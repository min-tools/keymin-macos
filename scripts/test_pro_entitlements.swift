import Foundation

/// Trial arithmetic, Free-tier limits, and entitlement decisions, compiled with
/// ProEntitlementLogic.swift alone so no StoreKit or Apple Account is involved.
@main
struct EntitlementTests {
    // A fixed clock keeps every date check deterministic.
    static let now = Date(timeIntervalSince1970: 2_000_000)
    static let later = now.addingTimeInterval(3_600)

    // check(condition, message): Stop at the first failed check with its message.
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }

    // transaction(product, [expiration = nil], [revoked = false], [shared = false], [trial = false]):
    // A summary purchased at now; a revoked one is revoked at now too.
    static func transaction(_ product: String, expiration: Date? = nil, revoked: Bool = false,
                            shared: Bool = false, trial: Bool = false) -> KeyminTransactionSummary {
        KeyminTransactionSummary(
            productID: product,
            purchaseDate: now,
            expirationDate: expiration,
            revocationDate: revoked ? now : nil,
            isFamilyShared: shared,
            isIntroductoryOffer: trial
        )
    }

    // main(): Run the trial, Free-limit, and entitlement checks.
    static func main() {
        // The app's own trial lasts 30 days from its start, counted in whole days.
        let trialStart = now
        check(KeyminFreeAccessPolicy.isTrialActive(
            startedAt: trialStart,
            now: trialStart.addingTimeInterval(29 * 24 * 60 * 60)
        ), "The app trial lasts through day 29")
        check(!KeyminFreeAccessPolicy.isTrialActive(
            startedAt: trialStart,
            now: trialStart.addingTimeInterval(30 * 24 * 60 * 60)
        ), "The app trial expires after 30 days")
        check(KeyminFreeAccessPolicy.trialDaysRemaining(startedAt: trialStart, now: trialStart) == 30,
              "A new trial reports 30 days remaining")

        // TestFlight remains a test environment with production-style receipt metadata.
        let sandboxPurchaseDate = Date(timeIntervalSince1970: 1_375_340_400)
        check(KeyminFreeAccessPolicy.usesLocalTrialClock(
            transactionIsProduction: true, hasSandboxReceipt: true, originalPurchaseDate: now
        ), "A sandbox receipt identifies TestFlight")
        check(KeyminFreeAccessPolicy.usesLocalTrialClock(
            transactionIsProduction: true,
            hasSandboxReceipt: false,
            originalPurchaseDate: sandboxPurchaseDate
        ), "The fixed sandbox date identifies macOS TestFlight")
        check(!KeyminFreeAccessPolicy.usesLocalTrialClock(
            transactionIsProduction: true, hasSandboxReceipt: false, originalPurchaseDate: now
        ), "The production App Store keeps Apple's signed clock")
        check(KeyminFreeAccessPolicy.shouldRestartLocalTrial(
            firstAcceptance: false, isTestEnvironment: true, didMigrateTestClock: false
        ), "An existing test install receives the corrected clock once")
        check(!KeyminFreeAccessPolicy.shouldRestartLocalTrial(
            firstAcceptance: false, isTestEnvironment: true, didMigrateTestClock: true
        ), "A migrated test install keeps its clock")

        // Only usesAppStoreDate selects Apple's signed date; it never falls back to local state.
        let localStart = now.addingTimeInterval(24 * 60 * 60)
        check(KeyminFreeAccessPolicy.authoritativeTrialStartDate(
            appStoreOriginalPurchaseDate: now,
            localStartedAt: localStart,
            usesAppStoreDate: true
        ) == now, "The signed App Store date overrides local state")
        check(KeyminFreeAccessPolicy.authoritativeTrialStartDate(
            appStoreOriginalPurchaseDate: nil,
            localStartedAt: localStart,
            usesAppStoreDate: true
        ) == nil, "A missing signed date never falls back to local state")
        check(KeyminFreeAccessPolicy.authoritativeTrialStartDate(
            appStoreOriginalPurchaseDate: nil,
            localStartedAt: localStart,
            usesAppStoreDate: false
        ) == localStart, "Source builds retain their local trial date")

        // The Free tier shows the first five bindings and keeps the rest hidden but intact.
        let bindings = Array(1...8)
        check(KeyminFreeAccessPolicy.editableBindings(bindings, limited: false) == bindings,
              "Full access shows every binding")
        check(KeyminFreeAccessPolicy.editableBindings(bindings, limited: true) == [1, 2, 3, 4, 5],
              "Free shows the first five bindings in file order")
        check(KeyminFreeAccessPolicy.editableBindings([1, 2], limited: true) == [1, 2],
              "A short file is shown completely")
        check(KeyminFreeAccessPolicy.hiddenBindingCount(total: 8, limited: true) == 3,
              "Free reports how many bindings are hidden")
        check(KeyminFreeAccessPolicy.hiddenBindingCount(total: 8, limited: false) == 0
              && KeyminFreeAccessPolicy.hiddenBindingCount(total: 3, limited: true) == 0,
              "Nothing is hidden with full access or a short file")
        check(KeyminFreeAccessPolicy.canAddBinding(total: 4, limited: true)
              && !KeyminFreeAccessPolicy.canAddBinding(total: 5, limited: true)
              && KeyminFreeAccessPolicy.canAddBinding(total: 50, limited: false),
              "Free can add bindings only up to the limit")

        // Evaluation ignores unknown and revoked products and ranks the rest.
        check(!KeyminEntitlementLogic.evaluate([]).isPro, "No transaction is free")
        check(!KeyminEntitlementLogic.evaluate([transaction("unknown")]).isPro, "Unknown products are ignored")
        check(!KeyminEntitlementLogic.evaluate([
            transaction(KeyminProductID.lifetime, revoked: true)
        ]).isPro, "Revoked purchases are ignored")
        let lifetime = KeyminEntitlementLogic.evaluate([
            transaction(KeyminProductID.yearly, expiration: later),
            transaction(KeyminProductID.lifetime)
        ])
        check(lifetime.kind == .lifetime, "Lifetime access wins over subscription access")
        let owned = KeyminEntitlementLogic.evaluate([
            transaction(KeyminProductID.yearly, expiration: later, shared: true),
            transaction(KeyminProductID.yearly, expiration: later.addingTimeInterval(-10))
        ])
        check(!owned.isFamilyShared, "An owned subscription wins over a shared subscription")
        // Status lines for a StoreKit introductory offer follow the renewal flag.
        var trial = KeyminEntitlementLogic.evaluate([
            transaction(KeyminProductID.yearly, expiration: later, trial: true)
        ])
        trial.willAutoRenew = true
        check(KeyminEntitlementLogic.statusKind(for: trial, now: now) == .trialRenews(later),
              "A renewing trial reports its first payment date")
        trial.willAutoRenew = false
        check(KeyminEntitlementLogic.statusKind(for: trial, now: now) == .trialEnds(later),
              "A canceled trial reports its end date")
        print("Keymin trial, Free binding limit, and Pro entitlement decisions passed")
    }
}
