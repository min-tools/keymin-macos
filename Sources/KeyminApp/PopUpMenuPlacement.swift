import AppKit

/// Chooses which way a `PopUpMenuButton` menu opens. Coordinates are AppKit's: the button view
/// is not flipped, so y = 0 is its bottom edge and y grows upward, and `popUp(positioning: nil,
/// at:)` places the menu's top-left corner at the given point. AppKit only scrolls a menu that
/// runs off the screen, so the direction has to be chosen here from the room on each side.
enum PopUpMenuPlacement {
    /// Space kept between the button and the menu.
    static let gap: CGFloat = 4
    /// The default placement: the menu hangs just below the button.
    static let below = NSPoint(x: 0, y: -gap)

    // origin(menuHeight, buttonHeight, buttonOnScreen, visibleFrame): Where to open the menu, in
    // the button view's coordinates. Below when the menu fits there, otherwise above when that
    // side has more room. A menu taller than both sides opens on the roomier side and lets AppKit
    // scroll it. The button rect and visible frame are both in screen coordinates.
    static func origin(menuHeight: CGFloat, buttonHeight: CGFloat, buttonOnScreen: NSRect, visibleFrame: NSRect) -> NSPoint {
        // The room on each side leaves the gap free, so a menu that exactly fills it still fits.
        let roomBelow = buttonOnScreen.minY - visibleFrame.minY - gap
        let roomAbove = visibleFrame.maxY - buttonOnScreen.maxY - gap
        guard menuHeight > roomBelow, roomAbove > roomBelow else { return below }
        // The point is the menu's top-left corner, so lift it by the menu height; an oversized
        // menu stops at the top of the visible area instead.
        return NSPoint(x: 0, y: buttonHeight + gap + min(menuHeight, roomAbove))
    }
}
