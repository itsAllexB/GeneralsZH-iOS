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

// GeneralsX @feature iOS port 11/11/2026 The game on an external display (USB-C monitor, AirPlay).
//
// Without this an external display mirrors the phone: the phone's picture with bars. With it:
//
//   - iOS gives the app a scene on the display. Up to iOS 26 that comes from Info.plist's scene
//     manifest (role UIWindowSceneSessionRoleExternalDisplayNonInteractive, delegate class
//     GXExternalDisplaySceneDelegate); from iOS 27 only to a registered scene accessory, which the
//     pad's view controller registers.
//   - Once the game's window exists (gx_external_display_start), that UIWindow -- SDL's, with SDL's
//     view controller and the Metal view DXVK renders into -- moves to the display's scene, and back
//     to the phone's when the display goes. SDL, DXVK and the engine then simply see a window of
//     another size: the engine re-creates its backbuffer for it each frame as it does on rotation
//     (DX8Wrapper::Pillarbox_Process_Resize) and fits its picture in with bars until it can change
//     resolution (SDL3GameEngine.cpp, at the menus).
//   - The Metal view's scale is lowered so the drawable has at most about 1080p of pixels
//     (ExternalRenderSize); SDL reports the same pixel size (Patches/sdl3-ios-metal-view-pixel-
//     size.patch), so DXVK's swapchain, the engine's backbuffer and the game resolution agree.
//   - The phone shows a trackpad (ExternalDisplayPad.swift) whose touches reach the engine as SDL
//     finger events of their own touch device; the engine turns them into its pointer
//     (handleTouchpadEvent).
//   - Before the game's window exists (the launcher, the game starting) the display shows a title
//     card instead of a mirror of the launcher.
//
// iOS takes the display's scene away whenever the app leaves the foreground and gives it back on
// return. The picture comes back to the phone at once each time, but the game's resolution only
// once the app is active and the display has stayed away two seconds (ResolutionPlan), so an app
// switch does not change resolutions twice.
//
// Without an external display nothing here acts: the game's window stays where SDL made it, at the
// scale SDL gave it. The one trace is the pad's window, hidden, which holds the scene accessory
// registration iOS 27 asks for.

#if canImport(UIKit) && os(iOS)
import Foundation
import QuartzCore
import UIKit
import GXLauncherCore

/// What the pad sends to the engine (include/gx_external_display.h, GXPadEventKind).
enum PadEventKind: Int32 {
    case fingerDown = 0
    case fingerMove = 1
    case fingerUp = 2
    case fingerCancel = 3
    case hover = 4
    case buttonDown = 5
    case buttonUp = 6
}

typealias PadCallback = @convention(c) (Int32, UInt64, Float, Float) -> Void

/// The display's scene. UIKit makes one per connected display, from the Info.plist entry (iOS 17 to
/// 26) or the pad's scene accessory (iOS 27).
@objc(GXExternalDisplaySceneDelegate)
final class ExternalDisplaySceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        MainActor.assumeIsolated { ExternalDisplay.shared.connected(windowScene) }
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        MainActor.assumeIsolated { ExternalDisplay.shared.disconnected(scene) }
    }
}

@MainActor
final class ExternalDisplay {
    static let shared = ExternalDisplay()

    /// Read by the engine from its SDL event watcher; written on the main thread only.
    nonisolated(unsafe) static var pictureAway = false

    private var phoneScene: UIWindowScene?
    private var display: UIWindowScene?
    private var cardWindow: UIWindow?
    private(set) var gameWindow: UIWindow?
    private(set) var padWindow: UIWindow?
    private var pad: ExternalDisplayPadController?
    private var accessory: AnyObject?
    private var callback: PadCallback?
    private var plan = ResolutionPlan()
    private var observers: [NSObjectProtocol] = []
    private var lastLoggedDrawable: PixelSize?
    /// The display's resolution as last told to the plan (.some(nil): too small for the game).
    private var reportedResolution: PixelSize??

    private static func log(_ message: String) { LauncherRunner.log("external display: \(message)") }
    private static func now() -> Double { ProcessInfo.processInfo.systemUptime }

    private var maxHeight: Int { ExternalRenderSize.maxHeight(environment: ProcessInfo.processInfo.environment) }

    // MARK: - Set-up

    /// The phone's scene is known (the launcher has it): make the pad and, on iOS 27, register the
    /// scene accessory through it, so a display connected from now on gets a scene of the app's.
    func prepare(phone scene: UIWindowScene) {
        if phoneScene == nil {
            phoneScene = scene
            let center = NotificationCenter.default
            observers.append(center.addObserver(forName: UIScene.didActivateNotification, object: scene, queue: .main) { _ in
                MainActor.assumeIsolated { ExternalDisplay.shared.phoneActivity(true) }
            })
            observers.append(center.addObserver(forName: UIScene.willDeactivateNotification, object: scene, queue: .main) { _ in
                MainActor.assumeIsolated { ExternalDisplay.shared.phoneActivity(false) }
            })
        }
        guard padWindow == nil else { return }
        let controller = ExternalDisplayPadController()
        let window = UIWindow(windowScene: scene)
        window.rootViewController = controller
        // Below SDL's game window, which covers it while the game is on the phone: the pad is seen only
        // once the game's window has gone to the display. Visible all the same: iOS 27 offers the
        // display's scene only to an accessory registered by a view controller that is on screen
        // (a hidden window's was never offered one in the Simulator).
        window.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.normal.rawValue - 1)
        window.isHidden = false
        padWindow = window
        pad = controller
        if #available(iOS 27.0, *) {
            let configuration = UISceneConfiguration(name: "External Display", sessionRole: .windowExternalDisplayNonInteractive)
            configuration.delegateClass = ExternalDisplaySceneDelegate.self
            accessory = controller.registerSceneAccessory(.externalNonInteractive(sceneConfiguration: configuration))
            Self.log("scene accessory registered (iOS 27)")
        }
    }

    /// The engine's window exists (SDL3Main.cpp, right after SDL_CreateWindow).
    func start(gameWindow window: UIWindow, callback: PadCallback?) {
        gameWindow = window
        self.callback = callback
        if let scene = window.windowScene, phoneScene == nil || padWindow == nil {
            prepare(phone: scene)
        }
        pad?.gameController = window.rootViewController
        Self.log("game window ready\(display != nil ? ", a display is connected" : "")")
        attachGame()
    }

    // MARK: - The display's scene

    func connected(_ scene: UIWindowScene) {
        display = scene
        let screen = scene.screen
        let mode = screen.currentMode.map { "\(Int($0.size.width))x\(Int($0.size.height))" } ?? "unknown"
        Self.log("scene connected: \(Int(screen.nativeBounds.width))x\(Int(screen.nativeBounds.height)) pixels, "
                 + "\(Int(screen.bounds.width))x\(Int(screen.bounds.height)) points at scale \(screen.nativeScale), "
                 + "mode \(mode), up to \(screen.maximumFramesPerSecond) Hz")
        if gameWindow != nil {
            attachGame()
        } else {
            showCard()
        }
    }

    func disconnected(_ scene: UIScene) {
        guard scene === display else { return }
        Self.log("scene disconnected")
        display = nil
        cardWindow?.isHidden = true
        cardWindow = nil
        detachGame()
        plan.displayDisconnected(now: Self.now())
    }

    private func phoneActivity(_ active: Bool) {
        plan.appActivity(active: active, now: Self.now())
    }

    /// Before the game's window exists, the display shows the game's name rather than the launcher.
    private func showCard() {
        guard let display, cardWindow == nil else { return }
        let window = UIWindow(windowScene: display)
        window.rootViewController = ExternalDisplayCardController()
        window.isHidden = false
        cardWindow = window
        Self.log("title card shown until the game starts")
    }

    // MARK: - Moving the game

    private func attachGame() {
        guard let display, let gameWindow, !Self.pictureAway else { return }
        // Set before the move: the game window resigns key status on the way, and the engine must
        // not take that for the app becoming inactive (SDL3GameEngine.cpp).
        Self.pictureAway = true
        gameWindow.windowScene = display
        gameWindow.frame = display.coordinateSpace.bounds
        gameWindow.layoutIfNeeded()
        if !gameWindow.isHidden {
            cardWindow?.isHidden = true
            cardWindow = nil
        }
        padWindow?.makeKey()
        applyScale()
        reportedResolution = nil
        reportResolution()
        let points = display.coordinateSpace.bounds.size
        Self.log("the game's picture moves to the display (\(Int(points.width))x\(Int(points.height)) points), "
                 + "game resolution wanted \(plan.wanted?.description ?? "unchanged")")
    }

    private func detachGame() {
        guard Self.pictureAway, let gameWindow else { return }
        let phone = phoneScene ?? gameWindow.windowScene
        if let phone {
            gameWindow.windowScene = phone
            gameWindow.frame = phone.coordinateSpace.bounds
        }
        restoreScale()
        if !gameWindow.isHidden {
            gameWindow.makeKeyAndVisible()
        }
        gameWindow.layoutIfNeeded()
        Self.pictureAway = false
        Self.log("the game's picture is back on the phone")
    }

    /// The scale and the drawable for the display the picture is on (nil without one).
    private func displayDrawable() -> (scale: Double, drawable: PixelSize)? {
        guard let display else { return nil }
        let points = display.coordinateSpace.bounds.size
        let size = (Double(points.width), Double(points.height))
        let scale = ExternalRenderSize.drawableScale(points: size, screenScale: Double(display.screen.nativeScale), maxHeight: maxHeight)
        return (scale, ExternalRenderSize.pixels(points: size, scale: scale))
    }

    /// Gives the game's view on the display the capped scale (SDL made it with the screen's own).
    private func applyScale() {
        guard Self.pictureAway, let target = displayDrawable(), let display,
              let view = gameWindow?.rootViewController?.view else { return }
        let scale = CGFloat(target.scale)
        if view.layer.contentsScale != scale {
            view.contentScaleFactor = scale
            view.layer.contentsScale = scale
            view.setNeedsLayout()
            view.layoutIfNeeded()
        }
        if target.drawable != lastLoggedDrawable {
            lastLoggedDrawable = target.drawable
            Self.log("drawable \(target.drawable) (scale \(String(format: "%.4f", target.scale)) of the screen's \(display.screen.nativeScale), "
                     + "cap \(maxHeight) lines), view \(type(of: view))")
        }
    }

    /// Tells the plan the display's resolution when it is new (connect, a mode change, the cap).
    private func reportResolution() {
        guard Self.pictureAway, let target = displayDrawable() else { return }
        let resolution = ExternalRenderSize.gameResolution(drawable: target.drawable)
        if let reported = reportedResolution, reported == resolution { return }
        reportedResolution = resolution
        plan.displayConnected(resolution: resolution)
        if resolution == nil {
            Self.log("the display is too small for the game's interface (\(target.drawable)): the resolution stays, the picture is fitted with bars")
        }
    }

    /// Back on the phone: the phone's own scale, as SDL gives its Metal view (the screen's native
    /// scale; SDL3Main.cpp always asks for SDL_WINDOW_HIGH_PIXEL_DENSITY). Also when SDL made the
    /// Metal view while the window was on the display, at that screen's scale.
    private func restoreScale() {
        lastLoggedDrawable = nil
        guard let phoneScene, let view = gameWindow?.rootViewController?.view else { return }
        let scale = phoneScene.screen.nativeScale
        if view.layer.contentsScale != scale {
            view.contentScaleFactor = scale
            view.layer.contentsScale = scale
            view.setNeedsLayout()
            view.layoutIfNeeded()
        }
    }

    // MARK: - Engine interface

    /// Once per frame (and once at start): SDL replaces the game's root view with its Metal view
    /// when DXVK makes its surface, at the screen's own scale; that view gets the capped scale here
    /// before it presents. Also hides the title card once the game shows its window, and ends the
    /// display's resolution once the grace is over.
    func update() {
        if Self.pictureAway {
            applyScale()
            reportResolution()
            if let gameWindow, !gameWindow.isHidden, let card = cardWindow {
                card.isHidden = true
                cardWindow = nil
            }
        }
        if plan.tick(now: Self.now()) {
            Self.log("the display stayed away \(ResolutionPlan.graceSeconds) s with the app active: the phone's resolution \(plan.wanted?.description ?? "?") again")
        }
    }

    /// A mouse came or went (HardwareInput.swift): the pad asks for the pointer lock while one is connected.
    func pointerLockPreferenceChanged() {
        pad?.setNeedsUpdateOfPrefersPointerLocked()
    }

    func setPhoneResolution(_ size: PixelSize) {
        plan.phone = size
    }

    var wantedResolution: PixelSize? { plan.wanted }

    /// The game's resolution for the display when the picture is there now (start-up), else nil.
    var startResolution: PixelSize? {
        guard Self.pictureAway, let target = displayDrawable() else { return nil }
        return ExternalRenderSize.gameResolution(drawable: target.drawable)
    }

    /// The game window's size in points, which the engine's finger coordinates are fractions of.
    var gamePoints: CGSize { gameWindow?.bounds.size ?? .zero }

    func send(_ kind: PadEventKind, id: UInt64, x: Double, y: Double) {
        callback?(kind.rawValue, id, Float(x), Float(y))
    }
}

// MARK: - The title card

/// What the display shows while the launcher is up or the game is starting.
final class ExternalDisplayCardController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        let title = UILabel()
        title.text = "Generals ZH"
        title.font = .systemFont(ofSize: 44, weight: .bold)
        title.textColor = .white
        let subtitle = UILabel()
        subtitle.text = L("The game appears here once it starts. The phone is its trackpad.")
        subtitle.font = .systemFont(ofSize: 20)
        subtitle.textColor = UIColor(white: 0.7, alpha: 1)
        subtitle.numberOfLines = 0
        subtitle.textAlignment = .center
        let stack = UIStackView(arrangedSubviews: [title, subtitle])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: 0.8),
        ])
    }
}

// MARK: - C interface (include/gx_external_display.h)

@_cdecl("gx_external_display_start")
public func gx_external_display_start(_ uiwindow: UnsafeMutableRawPointer?, _ callback: (@convention(c) (Int32, UInt64, Float, Float) -> Void)?) {
    guard Thread.isMainThread, let uiwindow else { return }
    let window = Unmanaged<UIWindow>.fromOpaque(uiwindow).takeUnretainedValue()
    MainActor.assumeIsolated { ExternalDisplay.shared.start(gameWindow: window, callback: callback) }
}

@_cdecl("gx_external_display_update")
public func gx_external_display_update() {
    guard Thread.isMainThread else { return }
    MainActor.assumeIsolated { ExternalDisplay.shared.update() }
}

@_cdecl("gx_external_display_picture_away")
public func gx_external_display_picture_away() -> Bool {
    ExternalDisplay.pictureAway
}

@_cdecl("gx_external_display_set_phone_resolution")
public func gx_external_display_set_phone_resolution(_ width: Int32, _ height: Int32) {
    guard Thread.isMainThread, width > 0, height > 0 else { return }
    MainActor.assumeIsolated { ExternalDisplay.shared.setPhoneResolution(PixelSize(width: Int(width), height: Int(height))) }
}

@_cdecl("gx_external_display_wanted_resolution")
public func gx_external_display_wanted_resolution(_ width: UnsafeMutablePointer<Int32>?, _ height: UnsafeMutablePointer<Int32>?) -> Bool {
    guard Thread.isMainThread else { return false }
    guard let wanted = MainActor.assumeIsolated({ ExternalDisplay.shared.wantedResolution }) else { return false }
    width?.pointee = Int32(wanted.width)
    height?.pointee = Int32(wanted.height)
    return true
}

@_cdecl("gx_external_display_start_resolution")
public func gx_external_display_start_resolution(_ width: UnsafeMutablePointer<Int32>?, _ height: UnsafeMutablePointer<Int32>?) -> Bool {
    guard Thread.isMainThread else { return false }
    guard let size = MainActor.assumeIsolated({ ExternalDisplay.shared.startResolution }) else { return false }
    width?.pointee = Int32(size.width)
    height?.pointee = Int32(size.height)
    return true
}
#endif
