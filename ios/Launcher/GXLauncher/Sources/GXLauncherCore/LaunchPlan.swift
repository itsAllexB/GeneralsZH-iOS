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

// GeneralsX @feature iOS launcher 25/10/2026 What the engine receives when the player taps Play:
// extra command-line arguments (appended to argv) and environment variables (setenv).
//
// Arguments (GeneralsZHActivity.getArguments() on Android):
//   -gxSafeInsets l,t,r,b   safe-area insets as fractions of the landscape window (GXSafeArea.h)
//   -nologo                 "Skip intro movies"
//
// Environment:
//   GX_SETTINGS_DIR    always; the folder holding control_scheme, mouse_mode, logging_off, markers
//   GX_GAME_DATA_DIR   the game data folder to chdir() into, by priority: the folder chosen in
//                      Files > the copy imported into Application Support > <App>/GameData (dev
//                      builds); unset when there is none
//   GX_UI_SCALE        Options.ini GXUiScale clamped to 70...200, when set and not 100 (100 is the
//                      engine's default) -- GXUiScale.cpp reads this variable
//                      directly (Android's SDL3Main.cpp copies it there from Options.ini; the iOS
//                      SDL3Main.cpp does not, so the launcher does)
//   GX_TRACE, GX_PERF, GX_AUDIO_TRACE, GX_TOUCH_DEBUG = "1"
//                      when the matching diagnostics marker is on -- GXTrace.h and
//                      SDL3GameEngine.cpp already honour these as alternatives to the marker
//   SDL_AUDIO_CATEGORY "playback" ("Play sound in silent mode", default) or "ambient"
//   GENERALSX_BUNDLED_FONTS_DIR, DXVK_CONFIG_FILE
//                      <App>/GameSupport/fonts and <App>/GameSupport/dxvk.conf, only when the
//                      support files could not be copied into the game folder (read-only folder)

import Foundation

// MARK: - Launcher preferences

/// Settings that only the launcher itself needs (the engine sees their effect as arguments/env).
public struct LauncherPreferences: Codable, Equatable, Sendable {
    /// "Skip intro movies" -> -nologo. Android default: off.
    public var skipIntro: Bool = false
    /// "Play sound in silent mode": AVAudioSession .playback (on, default) or .ambient (off).
    public var playSoundInSilentMode: Bool = true

    public init(skipIntro: Bool = false, playSoundInSilentMode: Bool = true) {
        self.skipIntro = skipIntro
        self.playSoundInSilentMode = playSoundInSilentMode
    }

    public init(from decoder: Decoder) throws {
        // Tolerant of missing and unknown keys (an older file's "preferImportedData" is ignored:
        // the data source now follows a fixed priority, see LaunchPlanBuilder.gameDataSource).
        let c = try decoder.container(keyedBy: CodingKeys.self)
        skipIntro = try c.decodeIfPresent(Bool.self, forKey: .skipIntro) ?? false
        playSoundInSilentMode = try c.decodeIfPresent(Bool.self, forKey: .playSoundInSilentMode) ?? true
    }

    public static func load(from file: URL) -> LauncherPreferences {
        guard let data = try? Data(contentsOf: file),
              let prefs = try? JSONDecoder().decode(LauncherPreferences.self, from: data) else {
            return LauncherPreferences()
        }
        return prefs
    }

    public func save(to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: file, options: .atomic)
    }
}

// MARK: - Safe insets

/// Safe-area insets for -gxSafeInsets, as fractions of the LANDSCAPE window ("left,top,right,
/// bottom"), the form GXSafeArea.h expects. The game is landscape-only but the launcher may be
/// portrait when Play is tapped, so portrait insets are rotated: the portrait top/bottom (sensor
/// housing, home indicator) become the landscape left and right sides. iOS reports symmetric
/// side insets in landscape, so both sides get the larger of the two; the bottom keeps the
/// portrait home-indicator inset, a slight over-estimate that never clips HUD text.
public struct SafeInsets: Equatable, Sendable {
    public var left: Double
    public var top: Double
    public var right: Double
    public var bottom: Double

    public init(left: Double, top: Double, right: Double, bottom: Double) {
        self.left = left; self.top = top; self.right = right; self.bottom = bottom
    }

    /// `insets` in points for a window of `width` x `height` points.
    public static func landscapeFractions(top: Double, left: Double, bottom: Double, right: Double,
                                          width: Double, height: Double) -> SafeInsets? {
        guard width > 0, height > 0 else { return nil }
        if width >= height {
            return SafeInsets(left: left / width, top: top / height, right: right / width, bottom: bottom / height)
        }
        // Portrait: landscape width = portrait height, landscape height = portrait width.
        let side = max(top, bottom)
        return SafeInsets(left: side / height, top: max(left, right) / width,
                          right: side / height, bottom: bottom / width)
    }

    public var isZero: Bool { left == 0 && top == 0 && right == 0 && bottom == 0 }

    /// "0.0670,0.0000,0.0670,0.0477" -- POSIX decimal point regardless of the user's locale.
    public var argument: String {
        String(format: "%.4f,%.4f,%.4f,%.4f", locale: Locale(identifier: "en_US_POSIX"), left, top, right, bottom)
    }
}

// MARK: - The plan

public struct LaunchPlan: Equatable, Sendable {
    public var arguments: [String]
    public var environment: [(name: String, value: String)]

    public static func == (a: LaunchPlan, b: LaunchPlan) -> Bool {
        a.arguments == b.arguments && a.environment.map { "\($0.name)=\($0.value)" } == b.environment.map { "\($0.name)=\($0.value)" }
    }

    public func value(of name: String) -> String? {
        environment.last(where: { $0.name == name })?.value
    }
}

public enum LaunchPlanBuilder {
    public static let settingsDirVariable = "GX_SETTINGS_DIR"
    public static let gameDataDirVariable = "GX_GAME_DATA_DIR"
    public static let uiScaleVariable = "GX_UI_SCALE"
    public static let audioCategoryVariable = "SDL_AUDIO_CATEGORY"
    public static let bundledFontsVariable = "GENERALSX_BUNDLED_FONTS_DIR"
    public static let dxvkConfigVariable = "DXVK_CONFIG_FILE"

    /// The extra argv entries, in Android's order (safe insets first, then -nologo).
    public static func arguments(preferences: LauncherPreferences, safeInsets: SafeInsets?) -> [String] {
        var args: [String] = []
        if let insets = safeInsets, !insets.isZero {
            args += ["-gxSafeInsets", insets.argument]
        }
        if preferences.skipIntro {
            args.append("-nologo")
        }
        return args
    }

    /// Where the game data comes from, by priority: the folder chosen in Files (`externalFolder`,
    /// already opened and checked by the caller) > the copy in Application Support > the bundle.
    public static func gameDataSource(paths: LauncherPaths, externalFolder: URL?) -> GameDataSource? {
        if let externalFolder { return .external(externalFolder) }
        let fm = FileManager.default
        if fm.fileExists(atPath: paths.importedGameData.path) { return .imported(paths.importedGameData) }
        if fm.fileExists(atPath: paths.bundledGameData.path) { return .bundled(paths.bundledGameData) }
        return nil
    }

    /// Everything the engine gets, from what is on disk now.
    /// `supportFallback`: the support files could not be put into the game folder, so point the
    /// engine at the bundle's copies instead.
    public static func plan(paths: LauncherPaths, preferences: LauncherPreferences, safeInsets: SafeInsets?,
                            externalFolder: URL? = nil, supportFallback: Bool = false) -> LaunchPlan {
        var env: [(name: String, value: String)] = [(settingsDirVariable, paths.settingsDir.path)]
        if let source = gameDataSource(paths: paths, externalFolder: externalFolder) {
            env.append((gameDataDirVariable, source.url.path))
        }
        let options = OptionsIniStore(file: paths.optionsIni, defaults: nil).load()
        if options.value(for: InterfaceScale.key) != nil {
            let percent = InterfaceScale.read(options)  // clamped to 70...200
            if percent != InterfaceScale.defaultPercent {
                env.append((uiScaleVariable, String(percent)))
            }
        }
        for marker in MarkerFile.diagnostics where marker.isPresent(in: paths) {
            if let name = marker.environmentVariable {
                env.append((name, "1"))
            }
        }
        env.append((audioCategoryVariable, preferences.playSoundInSilentMode ? "playback" : "ambient"))
        if supportFallback {
            env.append((bundledFontsVariable, paths.bundledSupport.appendingPathComponent("fonts").path))
            env.append((dxvkConfigVariable, paths.bundledSupport.appendingPathComponent("dxvk.conf").path))
        }
        return LaunchPlan(arguments: arguments(preferences: preferences, safeInsets: safeInsets), environment: env)
    }

    /// setenv() for every variable of the plan (overwriting).
    public static func apply(_ plan: LaunchPlan) {
        for (name, value) in plan.environment {
            setenv(name, value, 1)
        }
    }
}

// MARK: - Data source

public enum GameDataSource: Equatable, Sendable {
    /// The folder the player chose in Files (security-scoped, bookmarked).
    case external(URL)
    /// The copy in Application Support/GeneralsX/ImportedGameData.
    case imported(URL)
    /// <App>.app/GameData (dev builds).
    case bundled(URL)

    public var url: URL {
        switch self {
        case .external(let url), .imported(let url), .bundled(let url): return url
        }
    }

    /// Whether the support files belong in it (the bundle is read-only and has them already).
    public var takesSupportFiles: Bool {
        if case .bundled = self { return false }
        return true
    }
}

// MARK: - Preparing a launch

/// What gx_launcher_run() does before returning, minus UIKit/AVFoundation: open the chosen game
/// folder, pick the data source, copy the support files into it, seed Options.ini, build the plan.
public enum LaunchPreparation {
    public struct Outcome: Sendable {
        public var plan: LaunchPlan
        public var source: GameDataSource?
        public var support: SupportSyncResult?
        public var folderState: GameFolderAccess.State
        /// Archives iCloud Drive still has to download (the chosen folder is then not used).
        public var pendingDownloads: [URL]
    }

    /// The chosen game folder when it can be used right now: opened, a game folder, and fully
    /// downloaded. Also returns the access state and any pending iCloud downloads.
    public static func usableExternalFolder(paths: LauncherPaths)
        -> (folder: URL?, state: GameFolderAccess.State, pending: [URL]) {
        let state = GameFolderAccess.open(paths: paths)
        guard case .open(let folder, _) = state else { return (nil, state, []) }
        let pending = UbiquitousFiles.pendingArchives(in: folder)
        guard pending.isEmpty, GameDataValidator.isGameFolder(folder) else { return (nil, state, pending) }
        return (folder, state, [])
    }

    public static func prepare(paths: LauncherPaths, preferences: LauncherPreferences,
                               safeInsets: SafeInsets?) -> Outcome {
        _ = try? paths.ensureSettingsDir()
        let external = usableExternalFolder(paths: paths)
        let source = LaunchPlanBuilder.gameDataSource(paths: paths, externalFolder: external.folder)
        var support: SupportSyncResult?
        if let source, source.takesSupportFiles {
            support = SupportFileSync.sync(from: paths.bundledSupport, to: source.url)
        }
        seedOptionsIfMissing(paths: paths, dataFolder: source?.url)
        let fallback = support.map { $0.hadSupport && !$0.complete } ?? false
        let plan = LaunchPlanBuilder.plan(paths: paths, preferences: preferences, safeInsets: safeInsets,
                                          externalFolder: external.folder, supportFallback: fallback)
        return Outcome(plan: plan, source: source, support: support, folderState: external.state,
                       pendingDownloads: external.pending)
    }

    /// Options.ini from GameSupport/DefaultOptions.ini (else the data folder's) when it is missing.
    public static func seedOptionsIfMissing(paths: LauncherPaths, dataFolder: URL?) {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: paths.optionsIni.path),
              let defaults = paths.defaultOptionsSource(dataFolder: dataFolder) else { return }
        try? fm.createDirectory(at: paths.userDataDir, withIntermediateDirectories: true)
        try? fm.copyItem(at: defaults, to: paths.optionsIni)
    }
}
