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
//   GX_GAME_DATA_DIR   the game data folder to chdir() into (bundled or imported), when one exists
//   GX_UI_SCALE        Options.ini GXUiScale, when set -- GXUiScale.cpp reads this variable
//                      directly (Android's SDL3Main.cpp copies it there from Options.ini; the iOS
//                      SDL3Main.cpp does not, so the launcher does)
//   GX_TRACE, GX_PERF, GX_AUDIO_TRACE, GX_TOUCH_DEBUG = "1"
//                      when the matching diagnostics marker is on -- GXTrace.h and
//                      SDL3GameEngine.cpp already honour these as alternatives to the marker

import Foundation

// MARK: - Launcher preferences

/// Settings that only the launcher itself needs (the engine sees their effect as arguments/env).
public struct LauncherPreferences: Codable, Equatable, Sendable {
    /// "Skip intro movies" -> -nologo. Android default: off.
    public var skipIntro: Bool = false
    /// Use ImportedGameData instead of the bundled GameData when both exist.
    public var preferImportedData: Bool = false

    public init(skipIntro: Bool = false, preferImportedData: Bool = false) {
        self.skipIntro = skipIntro
        self.preferImportedData = preferImportedData
    }

    public init(from decoder: Decoder) throws {
        // Tolerant of missing keys so older/newer files still load.
        let c = try decoder.container(keyedBy: CodingKeys.self)
        skipIntro = try c.decodeIfPresent(Bool.self, forKey: .skipIntro) ?? false
        preferImportedData = try c.decodeIfPresent(Bool.self, forKey: .preferImportedData) ?? false
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

    /// The game data folder to hand the engine: the imported copy when preferred (or when the
    /// bundle has none), else the bundled one; nil when neither exists.
    public static func gameDataDirectory(paths: LauncherPaths, preferences: LauncherPreferences) -> URL? {
        let fm = FileManager.default
        let imported = fm.fileExists(atPath: paths.importedGameData.path)
        let bundled = fm.fileExists(atPath: paths.bundledGameData.path)
        if imported && (preferences.preferImportedData || !bundled) { return paths.importedGameData }
        if bundled { return paths.bundledGameData }
        return nil
    }

    /// Everything the engine gets, from what is on disk now.
    public static func plan(paths: LauncherPaths, preferences: LauncherPreferences, safeInsets: SafeInsets?) -> LaunchPlan {
        var env: [(name: String, value: String)] = [(settingsDirVariable, paths.settingsDir.path)]
        if let data = gameDataDirectory(paths: paths, preferences: preferences) {
            env.append((gameDataDirVariable, data.path))
        }
        let options = OptionsIniStore(file: paths.optionsIni, defaults: nil).load()
        if let raw = options.value(for: InterfaceScale.key), let percent = parsePercent(raw), percent > 0 {
            env.append((uiScaleVariable, String(percent)))
        }
        for marker in MarkerFile.diagnostics where marker.isPresent(in: paths) {
            if let name = marker.environmentVariable {
                env.append((name, "1"))
            }
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
