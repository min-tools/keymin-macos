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
