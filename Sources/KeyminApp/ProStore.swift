import AppKit
import StoreKit
import SwiftUI

/// Owns verified access: StoreKit purchases, the 30-day trial clock, and the Pro panel. Views
/// observe it for the current access level; the model forwards its changes to re-filter bindings.
@MainActor
final class KeyminProStore: ObservableObject {
    static let shared = KeyminProStore()
    /// Posted when the verified entitlement or the signed production trial date changes.
    static let entitlementDidChange = Notification.Name("KeyminProEntitlementDidChange")
    static let manageSubscriptionsURL = URL(string: "https://apps.apple.com/account/subscriptions")!

    /// How a purchase ended. `pending` means an approval such as Ask to Buy is still outstanding.
    enum PurchaseOutcome: Equatable { case unlocked, pending, cancelled }

    @Published private(set) var entitlement = KeyminEntitlement.free
    @Published private(set) var yearly: Product?
    @Published private(set) var lifetime: Product?
    @Published private(set) var storeError: String?
    @Published private(set) var isLoading = false
    /// When the trial began: Apple's signed acquisition date in production, a local clock elsewhere.
    @Published private(set) var appTrialStartedAt: Date?
    /// True once an App Store build has finished its signed lookup, whatever the outcome.
    @Published private(set) var hasResolvedAppTrial = false
    /// True once StoreKit's current entitlements have been read at least once.
    @Published private(set) var hasResolvedEntitlement = false
    /// Stays pending through the welcome alert and its subsequent trial lookup.
    @Published private(set) var isTrialWelcomePending = true

    private var updates: Task<Void, Never>?
    /// Counts refreshes so a slow, stale StoreKit read cannot overwrite a newer result.
    private var refreshGeneration = 0
    /// Schedules subscription checks up to a minute apart while the app is awake.
    private var entitlementTimer: Timer?
    /// Fires when the trial ends so views re-evaluate the access level.
    private var appTrialTimer: Timer?
    private var activationObserver: NSObjectProtocol?
    /// The open Pro panel; it clears this when its window closes.
    private var panel: NSWindowController?
    private let defaults = UserDefaults.standard

    // Preferences keys for the local trial clock and the accepted trial disclosure.
    private static let appTrialStartedAtKey = "KeyminAppTrialStartedAt"
    private static let appTrialDisclosureAcceptedKey = "KeyminAppTrialDisclosureAccepted"

    // Only a git-ignored private build input can grant local Pro access; nil means normal rules.
    private var developerOverride: Bool? { KeyminEdition.localProAccess }

    var isPro: Bool { developerOverride ?? entitlement.isPro }
    var isLocalBuild: Bool { developerOverride == true }
    /// The trial counts only in public builds and only until a purchase is verified.
    var isAppTrialActive: Bool {
        guard developerOverride == nil, !entitlement.isPro, let appTrialStartedAt else { return false }
        return KeyminFreeAccessPolicy.isTrialActive(startedAt: appTrialStartedAt)
    }
    var hasFullAccess: Bool { isPro || isAppTrialActive }
    /// Wait for the welcome and its trial lookup before applying Free limits. Private builds
    /// and expired-trial previews have no welcome step.
    var hasPreparedFreeAccess: Bool {
        isLocalBuild || KeyminEdition.isExpiredTrialPreview
            || (!isTrialWelcomePending && (appTrialStartedAt != nil || hasResolvedAppTrial))
    }
    /// True after the trial without a verified purchase, once StoreKit state is known.
    var isLimitedToFreeBindings: Bool { hasResolvedEntitlement && hasPreparedFreeAccess && !hasFullAccess }

    var statusText: String {
        // Private unlocked builds show their own status text.
        if isLocalBuild {
            return KeyminEdition.localAccessStatus ?? localized("Pro")
        }
        // The app's own trial counts down in whole days.
        if isAppTrialActive, let appTrialStartedAt {
            let days = KeyminFreeAccessPolicy.trialDaysRemaining(startedAt: appTrialStartedAt)
            return days == 1 ? localized("Pro trial · 1 day remaining")
                : localizedFormat("Pro trial · %lld days remaining", Int64(days))
        }
        // Other states follow the entitlement; any date shows without a time.
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        switch KeyminEntitlementLogic.statusKind(for: entitlement) {
        case .free: return localizedFormat("Free · the first %lld bindings can be edited", Int64(KeyminFreeAccessPolicy.freeBindingLimit))
        case .active: return localized("Pro")
        case .lifetime: return localized("Lifetime")
        case .familyShared: return localized("Shared with your family")
        case .trialRenews(let date): return localizedFormat("Pro trial · first payment %@", formatter.string(from: date))
        case .trialEnds(let date): return localizedFormat("Pro trial · ends %@", formatter.string(from: date))
        case .trialUntil(let date): return localizedFormat("Pro trial · until %@", formatter.string(from: date))
        case .renews(let date): return localizedFormat("Renews %@", formatter.string(from: date))
        case .ends(let date): return localizedFormat("Expires %@", formatter.string(from: date))
        case .activeUntil(let date): return localizedFormat("Until %@", formatter.string(from: date))
        }
    }

    // start(): Begin StoreKit observation and the first entitlement read once per launch; private
    // unlocked builds skip StoreKit entirely.
    func start() {
        guard developerOverride == nil else {
            hasResolvedEntitlement = true
            return
        }
        // Source and private previews restore their local trial immediately.
        if !KeyminEdition.isAppStoreBuild {
            prepareLocalFreeAccess()
        }
        guard updates == nil else { return }
        // Finish each verified transaction so the App Store stops redelivering it, then re-read.
        updates = Task { [weak self] in
            for await update in StoreKit.Transaction.updates {
                // Finish only verified transactions; unverified ones are left unfinished.
                if case .verified(let transaction) = update { await transaction.finish() }
                await self?.refreshEntitlement()
            }
        }
        // Recheck after wake or an Apple Account change while the app was inactive.
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Timers do not fire during sleep, so reschedule the local trial's expiry.
                if !KeyminEdition.isAppStoreBuild {
                    self.prepareLocalFreeAccess()
                }
                self.objectWillChange.send()
                await self.refreshEntitlement()
            }
        }
        Task { [weak self] in await self?.refreshEntitlement() }
    }

    // deinit(): Stop the update stream, timers, and activation observer.
    deinit {
        updates?.cancel()
        entitlementTimer?.invalidate()
        appTrialTimer?.invalidate()
        // The observer exists only after start() ran in a public build.
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
    }

    // loadProducts(): Fetch the yearly and lifetime products; throws when neither is on sale.
    func loadProducts() async throws {
        guard developerOverride == nil else { return }
        isLoading = true
        storeError = nil
        defer { isLoading = false }
        let products = try await Product.products(for: KeyminProductID.all)
        let yearly = products.first { $0.id == KeyminProductID.yearly }
        let lifetime = products.first { $0.id == KeyminProductID.lifetime }
        guard yearly != nil || lifetime != nil else {
            throw StoreFailure(localized("Pro purchases are unavailable right now. Please try again later."))
        }
        self.yearly = yearly
        self.lifetime = lifetime
    }

    // purchase(product, confirmIn window): Buy through StoreKit and report the result.
    // A nil window or older macOS uses the store's standalone confirmation.
    func purchase(_ product: Product, confirmIn window: NSWindow?) async throws -> PurchaseOutcome {
        // Local builds have nothing to buy.
        if developerOverride == true { return .unlocked }
        let result: Product.PurchaseResult
        // macOS 15.2 can show the confirmation as a sheet on the panel.
        if #available(macOS 15.2, *), let window {
            result = try await product.purchase(confirmIn: window, options: [])
        } else {
            // Older systems, or a missing window, get the App Store's own confirmation window.
            result = try await product.purchase(options: [])
        }
        switch result {
        case .success(let verification):
            // Only a verified transaction unlocks; finishing it confirms delivery to the App Store.
            guard case .verified(let transaction) = verification else {
                throw StoreFailure(localized("The App Store could not verify this purchase."))
            }
            await transaction.finish()
            await refreshEntitlement()
            return .unlocked
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .cancelled
        }
    }

    // restore(): Sync purchases with the App Store and report whether Pro access is now verified.
    func restore() async throws -> Bool {
        // Local builds are always unlocked.
        if developerOverride == true { return true }
        try await AppStore.sync()
        await refreshEntitlement()
        return isPro
    }

    // refreshProducts(): Load the products for the panel, keeping the failure text instead of
    // throwing.
    func refreshProducts() async {
        do {
            try await loadProducts()
        } catch {
            storeError = error.localizedDescription
        }
    }

    // present([feature = nil]): Show the Pro panel, naming the feature that prompted it, or bring
    // the open panel forward.
    func present(feature: KeyminProFeature? = nil) {
        // Reuse the open panel rather than stacking a second one.
        if let panel {
            panel.showWindow(nil)
            panel.window?.makeKeyAndOrderFront(nil)
            return
        }
        // The panel releases itself when its window closes.
        let controller = KeyminProPanelController(store: self, feature: feature)
        panel = controller
        controller.onClose = { [weak self] in self?.panel = nil }
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // refreshEntitlement(): Re-read the trial state and StoreKit's current entitlements, publish
    // the result, and schedule the next check.
    private func refreshEntitlement() async {
        guard developerOverride == nil else { return }
        await refreshAppTrial()
        refreshGeneration += 1
        let generation = refreshGeneration
        // Summarize every verified current entitlement; StoreKit has already dropped expired ones.
        var summaries: [KeyminTransactionSummary] = []
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            summaries.append(summary(of: transaction))
        }
        // A newer StoreKit refresh supersedes this result.
        guard generation == refreshGeneration else { return }
        // StoreKit's entitlement state is now known; post-trial UI waits for this flag.
        hasResolvedEntitlement = true
        var next = KeyminEntitlementLogic.evaluate(summaries)
        // Preserve known renewal state while refreshing the same entitlement.
        if next.kind == entitlement.kind,
           next.expirationDate == entitlement.expirationDate,
           next.isFamilyShared == entitlement.isFamilyShared {
            next.willAutoRenew = entitlement.willAutoRenew
        }
        applyEntitlement(next)
        scheduleEntitlementRefresh()
        // Publish verified access before an optional network-backed renewal lookup finishes.
        if next.kind == .subscription {
            next.willAutoRenew = await subscriptionWillAutoRenew(for: next)
            guard generation == refreshGeneration else { return }
            applyEntitlement(next)
        }
    }

    // beginAppTrial([now = Date()]): Record that the user accepted the trial disclosure and resolve
    // the trial start date.
    func beginAppTrial(now: Date = Date()) {
        defaults.set(true, forKey: Self.appTrialDisclosureAcceptedKey)
        // App Store builds must verify the transaction environment before choosing a clock.
        if KeyminEdition.isAppStoreBuild {
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.refreshAppTrial(now: now)
                self.isTrialWelcomePending = false
            }
        } else {
            // Source builds start or restore the local clock right away.
            prepareLocalFreeAccess(startTrialIfNeeded: true, now: now)
            isTrialWelcomePending = false
        }
    }

    // refreshAppTrial([now = Date()]): In App Store builds, resolve the trial from the signed app
    // transaction: Apple's acquisition date in production, the disclosed local clock in a verified
    // sandbox. Other builds return at once and leave hasResolvedAppTrial false.
    private func refreshAppTrial(now: Date = Date()) async {
        guard KeyminEdition.isAppStoreBuild else { return }
        defer {
            // Finish startup even on failure. A failed first lookup grants no trial;
            // a later failure keeps the previously verified in-memory start date.
            hasResolvedAppTrial = true
        }
        guard let result = try? await AppTransaction.shared,
              case .verified(let transaction) = result,
              transaction.bundleID == KeyminEdition.bundleIdentifier else {
            // A production build must never replace a failed signed lookup with local state.
            return
        }
        // Production counts from Apple's signed acquisition date, which the user cannot reset.
        if transaction.environment == .production {
            let authoritative = KeyminFreeAccessPolicy.authoritativeTrialStartDate(
                appStoreOriginalPurchaseDate: transaction.originalPurchaseDate,
                localStartedAt: nil,
                usesAppStoreDate: true
            )
            // The policy answers nil only without a signed date, which production always has.
            if let authoritative {
                applyAppTrialStartDate(authoritative, now: now)
            }
        } else {
            // Sandbox and Xcode environments use the local clock, started once the disclosure
            // was accepted.
            let accepted = defaults.bool(forKey: Self.appTrialDisclosureAcceptedKey)
            prepareLocalFreeAccess(
                startTrialIfNeeded: accepted,
                now: now,
                allowAppStoreSandbox: true
            )
        }
    }

    // prepareLocalFreeAccess([startTrialIfNeeded = false], [now = Date()],
    // [allowAppStoreSandbox = false]): Restore the local trial clock from preferences, start it
    // when asked and not yet started, and schedule its expiry.
    private func prepareLocalFreeAccess(
        startTrialIfNeeded: Bool = false,
        now: Date = Date(),
        allowAppStoreSandbox: Bool = false
    ) {
        // Only a verified sandbox transaction may use local state in an App Store build.
        guard !KeyminEdition.isAppStoreBuild || allowAppStoreSandbox else { return }
        // Private previews force a start date and must not change the real one in preferences.
        if let forced = KeyminEdition.forcedTrialStartedAt {
            appTrialStartedAt = forced
        } else if appTrialStartedAt == nil {
            // A running clock is left alone; otherwise preferences decide.
            // A stored date means the trial already began on this Mac.
            if let stored = defaults.object(forKey: Self.appTrialStartedAtKey) as? Date {
                appTrialStartedAt = stored
            } else if startTrialIfNeeded {
                // Start the clock now and keep it; a plain restore never starts a trial.
                appTrialStartedAt = now
                defaults.set(now, forKey: Self.appTrialStartedAtKey)
            }
        }
        scheduleAppTrialExpiry(now: now)
    }

    // applyAppTrialStartDate(startedAt, [now = Date()]): Publish the signed production trial date
    // without storing a resettable copy, then schedule the expiry.
    private func applyAppTrialStartDate(_ startedAt: Date, now: Date = Date()) {
        // Notify only on a real change so observers do not refresh needlessly.
        if appTrialStartedAt != startedAt {
            appTrialStartedAt = startedAt
            NotificationCenter.default.post(name: Self.entitlementDidChange, object: self)
        }
        scheduleAppTrialExpiry(now: now)
    }

    // scheduleAppTrialExpiry([now = Date()]): Publish the Free tier as soon as the trial expires.
    private func scheduleAppTrialExpiry(now: Date = Date()) {
        appTrialTimer?.invalidate()
        appTrialTimer = nil
        guard let appTrialStartedAt,
              KeyminFreeAccessPolicy.isTrialActive(startedAt: appTrialStartedAt, now: now) else {
            return
        }
        // The timer only nudges observers; the access properties re-evaluate against the clock.
        let expiry = appTrialStartedAt.addingTimeInterval(KeyminFreeAccessPolicy.trialDuration)
        appTrialTimer = Timer.scheduledTimer(
            withTimeInterval: max(1, expiry.timeIntervalSince(now)),
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.objectWillChange.send()
            }
        }
    }

    // applyEntitlement(updated): Publish a changed entitlement and post the change notification;
    // identical state is ignored.
    private func applyEntitlement(_ updated: KeyminEntitlement) {
        guard updated != entitlement else { return }
        entitlement = updated
        NotificationCenter.default.post(name: Self.entitlementDidChange, object: self)
    }

    // summary(of transaction): Keep the fields used by the entitlement decision.
    private func summary(of transaction: StoreKit.Transaction) -> KeyminTransactionSummary {
        let introductory: Bool
        // macOS 14.2 replaced the deprecated offerType with the offer object.
        if #available(macOS 14.2, *) {
            introductory = transaction.offer?.type == .introductory
        } else {
            // Older systems still expose the offer type directly.
            introductory = transaction.offerType == .introductory
        }
        return KeyminTransactionSummary(
            productID: transaction.productID,
            purchaseDate: transaction.purchaseDate,
            expirationDate: transaction.expirationDate,
            revocationDate: transaction.revocationDate,
            isFamilyShared: transaction.ownershipType == .familyShared,
            isIntroductoryOffer: introductory
        )
    }

    // subscriptionWillAutoRenew(for current): Look up this subscription's renewal,
    // or nil when StoreKit cannot answer.
    private func subscriptionWillAutoRenew(for current: KeyminEntitlement) async -> Bool? {
        guard current.kind == .subscription else { return nil }
        // Renewal status comes from the product, so load it if the panel has not yet.
        if yearly == nil { try? await loadProducts() }
        guard let statuses = try? await yearly?.subscription?.status else { return nil }
        // Use only the status for the shown entitlement, so an older transaction cannot answer.
        for status in statuses {
            guard case .verified(let transaction) = status.transaction,
                  transaction.productID == KeyminProductID.yearly,
                  transaction.revocationDate == nil,
                  transaction.expirationDate == current.expirationDate,
                  (transaction.ownershipType == .familyShared) == current.isFamilyShared,
                  case .verified(let renewal) = status.renewalInfo else { continue }
            return renewal.willAutoRenew
        }
        return nil
    }

    // scheduleEntitlementRefresh(): Re-read a subscription's entitlement at most a minute out, so a
    // renewal or lapse shows promptly without waiting for a StoreKit update.
    private func scheduleEntitlementRefresh() {
        entitlementTimer?.invalidate()
        entitlementTimer = nil
        guard entitlement.kind == .subscription else { return }
        // Poll each minute, or at the expiry if sooner; after expiry, until StoreKit drops it.
        let remaining = entitlement.expirationDate?.timeIntervalSinceNow ?? 60
        let delay = remaining > 0 ? max(1, min(60, remaining)) : 60
        entitlementTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.refreshEntitlement() }
        }
    }
}

/// A store error that carries a user-readable message.
private struct StoreFailure: LocalizedError {
    let message: String
    // init(message): Wrap a user-readable message.
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// Progress and message state shared by the purchase and restore actions, so only one runs at a
/// time and both report into the same place.
@MainActor
private final class KeyminPaywallState: ObservableObject {
    enum Operation { case purchasing, restoring }
    @Published var operation: Operation?
    @Published var message: String?

    /// The label shown while an action is running.
    var progressText: String? {
        switch operation {
        case .purchasing: return localized("Contacting the App Store…")
        case .restoring: return localized("Restoring…")
        case nil: return nil
        }
    }
}

/// Carries the Pro view's measured height up to the window controller.
private struct KeyminProPanelHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    // reduce(value, nextValue): Keep the tallest reported height.
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// The Pro panel's content: access status, purchase and restore actions, and the legal links.
private struct KeyminProView: View {
    @ObservedObject var store: KeyminProStore
    let feature: KeyminProFeature?
    @ObservedObject var state: KeyminPaywallState
    let resize: (CGFloat) -> Void

    /// True while products load or an action runs; every action is disabled then.
    private var isWorking: Bool { store.isLoading || state.operation != nil }
    private var progressText: String? {
        state.progressText ?? (store.isLoading ? localized("Loading App Store products…") : nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // The lead names the feature that opened the panel when there is one.
            VStack(alignment: .leading, spacing: 6) {
                Text(localized("Keymin Pro"))
                    .font(.system(size: 22, weight: .bold))
                Text(feature.map { localizedFormat("Unlock %@ and the rest of Keymin Pro.", localized($0.rawValue)) }
                     ?? localized("Edit every binding and use the Source page. Pay yearly, or once for lifetime access."))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                statusSection
                // One progress row replaces the purchase buttons while anything is running.
                if let progressText {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(progressText)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                } else if !store.isPro {
                    // Trial and Free users can purchase once the panel is idle.
                    purchaseButtons
                }
                // Errors and the pending-approval note appear under the actions.
                if let message = state.message {
                    Text(localized(message))
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                }
            }

            // Restore is offered until a purchase is verified.
            if !store.isPro {
                Button(localized("Restore Purchases")) { restore() }
                    .disabled(isWorking)
                    .buttonStyle(.link)
                    .keyboardFocusable()
            }

            // Keep legal links beside the close action in every store state.
            HStack {
                HStack(spacing: 16) {
                    Link(localized("Terms of Use (EULA)"), destination: AppLinks.termsOfUse)
                        .keyboardFocusable()
                    Link(localized("Privacy Policy"), destination: AppLinks.privacyPolicy)
                        .keyboardFocusable()
                }
                .font(.system(size: 11))
                .buttonStyle(.link)
                Spacer()
                Button(localized(store.isPro ? "OK" : "Close")) { NSApp.keyWindow?.close() }
                    .disabled(isWorking)
                    .keyboardFocusable()
                    .controlSize(.large)
                    .keyboardShortcut(store.isPro ? .defaultAction : .cancelAction)
            }
        }
        .padding(.init(top: 22, leading: 28, bottom: 24, trailing: 28))
        .frame(width: 556)
        .fixedSize(horizontal: false, vertical: true)
        // Report the laid-out height so the window can follow it, and load prices on appearance.
        .background(
            GeometryReader { geometry in
                Color.clear.preference(key: KeyminProPanelHeightKey.self, value: geometry.size.height)
            }
        )
        .onPreferenceChange(KeyminProPanelHeightKey.self, perform: resize)
        .task { await load() }
    }

    @ViewBuilder private var statusSection: some View {
        // Distinguish the free trial from a verified Pro purchase.
        if store.isPro || store.isAppTrialActive {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.isAppTrialActive
                     ? localized("Your Pro trial is active.")
                     : localized("You have Keymin Pro."))
                    .font(.system(size: 13))
                Text(localized(store.statusText))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            // Subscriptions are managed in the App Store, not inside the app.
            if store.isPro && store.entitlement.kind == .subscription {
                Button(localized("Manage Subscription")) {
                    NSWorkspace.shared.open(KeyminProStore.manageSubscriptionsURL)
                }
                    .buttonStyle(.link)
                    .keyboardFocusable()
            }
        } else {
            // Free after the trial: the status line names the binding limit.
            Text(localized(store.statusText))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var purchaseButtons: some View {
        // Yearly is the prominent choice, with its price under the button.
        if let yearly = store.yearly {
            Button { buy(yearly) } label: {
                Text(localized("Keymin Pro Yearly"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .keyboardFocusable()
            .controlSize(.large)
            Text(localizedFormat("%@ per year", yearly.displayPrice))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        // Lifetime is the secondary choice and shows its price inline.
        if let lifetime = store.lifetime {
            Button { buy(lifetime) } label: {
                Text(localizedFormat("Keymin Pro Lifetime · %@", lifetime.displayPrice))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .keyboardFocusable()
            .controlSize(.large)
        }
        // Without products, explain why and offer another load.
        if store.yearly == nil && store.lifetime == nil {
            Text(localized(store.storeError ?? "Purchases are unavailable right now."))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Button(localized("Try Again")) { Task { await load() } }
                .keyboardFocusable()
        }
        // The auto-renewal terms must sit beside the purchase buttons.
        Text(localized("Payment is charged to your Apple Account. The yearly subscription renews automatically unless you cancel it in App Store settings at least a day before the current period ends."))
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
    }

    // load(): Load the products, unless they are already loading or an action is running.
    private func load() async {
        guard !isWorking else { return }
        await store.refreshProducts()
    }

    // buy(product): Show purchase progress until success, cancellation, pending, or failure.
    private func buy(_ product: Product) {
        guard !isWorking else { return }
        state.operation = .purchasing
        state.message = nil
        Task {
            defer { state.operation = nil }
            do {
                let outcome = try await store.purchase(product, confirmIn: NSApp.keyWindow)
                // Pending means an approval is outstanding; nothing unlocks yet.
                if outcome == .pending { state.message = localized("The purchase is awaiting approval.") }
            } catch { state.message = error.localizedDescription }
        }
    }

    // restore(): Restore purchases under their own progress label, unless the panel is busy.
    private func restore() {
        guard !isWorking else { return }
        state.operation = .restoring
        state.message = nil
        Task {
            defer { state.operation = nil }
            do {
                // A sync that finds no purchase is reported, not treated as an error.
                if try await !store.restore() { state.message = localized("No Keymin Pro purchase was found for this Apple Account.") }
            } catch { state.message = error.localizedDescription }
        }
    }
}
