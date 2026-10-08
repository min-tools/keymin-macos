import AppKit

/// Placement checks for pop-up menus against the room above and below their button.
@main
struct PopUpPlacementTests {
    static var checks = 0

    // check(condition, message): Stop at the first failed check with its message; count the rest.
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
        checks += 1
    }

    // origin(buttonY y, menuHeight): Where a menu opens for a 24 pt button whose bottom
    // edge sits buttonY points above the bottom of a 1000 pt screen.
    static func origin(buttonY y: CGFloat, menuHeight: CGFloat) -> NSPoint {
        PopUpMenuPlacement.origin(
            menuHeight: menuHeight,
            buttonHeight: 24,
            buttonOnScreen: NSRect(x: 100, y: y, width: 120, height: 24),
            visibleFrame: NSRect(x: 0, y: 0, width: 1600, height: 1000)
        )
    }

    // main(): Check the default placement, flipping, clamping, and the Dock's hidden area.
    static func main() {
        // The default placement is what every fits-below case must return.
        let gap = PopUpMenuPlacement.gap
        check(PopUpMenuPlacement.below == NSPoint(x: 0, y: -gap), "The default placement hangs the menu just below the button")

        // Menus that fit below stay below, even when there is more room above.
        check(origin(buttonY: 500, menuHeight: 300) == PopUpMenuPlacement.below, "A menu that fits below opens below")
        check(origin(buttonY: 304, menuHeight: 300) == PopUpMenuPlacement.below, "A menu that exactly fills the room below still opens below")
        check(origin(buttonY: 900, menuHeight: 2000) == PopUpMenuPlacement.below, "A menu too tall for both sides opens below when that side is roomier")

        // Menus that would run off the bottom flip upward when there is more room above.
        let flipped = origin(buttonY: 150, menuHeight: 300)
        check(flipped.y == 24 + gap + 300, "A menu that fits above opens with its bottom edge just above the button")
        check(flipped.x == 0, "Flipped menus stay aligned with the button's leading edge")
        check(origin(buttonY: 0, menuHeight: 10).y == 24 + gap + 10, "A button at the screen edge opens upward")

        // A menu too tall for either side opens upward only as far as the screen allows.
        let clamped = origin(buttonY: 150, menuHeight: 2000)
        check(clamped.y == 24 + gap + (1000 - 174 - gap), "An oversized menu stops at the top of the visible area so AppKit can scroll it")

        // The room below is measured from the visible area, not from zero.
        let dock = PopUpMenuPlacement.origin(
            menuHeight: 100,
            buttonHeight: 24,
            buttonOnScreen: NSRect(x: 100, y: 150, width: 120, height: 24),
            visibleFrame: NSRect(x: 0, y: 100, width: 1600, height: 900)
        )
        check(dock.y == 24 + gap + 100, "Space hidden behind the Dock does not count as room below")

        print("\(checks) pop-up placement checks passed")
    }
}
