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

// GeneralsX @feature iOS launcher 25/10/2026 control_scheme, mouse_mode and marker files: the
// exact bytes Android writes, and the engine's reading rules.

import XCTest
@testable import GXLauncherCore

final class SettingsFilesTests: XCTestCase {
    func testPresets() {
        XCTAssertEqual(ControlScheme.classic.preset, .classic)
        XCTAssertEqual(ControlScheme.tactical.preset, .tactical)
        XCTAssertEqual(ControlScheme.tactical,
                       ControlScheme(attackMove: true, armyButtons: true, cameraHigh: false, minimapCamera: true),
                       "Tactical: attack-move, army buttons and minimap camera; no longer the higher camera")
        XCTAssertEqual(ControlScheme(attackMove: true).preset, .custom)
        XCTAssertEqual(ControlScheme(attackMove: true, armyButtons: true).preset, .custom, "minimap camera off: Custom")
        // The higher camera is not part of the presets.
        XCTAssertEqual(ControlScheme(cameraHigh: true).preset, .classic)
        XCTAssertEqual(ControlScheme(attackMove: true, armyButtons: true, cameraHigh: true, minimapCamera: true).preset, .tactical)

        var scheme = ControlScheme(attackMove: true, cameraHigh: true)
        scheme.apply(.custom)
        XCTAssertEqual(scheme, ControlScheme(attackMove: true, cameraHigh: true), "Custom keeps the switches")
        scheme.apply(.tactical)
        XCTAssertEqual(scheme, ControlScheme(attackMove: true, armyButtons: true, cameraHigh: true, minimapCamera: true),
                       "a preset never resets camera_high")
        scheme.apply(.classic)
        XCTAssertEqual(scheme, ControlScheme(cameraHigh: true), "a preset never resets camera_high")
        scheme.cameraHigh = false
        scheme.apply(.tactical)
        XCTAssertFalse(scheme.cameraHigh, "nor sets it")
    }

    func testControlSchemeFileTextMatchesAndroid() {
        // Android's three keys in its order, then minimap_camera (GXControlScheme.h kNames).
        XCTAssertEqual(ControlScheme(attackMove: true, armyButtons: true, cameraHigh: true, minimapCamera: true).fileText,
                       "attack_move=1\narmy_buttons=1\ncamera_high=1\nminimap_camera=1\n")
        XCTAssertEqual(ControlScheme(armyButtons: true).fileText,
                       "attack_move=0\narmy_buttons=1\ncamera_high=0\nminimap_camera=0\n")
    }

    func testHigherCameraAloneKeepsTheFile() throws {
        let home = try TempHome()
        let file = home.paths.settingsFile(ControlScheme.fileName)
        // Classic preset + Allow higher camera: the file must stay, with camera_high=1.
        try ControlScheme(cameraHigh: true).write(to: file)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8),
                       "attack_move=0\narmy_buttons=0\ncamera_high=1\nminimap_camera=0\n")
        // An existing (Android-era, three-key) file with camera_high=1 reads back with the toggle on.
        try Data("attack_move=1\narmy_buttons=1\ncamera_high=1\n".utf8).write(to: file)
        let read = ControlScheme.read(from: file)
        XCTAssertTrue(read.cameraHigh)
        XCTAssertFalse(read.minimapCamera, "missing key = off, as in the engine")
        XCTAssertEqual(read.preset, .custom)
    }

    func testMinimapCameraIsWrittenAndKept() throws {
        let home = try TempHome()
        let file = home.paths.settingsFile(ControlScheme.fileName)
        var scheme = ControlScheme(minimapCamera: true)
        try scheme.write(to: file)
        XCTAssertEqual(ControlScheme.read(from: file), scheme)
        XCTAssertTrue(try String(contentsOf: file, encoding: .utf8).contains("minimap_camera=1\n"))
        // Toggling something else and rewriting keeps it.
        scheme = ControlScheme.read(from: file)
        scheme.cameraHigh = true
        try scheme.write(to: file)
        XCTAssertTrue(ControlScheme.read(from: file).minimapCamera)
        // Classic turns it off; Tactical on.
        scheme.apply(.classic)
        XCTAssertFalse(scheme.minimapCamera)
        scheme.apply(.tactical)
        XCTAssertTrue(scheme.minimapCamera)
    }

    func testUnknownKeysSurviveRewrite() throws {
        let home = try TempHome()
        let file = home.paths.settingsFile(ControlScheme.fileName)
        try home.paths.ensureSettingsDir()
        try Data("attack_move=1\nfuture_option=1\ncamera_high=0\n".utf8).write(to: file)
        var scheme = ControlScheme.read(from: file)
        XCTAssertEqual(scheme.otherLines, ["future_option=1"])
        scheme.apply(.classic)
        try scheme.write(to: file)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8),
                       "attack_move=0\narmy_buttons=0\ncamera_high=0\nminimap_camera=0\nfuture_option=1\n",
                       "an unknown key keeps the file and is kept")
    }

    func testControlSchemeWriteAndRead() throws {
        let home = try TempHome()
        let file = home.paths.settingsFile(ControlScheme.fileName)
        let custom = ControlScheme(attackMove: true, cameraHigh: true)
        try custom.write(to: file)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "attack_move=1\narmy_buttons=0\ncamera_high=1\nminimap_camera=0\n")
        XCTAssertEqual(ControlScheme.read(from: file), custom)

        try ControlScheme.classic.write(to: file)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path), "everything off = no file (retail)")
        XCTAssertEqual(ControlScheme.read(from: file), .classic)
        try ControlScheme.classic.write(to: file)  // deleting twice is fine
    }

    func testControlSchemeParseIsTolerant() {
        let parsed = ControlScheme.parse("# comment\n camera_high = 1 \nattack_move=yes\nunknown=1\narmy_buttons=1\r\nminimap_camera=1\n")
        var expected = ControlScheme(attackMove: false, armyButtons: true, cameraHigh: true, minimapCamera: true)
        expected.otherLines = ["unknown=1"]
        XCTAssertEqual(parsed, expected)
    }

    func testMouseMode() throws {
        let home = try TempHome()
        let file = home.paths.settingsFile(MouseMode.fileName)
        XCTAssertEqual(MouseMode.read(from: file), MouseMode(enabled: false, cursorPercent: 100))

        try MouseMode(enabled: true, cursorPercent: 150).write(to: file)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "150", "Integer.toString(), no newline")
        XCTAssertEqual(MouseMode.read(from: file), MouseMode(enabled: true, cursorPercent: 150))

        try Data().write(to: file)
        XCTAssertEqual(MouseMode.read(from: file), MouseMode(enabled: true, cursorPercent: 100), "empty marker = 100%")
        try Data("47\n".utf8).write(to: file)
        XCTAssertEqual(MouseMode.read(from: file).cursorPercent, 50, "rounded to 10 and clamped")
        try Data("999".utf8).write(to: file)
        XCTAssertEqual(MouseMode.read(from: file).cursorPercent, 200)

        try MouseMode(enabled: false, cursorPercent: 150).write(to: file)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testMarkers() throws {
        let home = try TempHome()
        XCTAssertEqual(MarkerFile.diagnostics.map(\.rawValue),
                       ["gx_trace.txt", "gx_perf.txt", "gx_audio_trace.txt", "gx_touch_debug.txt"])
        XCTAssertEqual(MarkerFile.loggingOff.rawValue, "logging_off")
        for marker in MarkerFile.allCases {
            XCTAssertFalse(marker.isPresent(in: home.paths))
            try marker.set(true, in: home.paths)
            XCTAssertTrue(marker.isPresent(in: home.paths))
            let size = try FileManager.default.attributesOfItem(atPath: marker.url(in: home.paths).path)[.size] as? Int
            XCTAssertEqual(size, 0, "markers are empty files")
            XCTAssertEqual(marker.url(in: home.paths).deletingLastPathComponent().standardizedFileURL,
                           home.paths.settingsDir.standardizedFileURL)
            try marker.set(false, in: home.paths)
            XCTAssertFalse(marker.isPresent(in: home.paths))
        }
    }

    func testPreferencesRoundTrip() throws {
        let home = try TempHome()
        XCTAssertEqual(LauncherPreferences.load(from: home.paths.preferencesFile), LauncherPreferences())
        let prefs = LauncherPreferences(skipIntro: true, playSoundInSilentMode: false, frameRate: 120)
        try prefs.save(to: home.paths.preferencesFile)
        XCTAssertEqual(LauncherPreferences.load(from: home.paths.preferencesFile), prefs)
        // An older file: sound defaults to ON, the retired "preferImportedData" is ignored.
        try Data("{\"skipIntro\": true, \"preferImportedData\": true}".utf8).write(to: home.paths.preferencesFile)
        XCTAssertEqual(LauncherPreferences.load(from: home.paths.preferencesFile),
                       LauncherPreferences(skipIntro: true, playSoundInSilentMode: true))
        XCTAssertTrue(LauncherPreferences().playSoundInSilentMode, "Play sound in silent mode defaults to ON")
        XCTAssertEqual(LauncherPreferences().frameRate, 60, "Frame Rate defaults to 60")
        XCTAssertEqual(LauncherPreferences.load(from: home.paths.preferencesFile).frameRate, 60, "missing key: 60")
    }

    func testPathsMatchTheEngine() {
        let paths = LauncherPaths(home: URL(fileURLWithPath: "/h"), bundledGameData: URL(fileURLWithPath: "/b/GameData"))
        XCTAssertEqual(paths.optionsIni.path, "/h/Library/Application Support/GeneralsX/GeneralsZH/Options.ini")
        XCTAssertEqual(paths.settingsDir.path, "/h/Library/Application Support/GeneralsX/launcher")
        XCTAssertEqual(paths.currentLog.path, "/h/Documents/generals-stderr.log")
        XCTAssertEqual(paths.previousLog.path, "/h/Documents/generals-stderr-prev.log")
    }
}
