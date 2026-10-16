import Foundation

/// Product identifiers, which must match App Store Connect. The app's 30-day trial is independent
/// of them.
enum KeyminProductID {
    static let yearly = "tools.min.keymin.pro.yearly"
    static let lifetime = "tools.min.keymin.pro.lifetime"
    static let all = [yearly, lifetime]
}

/// Public builds start with a full-access trial, then drop to the Free tier: the first five
/// bindings stay visible and editable, and the rest of the file is kept but hidden. The trial
/// start choice and date arithmetic live here so tests can check them without StoreKit.
enum KeyminFreeAccessPolicy {
    static let trialLengthDays = 30
    static let freeBindingLimit = 5
    static let trialDuration: TimeInterval = TimeInterval(trialLengthDays * 24 * 60 * 60)

    /// Apple's fixed `AppTransaction.originalPurchaseDate` in StoreKit test environments.
    private static let sandboxOriginalPurchaseTime: TimeInterval = 1_375_340_400

    // isSandboxOriginalPurchaseDate(date): Detect Apple's fixed sandbox acquisition date.
    static func isSandboxOriginalPurchaseDate(_ date: Date) -> Bool {
        abs(date.timeIntervalSince1970 - sandboxOriginalPurchaseTime) < 1
    }

    // usesLocalTrialClock(transactionIsProduction, hasSandboxReceipt,
    // originalPurchaseDate): Choose a local clock for Xcode, sandbox, and TestFlight.
    static func usesLocalTrialClock(
        transactionIsProduction: Bool,
        hasSandboxReceipt: Bool,
        originalPurchaseDate: Date
    ) -> Bool {
        !transactionIsProduction || hasSandboxReceipt
            || isSandboxOriginalPurchaseDate(originalPurchaseDate)
    }

    // shouldRestartLocalTrial(firstAcceptance, isTestEnvironment,
    // didMigrateTestClock): Restart after first consent or once during test migration.
    static func shouldRestartLocalTrial(
        firstAcceptance: Bool,
        isTestEnvironment: Bool,
        didMigrateTestClock: Bool
    ) -> Bool {
        firstAcceptance || (isTestEnvironment && !didMigrateTestClock)
    }

    // authoritativeTrialStartDate(appStoreOriginalPurchaseDate, localStartedAt, usesAppStoreDate):
    // Pick the trial start: Apple's signed date when usesAppStoreDate, otherwise the local clock.
    // A missing signed date never falls back to resettable local state.
    static func authoritativeTrialStartDate(
        appStoreOriginalPurchaseDate: Date?,
        localStartedAt: Date?,
        usesAppStoreDate: Bool
    ) -> Date? {
        usesAppStoreDate ? appStoreOriginalPurchaseDate : localStartedAt
    }

    // isTrialActive(startedAt, [now = Date()]): True while now is before the trial's end.
    static func isTrialActive(startedAt: Date, now: Date = Date()) -> Bool {
        now < startedAt.addingTimeInterval(trialDuration)
    }

    // trialDaysRemaining(startedAt, [now = Date()]): Whole days left, rounded up, never negative.
    static func trialDaysRemaining(startedAt: Date, now: Date = Date()) -> Int {
        let seconds = startedAt.addingTimeInterval(trialDuration).timeIntervalSince(now)
        return max(0, Int(ceil(seconds / (24 * 60 * 60))))
    }

    // editableBindings(bindings, limited): The bindings a user may see and edit: the first five
    // when limited, otherwise all. Hidden bindings never leave the document.
    static func editableBindings<Binding>(_ bindings: [Binding], limited: Bool) -> [Binding] {
        limited ? Array(bindings.prefix(freeBindingLimit)) : bindings
    }

    // hiddenBindingCount(total, limited): How many of a file's bindings the Free tier hides.
    static func hiddenBindingCount(total: Int, limited: Bool) -> Int {
        limited ? max(0, total - freeBindingLimit) : 0
    }

    // canAddBinding(total, limited): Whether one more binding would still be within the Free
    // allowance.
    static func canAddBinding(total: Int, limited: Bool) -> Bool {
        !limited || total < freeBindingLimit
    }
}

/// The fields of a StoreKit transaction that the entitlement decision needs, so tests can build
/// them without StoreKit.
struct KeyminTransactionSummary: Equatable {
    var productID: String
    var purchaseDate: Date
    var expirationDate: Date?
    var revocationDate: Date?
    var isFamilyShared: Bool
    var isIntroductoryOffer: Bool
}

/// The access a verified purchase grants. `willAutoRenew` stays nil until the renewal lookup
/// answers; `isTrial` marks a StoreKit introductory offer, not the app's own trial.
struct KeyminEntitlement: Equatable {
    enum Kind: Equatable { case none, lifetime, subscription }
    var kind: Kind = .none
    var expirationDate: Date?
    var isTrial = false
    var isFamilyShared = false
    var willAutoRenew: Bool?
    var isPro: Bool { kind != .none }
    static let free = KeyminEntitlement()
}

/// The status line the Pro panel shows, with the date it mentions. The trial cases describe a
/// StoreKit introductory offer, which the products do not configure; the app's 30-day trial is
/// reported separately by the store.
enum KeyminStatusKind: Equatable {
    case free
    case active
    case lifetime
    case familyShared
    case trialRenews(Date)
    case trialEnds(Date)
    case trialUntil(Date)
    case renews(Date)
    case ends(Date)
    case activeUntil(Date)
}

/// Pure decisions over transaction summaries, kept free of StoreKit so tests can drive them.
enum KeyminEntitlementLogic {
    // evaluate(transactions): Reduce the current entitlements to one access level, ignoring
    // revoked and unknown products. StoreKit's current-entitlement sequence already accounts for
    // expiry and billing grace.
    static func evaluate(_ transactions: [KeyminTransactionSummary]) -> KeyminEntitlement {
        let live = transactions.filter {
            $0.revocationDate == nil && KeyminProductID.all.contains($0.productID)
        }
        // A lifetime purchase outranks any subscription.
        if let lifetime = preferred(live.filter { $0.productID == KeyminProductID.lifetime }) {
            return KeyminEntitlement(kind: .lifetime, isFamilyShared: lifetime.isFamilyShared)
        }
        guard let subscription = preferred(live.filter { $0.productID == KeyminProductID.yearly }) else {
            return .free
        }
        return KeyminEntitlement(
            kind: .subscription,
            expirationDate: subscription.expirationDate,
            isTrial: subscription.isIntroductoryOffer,
            isFamilyShared: subscription.isFamilyShared
        )
    }

    // preferred(candidates): The transaction that represents a product: an owned one over a
    // family-shared one, then the later expiry.
    private static func preferred(_ candidates: [KeyminTransactionSummary]) -> KeyminTransactionSummary? {
        candidates.max { first, second in
            // Ownership outranks expiry; a shared transaction sorts lower.
            if first.isFamilyShared != second.isFamilyShared { return first.isFamilyShared }
            return (first.expirationDate ?? .distantFuture) < (second.expirationDate ?? .distantFuture)
        }
    }

    // statusKind(for entitlement, [now = Date()]): Choose the status and its date.
    // now prevents showing a renewal or expiry date that has already passed.
    static func statusKind(for entitlement: KeyminEntitlement, now: Date = Date()) -> KeyminStatusKind {
        switch entitlement.kind {
        case .none:
            return .free
        case .lifetime:
            return entitlement.isFamilyShared ? .familyShared : .lifetime
        case .subscription:
            // Family members cannot see or manage the owner's renewal.
            if entitlement.isFamilyShared { return .familyShared }
            // A missing or elapsed expiry has no future billing date to show.
            guard let date = entitlement.expirationDate, date > now else { return .active }
            // Trial here is a StoreKit introductory offer, not the app's own trial.
            switch (entitlement.isTrial, entitlement.willAutoRenew) {
            case (true, .some(true)): return .trialRenews(date)
            case (true, .some(false)): return .trialEnds(date)
            case (true, .none): return .trialUntil(date)
            case (false, .some(true)): return .renews(date)
            case (false, .some(false)): return .ends(date)
            case (false, .none): return .activeUntil(date)
            }
        }
    }
}
