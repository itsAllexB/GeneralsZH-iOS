/*
**	Command & Conquer Generals Zero Hour(tm)
**	Copyright 2025 Electronic Arts Inc.
**
**	This program is free software: you can redistribute it and/or modify
**	it under the terms of the GNU General Public License as published by
**	the Free Software Foundation, either version 3 of the License, or
**	(at your option) any later version.
**
**	This program is distributed in the hope that it will be useful,
**	but WITHOUT ANY WARRANTY; without even the implied warranty of
**	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
**	GNU General Public License for more details.
**
**	You should have received a copy of the GNU General Public License
**	along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

// GeneralsX @feature iOS port 11/11/2026 A hardware mouse and keyboard: the decisions, without UIKit
// or GameController, so they can be tested on the Mac (`swift test`). HardwareInput.swift applies them.
//
//   - MouseMotion: GameController's raw mouse counts (GCMouseInput.mouseMovedHandler, Y up) to the
//     game window's points (Y down). The system pointer is not used: an iPhone never locks it to the
//     app, and over a display that takes no input there is none.
//   - ScrollFilter: the scroll wheel's raw values to wheel notches, vertical on GameController's first
//     axis (negative = up), and a Magic Keyboard trackpad's double report with one stale axis dropped.
//   - MouseButtons: several mice at once (Bluetooth and a hub's): a button is down while any mouse
//     holds it, and a mouse that goes away lets go of what it held.
//   - TypedText: which of a key press's characters (UIKey.characters) are text for a game text field.

import Foundation

/// A mouse's raw motion to the game window's points.
public enum MouseMotion {
    /// One count is one point on a window 1080 points high, proportionally less on a smaller one,
    /// so a hand movement crosses about the same share of the picture on the phone and on a monitor.
    public static let referenceHeight = 1080.0

    public static func points(deltaX: Double, deltaY: Double, windowHeight: Double, speed: Double = 1.0)
        -> (x: Double, y: Double) {
        let scale = max(windowHeight, 1) / referenceHeight * speed
        return (deltaX * scale, -deltaY * scale)
    }
}

/// GameController's scroll values to wheel notches (SDL's convention: positive y is away from the user).
public struct ScrollFilter: Equatable, Sendable {
    private var lastFirst: Double = 0
    private var lastSecond: Double = 0

    public init() {}

    /// GameController reports both axes when either changes; on a Magic Keyboard's trackpad it calls
    /// twice per movement with one stale axis in each call. Only an axis that changed counts, and a
    /// movement that is clearly along one axis drops the other.
    public mutating func notches(first: Double, second: Double) -> (horizontal: Double, vertical: Double) {
        let verticalChanged = first != lastFirst
        let horizontalChanged = second != lastSecond
        lastFirst = first
        lastSecond = second
        let mostlyVertical = abs(first) > 2 * abs(second)
        let mostlyHorizontal = abs(second) > 2 * abs(first)
        let vertical = verticalChanged && !mostlyHorizontal ? -first : 0
        let horizontal = horizontalChanged && !mostlyVertical ? second : 0
        return (horizontal.isFinite ? horizontal : 0, vertical.isFinite ? vertical : 0)
    }
}

/// Buttons held across several mice.
public struct MouseButtons: Equatable, Sendable {
    /// SDL's button numbers.
    public static let left = 1, middle = 2, right = 3

    private var held: [Int: Set<Int>] = [:]   // button -> the mice holding it

    public init() {}

    /// A button changed on one mouse. Returns the change the game should see, if any: the first
    /// mouse to press a button presses it, the last to let go releases it.
    public mutating func change(button: Int, mouse: Int, pressed: Bool) -> Bool? {
        var holders = held[button] ?? []
        let before = !holders.isEmpty
        if pressed { holders.insert(mouse) } else { holders.remove(mouse) }
        held[button] = holders.isEmpty ? nil : holders
        let after = !holders.isEmpty
        return before == after ? nil : after
    }

    /// A mouse went away: the buttons only it held are released (returned in ascending order).
    public mutating func remove(mouse: Int) -> [Int] {
        var released: [Int] = []
        for (button, holders) in held where holders.contains(mouse) {
            var rest = holders
            rest.remove(mouse)
            held[button] = rest.isEmpty ? nil : rest
            if rest.isEmpty { released.append(button) }
        }
        return released.sorted()
    }

    public func isDown(_ button: Int) -> Bool { held[button] != nil }
}

/// Text a key press types into a game text field.
public enum TypedText {
    /// `characters` is UIKey.characters (the layout's, with Shift and Option applied). nil when the
    /// press types nothing: a shortcut (Control or Command held), or a key whose characters are not
    /// text (Return, Tab, Escape, Backspace and Delete are keys the game reads as keys; the arrows and
    /// function keys come as private-use characters or names).
    public static func text(characters: String, control: Bool, command: Bool) -> String? {
        if control || command || characters.isEmpty { return nil }
        for scalar in characters.unicodeScalars {
            let v = scalar.value
            if v < 0x20 || v == 0x7F { return nil }
            if (0xE000...0xF8FF).contains(v) { return nil }
            if (0xF0000...).contains(v) { return nil }
        }
        // UIKit names some special keys ("UIKeyInputUpArrow"): those are not text.
        if characters.count > 1, characters.hasPrefix("UIKeyInput") { return nil }
        return characters
    }
}
