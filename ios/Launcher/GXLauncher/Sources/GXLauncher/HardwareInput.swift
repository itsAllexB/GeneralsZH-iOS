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

// GeneralsX @feature iOS port 11/11/2026 A hardware mouse and keyboard (Bluetooth, or through a USB-C
// hub), on the phone and with the picture on an external display. C interface: gx_hardware_input.h.
//
// Mouse. SDL's UIKit backend moves its pointer only from UIKit's pointer events (hover over the game's
// view) and takes GameController's raw motion only in relative mode, which needs the game's window
// to have keyboard focus: on an external display it never has, and an iPhone never locks the
// pointer to an app (UIPointerLockState stays unlocked; Henge, the owner's emulator, logs the same).
// So every connected GCMouse is driven from here: raw motion, the three buttons and the wheel go to
// the engine through a C callback, which moves the game's own pointer (drawn by the game) by them.
// SDL's GameController handlers are replaced -- SDL installs them on its own handler queue, so a
// mouse whose queue is no longer the main one has been taken back by SDL and is taken over again
// (`update`, each frame). The app still asks for the pointer lock (the pad's controller here; SDL's
// through its relative mode, SDL3GameEngine.cpp), which iPadOS grants to a full-screen app and an
// iPhone does not: then the system pointer stays, hidden over the game's view.
//
// Keyboard. Keys need nothing new: SDL reads them from GameController (GCKeyboard), with or without
// focus. Text is the gap: SDL types into a game text field only through its hidden UITextField,
// which the engine opens on a tap, and which cannot take input on a display that takes none. With a
// hardware keyboard connected the engine asks for text here instead (gx_hardware_text_input): a
// responder that shows no on-screen keyboard becomes first responder in the window that has the
// keyboard -- the game's on the phone, the pad's while the picture is away -- and hands the
// characters of each key press (UIKey.characters, the layout's) to the engine as text.
//
// Several mice and keyboards at once, and devices that come and go with a hub, are followed through
// GameController's connect and disconnect notifications; GCKeyboard.coalesced merges keyboards.

#if canImport(UIKit) && os(iOS)
import Foundation
import GameController
import UIKit
import GXLauncherCore

/// What the engine receives (include/gx_hardware_input.h, GXHardwareMouseKind).
enum HardwareMouseKind: Int32 {
    case move = 0       // x, y: the pointer's motion in the game window's points
    case buttonDown = 1 // id: SDL's button number
    case buttonUp = 2
    case wheel = 3      // x: horizontal, y: vertical notches (positive y is away from the user)
}

typealias HardwareTextCallback = @convention(c) (UnsafePointer<CChar>?) -> Void

@MainActor
final class HardwareInput {
    static let shared = HardwareInput()

    /// Read by the engine from any thread.
    nonisolated(unsafe) static var mouseConnected = false

    private var mouseCallback: PadCallback?
    private var textCallback: HardwareTextCallback?
    private var mice: [GCMouse] = []
    private var buttons = MouseButtons()
    private var scroll = ScrollFilter()
    private var observers: [NSObjectProtocol] = []
    private var textWanted = false
    private let catcher = HardwareKeyCatcher()
    private var movesLogged = 0

    private static func log(_ message: String) { LauncherRunner.log("hardware input: \(message)") }

    func start(mouse: PadCallback?, text: HardwareTextCallback?) {
        mouseCallback = mouse
        textCallback = text
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .GCMouseDidConnect, object: nil, queue: .main) { note in
            guard let mouse = note.object as? GCMouse else { return }
            // After SDL's own observer, which sets its handlers synchronously.
            DispatchQueue.main.async { MainActor.assumeIsolated { HardwareInput.shared.attach(mouse) } }
        })
        observers.append(center.addObserver(forName: .GCMouseDidDisconnect, object: nil, queue: .main) { note in
            guard let mouse = note.object as? GCMouse else { return }
            MainActor.assumeIsolated { HardwareInput.shared.detach(mouse) }
        })
        observers.append(center.addObserver(forName: .GCKeyboardDidConnect, object: nil, queue: .main) { _ in
            Self.log("keyboard connected")
        })
        observers.append(center.addObserver(forName: .GCKeyboardDidDisconnect, object: nil, queue: .main) { _ in
            Self.log("keyboard disconnected\(GCKeyboard.coalesced == nil ? ", none left" : "")")
        })
        observers.append(center.addObserver(forName: UIPointerLockState.didChangeNotification, object: nil, queue: .main) { note in
            let scene = note.userInfo?[UIPointerLockState.sceneUserInfoKey] as? UIScene
            Self.log("pointer lock \(scene?.pointerLockState?.isLocked == true ? "granted" : "not granted") (scene role \(scene?.session.role.rawValue ?? "?"))")
        })
        GCMouse.mice().forEach(attach)
        Self.log("started: \(GCMouse.mice().count) mouse/mice, keyboard \(GCKeyboard.coalesced != nil ? "connected" : "none")")
    }

    var keyboardConnected: Bool { GCKeyboard.coalesced != nil }

    // MARK: - Mice

    private func attach(_ mouse: GCMouse) {
        guard let input = mouse.mouseInput else { return }
        if !mice.contains(where: { $0 === mouse }) {
            mice.append(mouse)
            Self.log("mouse connected: \(mouse.vendorName ?? "?"), right button \(input.rightButton != nil), "
                     + "middle \(input.middleButton != nil), \(mice.count) in all")
        }
        let id = ObjectIdentifier(mouse).hashValue
        mouse.handlerQueue = .main
        input.mouseMovedHandler = { _, dx, dy in
            MainActor.assumeIsolated { HardwareInput.shared.moved(Double(dx), Double(dy)) }
        }
        input.leftButton.pressedChangedHandler = { _, _, pressed in
            MainActor.assumeIsolated { HardwareInput.shared.button(MouseButtons.left, mouse: id, pressed: pressed) }
        }
        input.rightButton?.pressedChangedHandler = { _, _, pressed in
            MainActor.assumeIsolated { HardwareInput.shared.button(MouseButtons.right, mouse: id, pressed: pressed) }
        }
        input.middleButton?.pressedChangedHandler = { _, _, pressed in
            MainActor.assumeIsolated { HardwareInput.shared.button(MouseButtons.middle, mouse: id, pressed: pressed) }
        }
        input.auxiliaryButtons?.forEach { $0.pressedChangedHandler = nil }
        input.scroll.valueChangedHandler = { _, first, second in
            MainActor.assumeIsolated { HardwareInput.shared.scrolled(Double(first), Double(second)) }
        }
        Self.mouseConnected = true
        ExternalDisplay.shared.pointerLockPreferenceChanged()
    }

    private func detach(_ mouse: GCMouse) {
        mice.removeAll { $0 === mouse }
        for button in buttons.remove(mouse: ObjectIdentifier(mouse).hashValue) {
            mouseCallback?(HardwareMouseKind.buttonUp.rawValue, UInt64(button), 0, 0)
        }
        Self.mouseConnected = !mice.isEmpty
        Self.log("mouse disconnected, \(mice.count) left")
        ExternalDisplay.shared.pointerLockPreferenceChanged()
    }

    private func moved(_ dx: Double, _ dy: Double) {
        let height = Double(ExternalDisplay.shared.gamePoints.height)
        let p = MouseMotion.points(deltaX: dx, deltaY: dy, windowHeight: height)
        if movesLogged < 4 {
            movesLogged += 1
            Self.log("mouse motion \(dx),\(dy) -> \(String(format: "%.1f,%.1f", p.x, p.y)) points")
        }
        mouseCallback?(HardwareMouseKind.move.rawValue, 0, Float(p.x), Float(p.y))
    }

    private func button(_ button: Int, mouse: Int, pressed: Bool) {
        guard let down = buttons.change(button: button, mouse: mouse, pressed: pressed) else { return }
        mouseCallback?((down ? HardwareMouseKind.buttonDown : .buttonUp).rawValue, UInt64(button), 0, 0)
    }

    private func scrolled(_ first: Double, _ second: Double) {
        let n = scroll.notches(first: first, second: second)
        guard n.horizontal != 0 || n.vertical != 0 else { return }
        mouseCallback?(HardwareMouseKind.wheel.rawValue, 0, Float(n.horizontal), Float(n.vertical))
    }

    // MARK: - Each frame

    func update() {
        // SDL installs its own handlers (on its own queue) when it sees a mouse connect; take it back.
        for mouse in GCMouse.mice() where mouse.handlerQueue !== DispatchQueue.main || !mice.contains(where: { $0 === mouse }) {
            attach(mouse)
        }
        if Self.mouseConnected && GCMouse.mice().isEmpty {
            Self.mouseConnected = false
        }
        placeCatcher()
    }

    // MARK: - Text

    func setTextWanted(_ wanted: Bool) {
        guard wanted != textWanted else { return }
        textWanted = wanted
        Self.log("text entry \(wanted ? "from the hardware keyboard" : "off")")
        placeCatcher()
    }

    /// The catcher is first responder in the window that has the keyboard while the game wants text.
    private func placeCatcher() {
        guard textWanted, keyboardConnected else {
            if catcher.isFirstResponder { catcher.resignFirstResponder() }
            return
        }
        let host: UIView? = ExternalDisplay.pictureAway
            ? ExternalDisplay.shared.padWindow?.rootViewController?.view
            : ExternalDisplay.shared.gameWindow?.rootViewController?.view
        guard let host else { return }
        if catcher.superview !== host {
            catcher.removeFromSuperview()
            host.addSubview(catcher)
        }
        if !catcher.isFirstResponder {
            let taken = catcher.becomeFirstResponder()
            Self.log("text responder in the \(ExternalDisplay.pictureAway ? "pad's" : "game's") window: \(taken ? "first responder" : "refused")")
        }
    }

    fileprivate func typed(_ press: UIPress) {
        guard textWanted, let key = press.key else { return }
        let flags = key.modifierFlags
        guard let text = TypedText.text(characters: key.characters, control: flags.contains(.control),
                                        command: flags.contains(.command)) else { return }
        text.withCString { textCallback?($0) }
    }
}

/// A responder for a hardware keyboard's text: no UIKeyInput, so iOS shows no on-screen keyboard for it.
final class HardwareKeyCatcher: UIView {
    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        isUserInteractionEnabled = false
        alpha = 0
    }

    required init?(coder: NSCoder) { fatalError("made in code") }

    override var canBecomeFirstResponder: Bool { true }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            MainActor.assumeIsolated { HardwareInput.shared.typed(press) }
        }
        super.pressesBegan(presses, with: event)
    }
}

// MARK: - C interface (include/gx_hardware_input.h)

@_cdecl("gx_hardware_input_start")
public func gx_hardware_input_start(_ mouse: (@convention(c) (Int32, UInt64, Float, Float) -> Void)?,
                                    _ text: (@convention(c) (UnsafePointer<CChar>?) -> Void)?) {
    guard Thread.isMainThread else { return }
    MainActor.assumeIsolated { HardwareInput.shared.start(mouse: mouse, text: text) }
}

@_cdecl("gx_hardware_input_update")
public func gx_hardware_input_update() {
    guard Thread.isMainThread else { return }
    MainActor.assumeIsolated { HardwareInput.shared.update() }
}

@_cdecl("gx_hardware_mouse_connected")
public func gx_hardware_mouse_connected() -> Bool {
    HardwareInput.mouseConnected
}

@_cdecl("gx_hardware_keyboard_connected")
public func gx_hardware_keyboard_connected() -> Bool {
    guard Thread.isMainThread else { return false }
    return MainActor.assumeIsolated { HardwareInput.shared.keyboardConnected }
}

@_cdecl("gx_hardware_text_input")
public func gx_hardware_text_input(_ wanted: Bool) {
    guard Thread.isMainThread else { return }
    MainActor.assumeIsolated { HardwareInput.shared.setTextWanted(wanted) }
}
#endif
