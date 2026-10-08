#!/usr/bin/env python3
"""Exercise the real paywall actions with suspended, isolated StoreKit substitutes."""
from pathlib import Path
import subprocess
import tempfile

from build import ROOT, swift_compiler

# Minimal stand-ins for the helpers, product type, and store that the paywall view compiles against.
fixture = r'''
import AppKit
import SwiftUI

// localized(key): Keep source text deterministic without a resource bundle.
func localized(_ key: String) -> String { key }
// localizedFormat(format, argument): Format the paywall's single-string messages.
func localizedFormat(_ format: String, _ argument: String) -> String {
    String(format: format, argument)
}
extension View {
    // keyboardFocusable(): Leave fixture views unchanged; focus is outside these tests.
    func keyboardFocusable() -> some View { self }
}
enum KeyminProFeature: String { case example = "Example" }
struct Product { let displayPrice = "$1.00" }

// Suspend each store call so assertions observe the UI while that action is pending.
@MainActor final class KeyminProStore: ObservableObject {
    enum PurchaseOutcome { case unlocked, pending, cancelled }
    struct Failure: LocalizedError {
        var errorDescription: String? { "Test store error" }
    }
    static let manageSubscriptionsURL = URL(string: "https://example.com")!
    @Published var isLoading = false
    var storeError: String?
    struct Entitlement { enum Kind { case none, subscription }; var kind = Kind.none }
    var entitlement = Entitlement()
    var isPro = false
    var isAppTrialActive = true
    var yearly: Product?, lifetime: Product?
    var outcome: PurchaseOutcome = .cancelled
    var restored = false
    var calls: [String] = []
    var continuation: CheckedContinuation<Void, Error>?
    var statusText: String { "Pro trial · 24 days remaining" }
    // suspend(action): Record the operation and wait for complete() to release it.
    func suspend(_ action: String) async throws {
        calls.append(action)
        try await withCheckedThrowingContinuation { continuation = $0 }
    }
    // refreshProducts(): Mirror loading/error state while the product request is paused.
    func refreshProducts() async {
        isLoading = true
        storeError = nil
        defer { isLoading = false }
        do { try await suspend("load") }
        catch { storeError = error.localizedDescription }
    }
    // purchase(product, confirmIn window): Ignore the stub product and optional window;
    // return the selected outcome once the simulated request completes.
    func purchase(_ product: Product, confirmIn window: NSWindow?) async throws -> PurchaseOutcome {
        try await suspend("purchase")
        return outcome
    }
    // restore(): Wait for the simulated request, then return the selected restore result.
    func restore() async throws -> Bool {
        try await suspend("restore")
        return restored
    }
    // complete([failing=false]): Release the suspended operation, optionally with an error.
    func complete(failing: Bool = false) {
        let pending = continuation!
        continuation = nil
        // Error paths must release the same continuation as successful requests.
        if failing { pending.resume(throwing: Failure()) }
        else {
            // A successful request lets the caller return its configured result.
            pending.resume()
        }
    }
}
'''
# Compile the complete production view and its state; replace only external store access.
source = (ROOT / 'Sources/KeyminApp/ProStore.swift').read_text()
fixture += (ROOT / 'Sources/KeyminApp/BuildEdition.swift').read_text()
# The slice starts after the state class's @MainActor line, so restore it. Dropping `private`
# lets the test call the view's own actions and read its progress state.
fixture += '@MainActor\n' + source[source.index('private final class KeyminPaywallState:'):].replace('private ', '')
# The test program drives the real view's actions against the suspended store.
fixture += r'''
@main enum PaywallTests {
    // main(): Exercise the production view's actions against the suspended store.
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        var checks = 0
        // check(condition, message): Stop at a failed assertion and count passing checks.
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            guard condition() else { fatalError(message) }
            checks += 1
        }
        // waitFor(condition): Bound waits so a missing action transition fails clearly.
        func waitFor(_ condition: () -> Bool) async throws {
            for _ in 0..<2000 {
                // Stop polling once the action reaches its expected state.
                if condition() { return }
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            fatalError("Timed out waiting for the paywall action")
        }
        let store = KeyminProStore()
        let state = KeyminPaywallState()
        let view = KeyminProView(store: store, feature: nil, state: state, resize: { _ in })
        check(!view.isWorking && view.progressText == nil, "Idle has no progress label")

        // Price loading uses neutral wording and blocks competing purchase/restore actions.
        let loading = Task { await view.load() }
        try await waitFor { store.continuation != nil }
        check(view.isWorking, "Loading is busy")
        check(view.progressText == "Loading App Store products…", "Price loading is not restoring")
        view.buy(Product())
        view.restore()
        check(store.calls == ["load"], "Busy loading rejects competing operations")
        store.complete()
        await loading.value
        check(!view.isWorking && view.progressText == nil, "Loading clears progress")

        // Both purchase products follow the same action; cancellation, pending, and success clear busy state.
        for outcome in [KeyminProStore.PurchaseOutcome.cancelled, .pending, .unlocked] {
            store.outcome = outcome
            view.buy(Product())
            check(view.progressText == "Contacting the App Store…", "Purchase never says restoring")
            try await waitFor { store.continuation != nil }
            check(store.calls.last == "purchase", "Purchase calls the purchase API")
            let callCount = store.calls.count
            view.restore()
            view.buy(Product())
            check(store.calls.count == callCount, "Busy purchase rejects duplicate actions")
            store.complete()
            try await waitFor { !view.isWorking }
            check(view.progressText == nil, "Completed purchase clears progress")
            switch outcome {
            case .cancelled: check(state.message == nil, "Cancel does not unlock")
            case .pending: check(state.message == "The purchase is awaiting approval.",
                                 "Pending approval does not unlock")
            case .unlocked: check(state.message == nil, "Success reports unlocked access")
            }
        }

        // Restore alone displays restoring, including the no-purchase and successful cases.
        for restored in [false, true] {
            store.restored = restored
            view.restore()
            check(view.progressText == "Restoring…", "Restore keeps its specific label")
            try await waitFor { store.continuation != nil }
            check(store.calls.last == "restore", "Restore calls the restore API")
            store.complete()
            try await waitFor { !view.isWorking }
            check(view.progressText == nil, "Restore clears progress")
            check(restored ? state.message == nil : state.message == "No Keymin Pro purchase was found for this Apple Account.",
                  "Restore reports the actual entitlement result")
        }

        // Errors must leave controls usable and preserve the relevant error message.
        for restoring in [false, true] {
            // Exercise the restore error path.
            if restoring { view.restore() } else {
                // Exercise the purchase error path with the same failure injection.
                view.buy(Product())
            }
            try await waitFor { store.continuation != nil }
            store.complete(failing: true)
            try await waitFor { !view.isWorking }
            check(view.progressText == nil && state.message == "Test store error",
                  "Failed action clears progress and reports its error")
        }
        let failedLoad = Task { await view.load() }
        try await waitFor { store.continuation != nil }
        store.complete(failing: true)
        await failedLoad.value
        check(!view.isWorking && view.progressText == nil && store.storeError == "Test store error",
              "Failed product loading clears progress and remains retryable")
        print("Keymin paywall: \(checks) action and progress checks passed")
    }
}
'''
# Write the assembled program to a scratch directory, compile it, and run it with a time limit.
with tempfile.TemporaryDirectory(prefix='keymin-paywall-test-', dir='/private/tmp') as directory:
    folder = Path(directory)
    main = folder / 'main.swift'
    main.write_text(fixture)
    binary = folder / 'tests'
    subprocess.run(swift_compiler() + [
        '-parse-as-library', '-swift-version', '5', '-target', 'arm64-apple-macos14.0',
        '-module-cache-path', str(folder / 'modules'), str(main),
        '-framework', 'AppKit', '-framework', 'SwiftUI', '-o', str(binary),
    ], check=True)
    subprocess.run([str(binary)], check=True, timeout=30)
