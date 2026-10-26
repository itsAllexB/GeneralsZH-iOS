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

// GeneralsX @feature iOS launcher 25/10/2026 Shows the launcher before the engine starts, and the
// C entry point gx_launcher_run() (include/gx_launcher.h).
//
// On iOS the app's executable IS the engine: SDL3 owns UIApplicationMain and the scene delegate
// (SDLUIKitSceneDelegate), and calls the engine's main() (SDL_main) on the main thread from a
// run-loop timer right after the scene connects. The engine calls gx_launcher_run() from there,
// before SDL video init. This file then:
//
//   1. spins the main run loop until a UIWindowScene is foreground-active (SDL calls main()
//      while the scene is still connecting),
//   2. puts a UIHostingController in its own UIWindow on that scene, above SDL's launch-screen
//      window,
//   3. spins the run loop -- default and UITracking modes, as SDL's own UIKit_PumpEvents() does --
//      until the player taps Play,
//   4. measures the safe area, removes the window, prepares the game data (LaunchPreparation:
//      opens the chosen folder, copies GameSupport into it, seeds Options.ini), sets the audio
//      session category, writes the environment (setenv) and returns the extra arguments.
//
// It must be called on the main thread, from a run-loop callout (timer, performSelector,
// CFRunLoopPerformBlock) -- which is how SDL calls main() -- and NOT from inside a block on the
// main dispatch queue: a nested run loop does not drain the main queue while one of its blocks is
// running, and SwiftUI/Swift-concurrency main-actor work would stall. A watchdog logs a warning to
// stderr if that is detected. Nor from inside a UIKit/SwiftUI action handler (a Button action):
// SwiftUI does not deliver a nested button action while one is running, so Play would never fire
// (seen in the test host). The engine's main() is in neither situation.
//
// Development switches (environment variables, read once per call):
//   GX_LAUNCHER_SKIP=1          no UI: apply the saved settings and return at once
//   GX_LAUNCHER_SECTION=<name>  open on home | interface | tools | help | logs
//   GX_LAUNCHER_MAX_FPS=<n>     pretend the screen's maximum frame rate is n (the simulator
//                               reports 60, so this shows the 120 fps choice there)

#if canImport(UIKit) && os(iOS)
import AVFoundation
import Foundation
import SwiftUI
import UIKit
import GXLauncherCore

// GeneralsX @feature iOS port 26/10/2026 Landscape only -- the game's layouts are landscape -- except
// on a foldable's inner display (the iPhone Duo's, about 1.42:1): it ignores an orientation lock and
// laid the app out portrait even when held landscape, so Info.plist allows every orientation and the
// lock is applied here, at run time, on every other device.
final class LauncherHostingController: UIHostingController<LauncherRootView> {
    var landscapeOnly = false

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        landscapeOnly ? .landscape : .all
    }
}

@MainActor
enum LauncherRunner {
    /// iPads and ordinary iPhones (about 2.16:1) get landscape only; an iPhone screen that is nearly
    /// square is a foldable's inner display and keeps every orientation.
    static func isLandscapeOnly(_ scene: UIWindowScene) -> Bool {
        if scene.traitCollection.userInterfaceIdiom != .phone { return true }
        let size = scene.screen.bounds.size
        let long = max(size.width, size.height), short = min(size.width, size.height)
        return short <= 0 || long / short >= 1.6
    }

    /// The game's window follows SDL's orientation hint, which SDL also reads from the environment.
    static func applyOrientationPolicy(landscapeOnly: Bool) {
        if landscapeOnly {
            setenv("SDL_IOS_ORIENTATIONS", "LandscapeLeft LandscapeRight", 1)
        } else {
            unsetenv("SDL_IOS_ORIENTATIONS")
        }
        log("orientations: \(landscapeOnly ? "landscape only" : "all (foldable inner display)")")
    }

    /// Runs the launcher and returns the extra arguments (after applying the environment).
    static func run() -> [String] {
        let paths = LauncherPaths.current
        _ = try? paths.ensureSettingsDir()
        let env = ProcessInfo.processInfo.environment

        if let skip = env["GX_LAUNCHER_SKIP"], !skip.isEmpty, skip != "0" {
            log("GX_LAUNCHER_SKIP set: applying saved settings without UI")
            let scene = waitForScene(timeout: 2)
            applyOrientationPolicy(landscapeOnly: scene.map(isLandscapeOnly) ?? true)
            return finish(paths: paths, insets: measureInsets(in: scene),
                          maxFPS: maximumFramesPerSecond(scene, env: env))
        }

        guard let scene = waitForScene(timeout: nil) else {
            return finish(paths: paths, insets: nil, maxFPS: FrameRate.defaultRate)
        }
        let maxFPS = maximumFramesPerSecond(scene, env: env)
        let landscapeOnly = isLandscapeOnly(scene)
        applyOrientationPolicy(landscapeOnly: landscapeOnly)
        let model = LauncherModel(paths: paths, maximumFramesPerSecond: maxFPS)
        if let name = env["GX_LAUNCHER_SECTION"]?.lowercased() {
            if name == "logs" {
                model.section = .tools
                model.showLogs = true
            } else if let section = LauncherModel.Section(rawValue: name) {
                model.section = section
            }
        }

        let window = UIWindow(windowScene: scene)
        // Above SDL's launch-screen window (UIWindowLevelNormal + 1), which SDL hides on its own
        // once main() is running.
        window.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.normal.rawValue + 2)
        let host = LauncherHostingController(rootView: LauncherRootView(model: model))
        host.landscapeOnly = landscapeOnly
        window.rootViewController = host
        window.makeKeyAndVisible()
        if landscapeOnly {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape)) { error in
                log("landscape request: \(error.localizedDescription)")
            }
        }
        log("launcher shown on scene \(scene.session.persistentIdentifier)")

        startMainQueueWatchdog()
        spin { model.finished }

        let insets = measureInsets(window: window)
        // Tear down: dismiss anything presented, drop the hosting controller, hide the window.
        host.presentedViewController?.dismiss(animated: false)
        window.isHidden = true
        window.rootViewController = nil
        spin(for: 0.05)  // let UIKit process the removal before the engine creates its window
        return finish(paths: paths, insets: insets, maxFPS: maxFPS)
    }

    /// Builds the plan from what is on disk now, applies the environment and returns the args.
    private static func finish(paths: LauncherPaths, insets: SafeInsets?, maxFPS: Int) -> [String] {
        let prefs = LauncherPreferences.load(from: paths.preferencesFile)
        let outcome = LaunchPreparation.prepare(paths: paths, preferences: prefs, safeInsets: insets,
                                                maximumFramesPerSecond: maxFPS)
        logOutcome(outcome)
        for name in LaunchPlanBuilder.apply(outcome.plan) {
            log("unsetenv \(name) (set by an earlier run, no longer applies)")
        }
        configureAudioSession(playInSilentMode: prefs.playSoundInSilentMode)
        for (name, value) in outcome.plan.environment {
            log("setenv \(name)=\(value)")
        }
        log("extra args: \(outcome.plan.arguments)")
        return outcome.plan.arguments
    }

    static func logOutcome(_ outcome: LaunchPreparation.Outcome) {
        switch outcome.folderState {
        case .none: break
        case .unavailable(let name, let reason):
            log("WARNING: chosen game folder \"\(name)\" is unavailable (\(reason)); not used")
        case .open(let folder, _):
            if !outcome.pendingDownloads.isEmpty {
                log("WARNING: \(outcome.pendingDownloads.count) archive(s) in \(folder.path) are not downloaded from iCloud yet; folder not used")
            }
        }
        switch outcome.source {
        case .external(let url)?: log("game data: chosen folder \(url.path)")
        case .bundled(let url)?: log("game data: bundled \(url.path)")
        case nil: log("WARNING: no game data available")
        }
        if let support = outcome.support {
            if !support.hadSupport {
                log("no GameSupport folder in the bundle; nothing copied")
            } else if support.complete {
                log("support files: \(support.written.count) written, \(support.unchanged) unchanged")
            } else {
                log("WARNING: could not copy \(support.failed.count) support file(s) into the game folder (read-only?); using the bundle's fonts and dxvk.conf, Window overrides will not load")
            }
        }
    }

    /// "Play sound in silent mode": .playback ignores the Ring/Silent switch, .ambient respects
    /// it; both mix with other audio. SDL reads SDL_AUDIO_CATEGORY (set by the plan) when it opens
    /// audio. Errors are logged, never fatal.
    nonisolated static func configureAudioSession(playInSilentMode: Bool) {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(playInSilentMode ? .playback : .ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            log("audio session: \(session.category.rawValue)")
        } catch {
            log("WARNING: audio session setup failed: \(error.localizedDescription)")
        }
    }

    /// The screen's maximum frame rate (120 on ProMotion), or the GX_LAUNCHER_MAX_FPS override.
    static func maximumFramesPerSecond(_ scene: UIWindowScene?, env: [String: String]) -> Int {
        if let forced = env["GX_LAUNCHER_MAX_FPS"].flatMap(Int.init), forced > 0 { return forced }
        return scene?.screen.maximumFramesPerSecond ?? FrameRate.defaultRate
    }

    // MARK: - Scenes

    /// The foreground-active window scene, waiting (spinning the run loop) until there is one.
    /// A scene that stays foreground-inactive for 3 s is accepted too (e.g. a call banner).
    /// `timeout` nil waits forever.
    static func waitForScene(timeout: TimeInterval?) -> UIWindowScene? {
        let start = Date()
        while true {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                .filter { $0.session.role == .windowApplication }
            if let active = scenes.first(where: { $0.activationState == .foregroundActive }) {
                return active
            }
            let waited = Date().timeIntervalSince(start)
            if waited > 3, let inactive = scenes.first(where: { $0.activationState == .foregroundInactive }) {
                return inactive
            }
            if let timeout, waited > timeout {
                return scenes.first
            }
            spinOnce(maxWait: 0.05)
        }
    }

    // MARK: - Safe area

    private static func measureInsets(in scene: UIWindowScene?) -> SafeInsets? {
        guard let window = scene?.windows.first(where: { $0.isKeyWindow }) ?? scene?.windows.first else { return nil }
        return measureInsets(window: window)
    }

    private static func measureInsets(window: UIWindow) -> SafeInsets? {
        let i = window.safeAreaInsets
        let size = window.bounds.size
        return SafeInsets.landscapeFractions(top: Double(i.top), left: Double(i.left),
                                             bottom: Double(i.bottom), right: Double(i.right),
                                             width: Double(size.width), height: Double(size.height))
    }

    // MARK: - Run loop

    private static let trackingMode = CFRunLoopMode(RunLoop.Mode.tracking.rawValue as CFString)

    /// One pass of the main run loop: wait up to `maxWait` for a source in the default mode,
    /// then drain whatever the UITracking mode has (scroll views), like SDL's UIKit_PumpEvents().
    static func spinOnce(maxWait: CFTimeInterval) {
        autoreleasepool {
            _ = CFRunLoopRunInMode(.defaultMode, maxWait, true)
            var result: CFRunLoopRunResult
            repeat {
                result = CFRunLoopRunInMode(trackingMode, 0, true)
            } while result == .handledSource
        }
    }

    static func spin(until done: () -> Bool) {
        while !done() {
            spinOnce(maxWait: 1.0 / 60.0)
        }
    }

    static func spin(for seconds: TimeInterval) {
        let end = Date().addingTimeInterval(seconds)
        spin { Date() >= end }
    }

    /// Warns when the main dispatch queue is not being drained (called from inside a main-queue
    /// block; see the header comment).
    private static func startMainQueueWatchdog() {
        let flag = WatchdogFlag()
        DispatchQueue.main.async { flag.fired = true }
        let deadline = Date().addingTimeInterval(1)
        while Date() < deadline && !flag.fired {
            spinOnce(maxWait: 0.02)
        }
        if !flag.fired {
            log("WARNING: the main dispatch queue is not draining -- gx_launcher_run() was called from inside a main-queue block; the UI may freeze. Call it from a run-loop callout instead.")
        }
    }

    nonisolated static func log(_ message: String) {
        fputs("[GX-Launcher] \(message)\n", stderr)
    }
}

private final class WatchdogFlag: @unchecked Sendable { var fired = false }

// MARK: - C entry point

/// The argument array handed to C. Owned here and freed on the next call (see gx_launcher.h).
private final class ExportedArguments: @unchecked Sendable {
    static let shared = ExportedArguments()
    private let lock = NSLock()
    private var array: UnsafeMutablePointer<UnsafePointer<CChar>?>?

    func export(_ args: [String]) -> UnsafePointer<UnsafePointer<CChar>?> {
        lock.lock(); defer { lock.unlock() }
        if let old = array {
            var index = 0
            while let string = old[index] {
                free(UnsafeMutablePointer(mutating: string))
                index += 1
            }
            old.deallocate()
        }
        let fresh = UnsafeMutablePointer<UnsafePointer<CChar>?>.allocate(capacity: args.count + 1)
        for (index, arg) in args.enumerated() {
            fresh[index] = UnsafePointer(strdup(arg))
        }
        fresh[args.count] = nil
        array = fresh
        return UnsafePointer(fresh)
    }
}

/// See include/gx_launcher.h.
@_cdecl("gx_launcher_run")
public func gx_launcher_run() -> UnsafePointer<UnsafePointer<CChar>?> {
    guard Thread.isMainThread else {
        // UIKit cannot be touched from here: apply the saved settings without UI or safe insets.
        fputs("[GX-Launcher] ERROR: gx_launcher_run() called off the main thread; skipping the UI\n", stderr)
        let paths = LauncherPaths.current
        _ = try? paths.ensureSettingsDir()
        let prefs = LauncherPreferences.load(from: paths.preferencesFile)
        let outcome = LaunchPreparation.prepare(paths: paths, preferences: prefs, safeInsets: nil)
        LaunchPlanBuilder.apply(outcome.plan)
        LauncherRunner.configureAudioSession(playInSilentMode: prefs.playSoundInSilentMode)
        return ExportedArguments.shared.export(outcome.plan.arguments)
    }
    let args = MainActor.assumeIsolated { LauncherRunner.run() }
    return ExportedArguments.shared.export(args)
}
#endif
