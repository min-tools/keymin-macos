import AppKit
import SwiftUI

/// One entry of a pop-up menu built for a `PopUpMenuButton`.
enum PopUpMenuEntry {
    /// A selectable row; the closure runs when the user picks it.
    case item(String, image: NSImage? = nil, action: () -> Void)
    /// A section heading that cannot be selected.
    case header(String)
    case separator
    /// A row that opens a nested menu of the given entries.
    case submenu(String, [PopUpMenuEntry])
}

/// A styled SwiftUI button that opens a native AppKit menu. Its background view
/// anchors the menu to the custom button's full frame.
struct PopUpMenuButton<Label: View>: View {
    /// What VoiceOver reads for the button; the visible label is often just a symbol or key cap.
    let accessibilityLabel: String
    @ViewBuilder let label: () -> Label
    /// Built on every click, so lists such as running apps are always current.
    let entries: () -> [PopUpMenuEntry]
    @State private var anchor = PopUpMenuAnchorBox()

    var body: some View {
        // The anchor view sits in the button's background, so the click hands the fresh entries
        // to it and it pops the menu up from the button's own frame.
        Button {
            anchor.view?.present(entries())
        } label: {
            label()
                .contentShape(Rectangle())
        }
        .buttonStyle(.bare)
        .keyboardFocusable()
        .background(PopUpMenuAnchor(box: anchor))
        .accessibilityLabel(accessibilityLabel)
    }
}

/// Holds the anchor view so the button action can reach it.
final class PopUpMenuAnchorBox {
    var view: PopUpMenuAnchorView?
}

/// Places a `PopUpMenuAnchorView` behind the button and hands it to the box.
private struct PopUpMenuAnchor: NSViewRepresentable {
    let box: PopUpMenuAnchorBox

    // makeNSView(context): Create the anchor view and register it in the box.
    func makeNSView(context: Context) -> PopUpMenuAnchorView {
        let view = PopUpMenuAnchorView()
        box.view = view
        return view
    }

    // updateNSView(nsView, context): Keep the box pointing at this view across updates.
    func updateNSView(_ nsView: PopUpMenuAnchorView, context: Context) {
        box.view = nsView
    }
}

/// An invisible view the size of the button that knows where to pop the menu up.
final class PopUpMenuAnchorView: NSView {
    private let target = PopUpMenuTarget()
    /// Kept alive until the next menu: AppKit may deliver the chosen item's action after
    /// `popUp` returns, and the items must still exist then.
    private var activeMenu: NSMenu?

    /// No intrinsic size, so the view takes exactly the button's frame.
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    // present(entries): Build the menu for the entries and pop it up below or above the button.
    func present(_ entries: [PopUpMenuEntry]) {
        guard let window else { return }
        let menu = buildMenu(entries)
        activeMenu = menu
        menu.popUp(positioning: nil, at: menuOrigin(for: menu, in: window), in: self)
    }

    // menuOrigin(for menu, in window): Find the anchor in this view's coordinates: below
    // when it fits on screen there, otherwise above when that side has more room.
    private func menuOrigin(for menu: NSMenu, in window: NSWindow) -> NSPoint {
        // Compare the button's screen rect with the visible area of the window's screen.
        guard let screen = window.screen ?? NSScreen.main else { return PopUpMenuPlacement.below }
        let onScreen = window.convertToScreen(convert(bounds, to: nil))
        return PopUpMenuPlacement.origin(menuHeight: menu.size.height, buttonHeight: bounds.height, buttonOnScreen: onScreen, visibleFrame: screen.visibleFrame)
    }

    // buildMenu(entries): Build a fresh menu, dropping the closures of the previous one.
    func buildMenu(_ entries: [PopUpMenuEntry]) -> NSMenu {
        target.actions.removeAll()
        let menu = NSMenu()
        menu.autoenablesItems = false
        populate(menu, with: entries)
        return menu
    }

    // populate(menu, with entries): Add menu rows, recursing into submenus. Closures
    // are kept by the target, keyed by the item's identity.
    private func populate(_ menu: NSMenu, with entries: [PopUpMenuEntry]) {
        for entry in entries {
            switch entry {
            case .item(let title, let image, let action):
                // The target finds the closure by the item's identity when the item fires.
                let item = NSMenuItem(title: title, action: #selector(PopUpMenuTarget.handleMenuItem(_:)), keyEquivalent: "")
                item.target = target
                item.image = image
                target.actions[ObjectIdentifier(item)] = action
                menu.addItem(item)
            case .header(let title):
                menu.addItem(.sectionHeader(title: title))
            case .separator:
                menu.addItem(.separator())
            case .submenu(let title, let children):
                // Nested items share the same target, so they are routed like top-level ones.
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                let submenu = NSMenu(title: title)
                submenu.autoenablesItems = false
                populate(submenu, with: children)
                item.submenu = submenu
                menu.addItem(item)
            }
        }
    }
}

/// Routes menu item actions back to their closures. The method name must not collide with
/// `NSObject`'s `perform(_:)`, or `#selector` picks `performSelector:` and the call crashes.
private final class PopUpMenuTarget: NSObject {
    var actions: [ObjectIdentifier: () -> Void] = [:]

    // handleMenuItem(item): Run the closure registered for the chosen item.
    @objc func handleMenuItem(_ item: NSMenuItem) {
        actions[ObjectIdentifier(item)]?()
    }
}
