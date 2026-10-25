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

// GeneralsX @feature iOS launcher 25/10/2026 The small files in GX_SETTINGS_DIR that the engine
// reads at start. Names and formats are the Android launcher's, byte for byte, so the engine
// readers (GXControlScheme.h, GXMouseMode.h, GXLogging.h, GXTrace.h, SDL3GameEngine.cpp) only
// need their directory changed for iOS:
//
//   control_scheme      "attack_move=1\narmy_buttons=0\ncamera_high=1\n"; absent = Classic
//   mouse_mode          present = pointer mode; content = cursor size percent ("100")
//   logging_off         present = "Collect logs" switched OFF (empty file)
//   gx_trace.txt        present = verbose trace (empty file)
//   gx_perf.txt         present = performance summary
//   gx_audio_trace.txt  present = audio log
//   gx_touch_debug.txt  present = touch input overlay

import Foundation

// MARK: - Control scheme

/// The control scheme (SetupActivity.buildControlSchemeSection, GXControlScheme.h).
public struct ControlScheme: Equatable, Sendable {
    public static let fileName = "control_scheme"
    /// File order and key names, as GXControlScheme.h's kNames.
    public static let keys = ["attack_move", "army_buttons", "camera_high"]

    public enum Preset: Int, CaseIterable, Sendable {
        case classic, tactical, custom
    }

    /// A move order for combat units is an attack-move.
    public var attackMove: Bool
    /// The army column opens with its Army/Planes/Helicopters/Ground buttons.
    public var armyButtons: Bool
    /// The camera may zoom out up to four times higher.
    public var cameraHigh: Bool

    public init(attackMove: Bool = false, armyButtons: Bool = false, cameraHigh: Bool = false) {
        self.attackMove = attackMove
        self.armyButtons = armyButtons
        self.cameraHigh = cameraHigh
    }

    public static let classic = ControlScheme()
    public static let tactical = ControlScheme(attackMove: true, armyButtons: true, cameraHigh: true)

    var values: [Bool] { [attackMove, armyButtons, cameraHigh] }

    /// Android's controlSchemeIndex(): none on = Classic, all on = Tactical, else Custom.
    public var preset: Preset {
        if values.allSatisfy({ !$0 }) { return .classic }
        if values.allSatisfy({ $0 }) { return .tactical }
        return .custom
    }

    /// Picking Classic or Tactical sets every switch; Custom leaves them as they are.
    public mutating func apply(_ preset: Preset) {
        switch preset {
        case .classic: self = .classic
        case .tactical: self = .tactical
        case .custom: break
        }
    }

    /// Android's readControlScheme(): key=value lines, "1" is on, anything else off.
    public static func parse(_ text: String) -> ControlScheme {
        var scheme = ControlScheme()
        for line in text.split(whereSeparator: { $0.isNewline }) {
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            let on = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces) == "1"
            switch key {
            case "attack_move": scheme.attackMove = on
            case "army_buttons": scheme.armyButtons = on
            case "camera_high": scheme.cameraHigh = on
            default: continue
            }
        }
        return scheme
    }

    /// The exact text Android's writeControlScheme() writes.
    public var fileText: String {
        zip(Self.keys, values).map { "\($0)=\($1 ? "1" : "0")\n" }.joined()
    }

    public static func read(from file: URL) -> ControlScheme {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return .classic }
        return parse(text)
    }

    /// Classic deletes the file (no file is the retail game); anything else writes all three keys.
    public func write(to file: URL) throws {
        if preset == .classic {
            try removeIfPresent(file)
            return
        }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(fileText.utf8).write(to: file, options: .atomic)
    }
}

// MARK: - Mouse and touchpad

/// "Mouse and touchpad" (SetupActivity.buildMouseModeRows, GXMouseMode.h).
public struct MouseMode: Equatable, Sendable {
    public static let fileName = "mouse_mode"
    public static let cursorRange: ClosedRange<Int> = 50...200
    public static let cursorStep = 10
    public static let defaultCursorPercent = 100

    public var enabled: Bool
    public var cursorPercent: Int

    public init(enabled: Bool = false, cursorPercent: Int = MouseMode.defaultCursorPercent) {
        self.enabled = enabled
        self.cursorPercent = Self.clampCursor(cursorPercent)
    }

    /// Android's readMouseCursorPercent(): rounded to 10, clamped to 50...200, 100 when unreadable.
    public static func clampCursor(_ percent: Int) -> Int {
        let stepped = Int((Double(percent) / Double(cursorStep)).rounded()) * cursorStep
        return min(max(stepped, cursorRange.lowerBound), cursorRange.upperBound)
    }

    public static func read(from file: URL) -> MouseMode {
        guard FileManager.default.fileExists(atPath: file.path) else { return MouseMode() }
        let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        let firstLine = text.split(whereSeparator: { $0.isNewline }).first.map(String.init) ?? ""
        let value = Int(firstLine.trimmingCharacters(in: .whitespaces)) ?? defaultCursorPercent
        return MouseMode(enabled: true, cursorPercent: value)
    }

    /// Off deletes the marker; on writes the cursor percent with no newline (Integer.toString()).
    public func write(to file: URL) throws {
        guard enabled else {
            try removeIfPresent(file)
            return
        }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(String(cursorPercent).utf8).write(to: file, options: .atomic)
    }
}

// MARK: - Marker files

/// Empty marker files whose presence switches something on (or, for logging_off, off).
public enum MarkerFile: String, CaseIterable, Sendable, Identifiable {
    /// Present = "Collect logs" is OFF (GXLogging.h).
    case loggingOff = "logging_off"
    /// Verbose trace log (GXTrace.h; env GX_TRACE).
    case trace = "gx_trace.txt"
    /// Performance summary (GXTrace.h; env GX_PERF).
    case perf = "gx_perf.txt"
    /// Audio log (GXTrace.h; env GX_AUDIO_TRACE).
    case audioTrace = "gx_audio_trace.txt"
    /// Touch input overlay (SDL3GameEngine.cpp touchDebugEnabled(); env GX_TOUCH_DEBUG).
    case touchDebug = "gx_touch_debug.txt"

    public var id: String { rawValue }

    /// The diagnostics switches shown on the Tools screen, in Android's order.
    public static let diagnostics: [MarkerFile] = [.trace, .perf, .audioTrace, .touchDebug]

    /// The environment variable the engine already honours as an alternative to the marker.
    /// The launcher sets it to "1" when the marker is present, so the switch works even before
    /// the engine learns to look in GX_SETTINGS_DIR.
    public var environmentVariable: String? {
        switch self {
        case .loggingOff: return nil
        case .trace: return "GX_TRACE"
        case .perf: return "GX_PERF"
        case .audioTrace: return "GX_AUDIO_TRACE"
        case .touchDebug: return "GX_TOUCH_DEBUG"
        }
    }

    public func url(in paths: LauncherPaths) -> URL { paths.settingsFile(rawValue) }

    public func isPresent(in paths: LauncherPaths) -> Bool {
        FileManager.default.fileExists(atPath: url(in: paths).path)
    }

    /// Creates (empty) or deletes the marker.
    public func set(_ present: Bool, in paths: LauncherPaths) throws {
        let file = url(in: paths)
        if present {
            try paths.ensureSettingsDir()
            if !FileManager.default.fileExists(atPath: file.path) {
                try Data().write(to: file, options: .atomic)
            }
        } else {
            try removeIfPresent(file)
        }
    }
}

func removeIfPresent(_ file: URL) throws {
    do {
        try FileManager.default.removeItem(at: file)
    } catch CocoaError.fileNoSuchFile {
        // Already gone.
    } catch let error as NSError where error.domain == NSPOSIXErrorDomain && error.code == Int(ENOENT) {
        // Already gone.
    }
}
