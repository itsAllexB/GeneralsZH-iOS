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

// GeneralsX @feature iOS port 11/11/2026 The phone as the trackpad while the game's picture is on an
// external display (ExternalDisplay.swift).
//
// The pad only reports; the engine decides what a gesture means (SDL3GameEngine.cpp,
// handleTouchpadEvent, the launcher's "Mouse and touchpad" mode without its direct menu taps):
//
//   fingers        -> finger events in the game window's coordinates, scaled by the finger gain
//                     (PointerMapping): move one to move the pointer, tap to click, two-finger tap
//                     to right-click, tap then touch again and drag for a selection box, two
//                     fingers to scroll the map and pinch to zoom
//   a mouse        -> GameController's raw motion and buttons (HardwareInput.swift); only a pointer
//                     GameController does not know (a pointer device without a GCMouse) is followed
//                     here, by where it hovers over the pad
//
// The phone's own pointer is hidden over the pad: the one that counts is on the display.

#if canImport(UIKit) && os(iOS)
import Foundation
import GameController
import UIKit
import GXLauncherCore

final class ExternalDisplayPadController: UIViewController {
    /// SDL's view controller: the phone keeps the orientations the game allows while the pad shows.
    weak var gameController: UIViewController?

    override func loadView() {
        view = ExternalDisplayPadView()
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        gameController?.supportedInterfaceOrientations ?? .all
    }

    // GeneralsX @feature iOS port 11/11/2026 With a mouse connected (HardwareInput.swift) its raw motion
    // drives the game's pointer; locking the system pointer keeps it from wandering over the pad. iPadOS
    // may grant it, an iPhone does not (the pointer is then hidden over the pad instead).
    override var prefersPointerLocked: Bool { HardwareInput.mouseConnected }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    // As SDL's controller with SDL_HINT_IOS_HIDE_HOME_INDICATOR=2 (SDL3Main.cpp): an edge swipe
    // needs a second swipe, so a palm on the edge does not take the app away mid-match.
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }
}

final class ExternalDisplayPadView: UIView, UIPointerInteractionDelegate {
    private struct Finger {
        let touch: UITouch
        let id: UInt64
    }

    private var fingers: [Finger] = []
    private var nextId: UInt64 = 1
    private var pointerButtons: [ObjectIdentifier: UInt64] = [:]
    private var loggedTouches = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        isMultipleTouchEnabled = true
        addInteraction(UIPointerInteraction(delegate: self))
        addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hovered(_:))))
        buildHint()
    }

    required init?(coder: NSCoder) { fatalError("made in code") }

    func pointerInteraction(_ interaction: UIPointerInteraction, styleFor region: UIPointerRegion) -> UIPointerStyle? {
        .hidden()
    }

    private func buildHint() {
        let icon = UIImageView(image: UIImage(systemName: "display"))
        icon.tintColor = UIColor(white: 0.55, alpha: 1)
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 40, weight: .light)
        let title = UILabel()
        title.text = L("The game is on the external display")
        title.font = .preferredFont(forTextStyle: .headline)
        title.textColor = UIColor(white: 0.8, alpha: 1)
        title.textAlignment = .center
        title.numberOfLines = 0
        let hints = UILabel()
        hints.text = [
            L("Move a finger here to move the pointer"),
            L("Tap to click · tap with two fingers to right-click"),
            L("Tap, then touch again and drag for a selection box"),
            L("Two fingers: drag to scroll the map, pinch to zoom"),
        ].joined(separator: "\n")
        hints.font = .preferredFont(forTextStyle: .footnote)
        hints.textColor = UIColor(white: 0.5, alpha: 1)
        hints.textAlignment = .center
        hints.numberOfLines = 0
        let stack = UIStackView(arrangedSubviews: [icon, title, hints])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.85),
        ])
    }

    // MARK: - Fingers

    /// Finger positions in the game window's coordinates (fractions of its points, as SDL's own
    /// finger events), scaled so the pointer's speed suits the display.
    private func gameFraction(_ touch: UITouch) -> (Double, Double) {
        let p = touch.location(in: self)
        let game = MainActor.assumeIsolated { ExternalDisplay.shared.gamePoints }
        let gw = max(Double(game.width), 1), gh = max(Double(game.height), 1)
        let gain = PointerMapping.fingerGain(pad: (Double(bounds.width), Double(bounds.height)), picture: (gw, gh))
        return (Double(p.x) * gain / gw, Double(p.y) * gain / gh)
    }

    private func send(_ kind: PadEventKind, _ id: UInt64, _ x: Double, _ y: Double) {
        MainActor.assumeIsolated { ExternalDisplay.shared.send(kind, id: id, x: x, y: y) }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            if touch.type == .indirectPointer {
                pointerPressed(touch, event: event)
                continue
            }
            let finger = Finger(touch: touch, id: nextId)
            nextId += 1
            fingers.append(finger)
            let (x, y) = gameFraction(touch)
            send(.fingerDown, finger.id, x, y)
            if loggedTouches < 6 {
                loggedTouches += 1
                LauncherRunner.log("external display: pad finger \(finger.id) down")
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let finger = fingers.first(where: { $0.touch === touch }) else { continue }
            let (x, y) = gameFraction(touch)
            send(.fingerMove, finger.id, x, y)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        lift(touches, kind: .fingerUp)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        lift(touches, kind: .fingerCancel)
    }

    private func lift(_ touches: Set<UITouch>, kind: PadEventKind) {
        for touch in touches {
            if touch.type == .indirectPointer {
                pointerReleased(touch)
                continue
            }
            guard let index = fingers.firstIndex(where: { $0.touch === touch }) else { continue }
            let finger = fingers.remove(at: index)
            let (x, y) = gameFraction(touch)
            send(kind, finger.id, x, y)
        }
    }

    // MARK: - A mouse (where iOS gives the app a pointer)

    @objc private func hovered(_ recognizer: UIHoverGestureRecognizer) {
        guard recognizer.state == .began || recognizer.state == .changed else { return }
        // A mouse GameController knows moves the pointer by its raw motion (HardwareInput.swift); the
        // system pointer's position over the pad would fight it.
        if !GCMouse.mice().isEmpty { return }
        hover(at: recognizer.location(in: self))
    }

    private func hover(at point: CGPoint) {
        let game = MainActor.assumeIsolated { ExternalDisplay.shared.gamePoints }
        let gw = max(Double(game.width), 1), gh = max(Double(game.height), 1)
        let p = PointerMapping.hoverPoint((Double(point.x), Double(point.y)),
                                          pad: (Double(bounds.width), Double(bounds.height)), picture: (gw, gh))
        send(.hover, 0, p.x / gw, p.y / gh)
    }

    private func pointerPressed(_ touch: UITouch, event: UIEvent?) {
        // With the mouse known to the GameController framework its buttons come from there
        // (HardwareInput.swift; SDL_uikitview.m ignores these touches then too); sending them here as
        // well would click twice.
        if !GCMouse.mice().isEmpty { return }
        hover(at: touch.location(in: self))
        // SDL's button numbers: 1 left, 3 right.
        let button: UInt64 = (event?.buttonMask.contains(.secondary) ?? false) ? 3 : 1
        pointerButtons[ObjectIdentifier(touch)] = button
        send(.buttonDown, button, 0, 0)
    }

    private func pointerReleased(_ touch: UITouch) {
        guard let button = pointerButtons.removeValue(forKey: ObjectIdentifier(touch)) else { return }
        send(.buttonUp, button, 0, 0)
    }
}
#endif
