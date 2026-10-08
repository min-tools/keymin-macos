import SwiftUI

extension View {
    // keyboardFocusable(): Leave fixture views unchanged; tests do not exercise focus.
    func keyboardFocusable() -> some View { self }
}

/// Replaces preferences so the test never changes the workstation's user settings.
final class TrialPreferences {
    var values: [String: Any] = [:]
    // bool(forKey key): Read a saved disclosure flag.
    func bool(forKey key: String) -> Bool { values[key] as? Bool ?? false }
    // object(forKey key): Read a saved local trial date.
    func object(forKey key: String) -> Any? { values[key] }
    // set(value, forKey key): Save trial state only in this fixture's memory.
    func set(_ value: Any, forKey key: String) { values[key] = value }
}

/// Supplies verified app transactions, with optional suspension or lookup failure.
@MainActor enum TrialFixture {
    enum Environment { case production, sandbox }
    struct Transaction {
        var bundleID = KeyminEdition.bundleIdentifier
        var environment = Environment.sandbox
        var originalPurchaseDate = Date(timeIntervalSince1970: 0)
    }
    enum Verification { case verified(Transaction) }
    struct Failure: Error {}
    static let defaults = TrialPreferences()
    static var transaction = Transaction()
    static var shouldFail = false
    static var shouldSuspend = false
    static var continuation: CheckedContinuation<Void, Never>?
    static var shared: Verification {
        get async throws {
            // Pause the post-welcome read so the test can inspect the intermediate state.
            if shouldSuspend {
                await withCheckedContinuation { continuation = $0 }
            }
            // A failed signed lookup must never grant a local App Store trial.
            if shouldFail { throw Failure() }
            return .verified(transaction)
        }
    }
}

@main enum TrialStartupTests {
    // waitFor(condition): Bound each asynchronous wait so a broken transition fails clearly.
    @MainActor static func waitFor(_ condition: () -> Bool) async throws {
        for _ in 0..<2000 {
            // Stop polling as soon as the expected asynchronous transition occurs.
            if condition() { return }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        fatalError("Trial startup did not complete")
    }

    // main(): Check welcome, delayed lookup, expiry, production dates, and failed verification.
    @MainActor static func main() async throws {
        let now = Date()
        let old = now.addingTimeInterval(-31 * 24 * 60 * 60)
        let startKey = "KeyminAppTrialStartedAt"
        let acceptedKey = "KeyminAppTrialDisclosureAccepted"
        let store = KeyminProStore()
        store.hasResolvedEntitlement = true

        // A source build starts its local trial synchronously after the welcome.
        if !KeyminEdition.isAppStoreBuild {
            precondition(!store.hasPreparedFreeAccess && !store.isLimitedToFreeBindings)
            store.beginAppTrial(now: now)
            precondition(store.hasPreparedFreeAccess && store.hasFullAccess)
            precondition(store.appTrialStartedAt == now)
            print("Source trial startup passed")
            return
        }

        // StoreKit may finish its startup read while the welcome alert is still open.
        await store.refreshAppTrial(now: now)
        precondition(store.hasResolvedAppTrial && store.appTrialStartedAt == nil)
        precondition(!store.hasPreparedFreeAccess && !store.isLimitedToFreeBindings,
                     "A sandbox trial awaiting consent must not look expired")

        // Dismissing the alert must not briefly unlock the expired banner during a slow read.
        TrialFixture.shouldSuspend = true
        store.beginAppTrial(now: now)
        try await waitFor { TrialFixture.continuation != nil }
        precondition(!store.hasPreparedFreeAccess && !store.isLimitedToFreeBindings,
                     "The post-welcome trial lookup is still pending")
        TrialFixture.shouldSuspend = false
        TrialFixture.continuation?.resume()
        TrialFixture.continuation = nil
        try await waitFor { !store.isTrialWelcomePending }
        precondition(store.hasPreparedFreeAccess && store.hasFullAccess)
        precondition(store.appTrialStartedAt == now,
                     "Sandbox uses the accepted local clock, not Apple's fixed test date")

        // A returning sandbox user keeps the original clock and receives Free limits after expiry.
        TrialFixture.defaults.values = [startKey: old, acceptedKey: true]
        let expired = KeyminProStore()
        expired.hasResolvedEntitlement = true
        expired.beginAppTrial(now: now)
        try await waitFor { !expired.isTrialWelcomePending }
        precondition(expired.appTrialStartedAt == old && expired.isLimitedToFreeBindings)

        // Production must use its signed date even if local preferences claim a fresh trial.
        TrialFixture.defaults.values = [startKey: now]
        TrialFixture.transaction.environment = .production
        TrialFixture.transaction.originalPurchaseDate = old
        let production = KeyminProStore()
        production.hasResolvedEntitlement = true
        await production.refreshAppTrial(now: now)
        precondition(!production.hasPreparedFreeAccess,
                     "Even an expired production trial waits for the welcome to close")
        production.beginAppTrial(now: now)
        try await waitFor { !production.isTrialWelcomePending }
        precondition(production.appTrialStartedAt == old && production.isLimitedToFreeBindings)

        // Failure hides no permanent limit and never falls back to a resettable local clock.
        TrialFixture.shouldFail = true
        let failed = KeyminProStore()
        failed.hasResolvedEntitlement = true
        failed.beginAppTrial(now: now)
        try await waitFor { !failed.isTrialWelcomePending }
        precondition(failed.appTrialStartedAt == nil && !failed.hasFullAccess)
        precondition(failed.isLimitedToFreeBindings)
        print("App Store trial startup, delayed lookup, expiry, and verification failure passed")
    }
}
