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

// GeneralsX @feature iOS port 11/11/2026 Hardware mouse and keyboard decisions (HardwareInputPlan.swift).

import XCTest
@testable import GXLauncherCore

final class HardwareInputPlanTests: XCTestCase {
    func testMotionIsOneToOneAt1080AndYIsFlipped() {
        let m = MouseMotion.points(deltaX: 10, deltaY: 5, windowHeight: 1080)
        XCTAssertEqual(m.x, 10)
        XCTAssertEqual(m.y, -5, "GameController's Y runs up, the window's down")
    }

    func testMotionScalesWithTheWindow() {
        // The phone held landscape (~440 points high): the same hand movement crosses the same share.
        let phone = MouseMotion.points(deltaX: 1080, deltaY: 0, windowHeight: 440)
        XCTAssertEqual(phone.x, 440, accuracy: 0.001)
        XCTAssertEqual(MouseMotion.points(deltaX: 10, deltaY: 0, windowHeight: 1080, speed: 2).x, 20)
        XCTAssertGreaterThan(MouseMotion.points(deltaX: 10, deltaY: 0, windowHeight: 0).x, 0)
    }

    func testWheelUpIsPositive() {
        var f = ScrollFilter()
        XCTAssertEqual(f.notches(first: -1, second: 0).vertical, 1)
        XCTAssertEqual(f.notches(first: 1, second: 0).vertical, -1)
    }

    func testStaleAxisIsDropped() {
        var f = ScrollFilter()
        _ = f.notches(first: -2, second: 0)
        // The trackpad's second report repeats the vertical value and adds a horizontal one.
        let second = f.notches(first: -2, second: 0.3)
        XCTAssertEqual(second.vertical, 0, "unchanged axis")
        XCTAssertEqual(second.horizontal, 0, "mostly vertical movement: no sideways drift")
        var h = ScrollFilter()
        XCTAssertEqual(h.notches(first: 0, second: 3).horizontal, 3)
        XCTAssertEqual(h.notches(first: 0, second: 3).horizontal, 0)
    }

    func testOneMouse() {
        var b = MouseButtons()
        XCTAssertEqual(b.change(button: 1, mouse: 7, pressed: true), true)
        XCTAssertNil(b.change(button: 1, mouse: 7, pressed: true), "no second press")
        XCTAssertTrue(b.isDown(1))
        XCTAssertEqual(b.change(button: 1, mouse: 7, pressed: false), false)
        XCTAssertNil(b.change(button: 1, mouse: 7, pressed: false), "no release without a press")
    }

    func testTwoMiceShareAButton() {
        var b = MouseButtons()
        XCTAssertEqual(b.change(button: 3, mouse: 1, pressed: true), true)
        XCTAssertNil(b.change(button: 3, mouse: 2, pressed: true))
        XCTAssertNil(b.change(button: 3, mouse: 1, pressed: false), "the other mouse still holds it")
        XCTAssertEqual(b.change(button: 3, mouse: 2, pressed: false), false)
    }

    func testAMouseGoingAwayLetsGo() {
        var b = MouseButtons()
        _ = b.change(button: 1, mouse: 1, pressed: true)
        _ = b.change(button: 2, mouse: 1, pressed: true)
        _ = b.change(button: 2, mouse: 2, pressed: true)
        XCTAssertEqual(b.remove(mouse: 1), [1], "the middle button is still held by mouse 2")
        XCTAssertFalse(b.isDown(1))
        XCTAssertTrue(b.isDown(2))
        XCTAssertEqual(b.remove(mouse: 2), [2])
        XCTAssertEqual(b.remove(mouse: 3), [])
    }

    func testTypedText() {
        XCTAssertEqual(TypedText.text(characters: "a", control: false, command: false), "a")
        XCTAssertEqual(TypedText.text(characters: "A", control: false, command: false), "A")
        XCTAssertEqual(TypedText.text(characters: "ü", control: false, command: false), "ü")
        XCTAssertEqual(TypedText.text(characters: " ", control: false, command: false), " ")
        XCTAssertNil(TypedText.text(characters: "a", control: true, command: false), "Ctrl+A is a hotkey")
        XCTAssertNil(TypedText.text(characters: "c", control: false, command: true))
        XCTAssertNil(TypedText.text(characters: "\r", control: false, command: false), "Return is a key")
        XCTAssertNil(TypedText.text(characters: "\t", control: false, command: false))
        XCTAssertNil(TypedText.text(characters: "\u{1B}", control: false, command: false), "Escape")
        XCTAssertNil(TypedText.text(characters: "\u{7F}", control: false, command: false), "Delete")
        XCTAssertNil(TypedText.text(characters: "\u{F700}", control: false, command: false), "an arrow")
        XCTAssertNil(TypedText.text(characters: "UIKeyInputUpArrow", control: false, command: false))
        XCTAssertNil(TypedText.text(characters: "", control: false, command: false))
    }
}
