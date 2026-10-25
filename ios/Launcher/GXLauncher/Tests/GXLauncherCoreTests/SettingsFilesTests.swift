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
        XCTAssertEqual(ControlScheme(attackMove: true).preset, .custom)
        var scheme = ControlScheme(cameraHigh: true)
        scheme.apply(.custom)
        XCTAssertEqual(scheme, ControlScheme(cameraHigh: true), "Custom keeps the switches")
        scheme.apply(.tactical)
        XCTAssertEqual(scheme, .tactical)
        scheme.apply(.classic)
        XCTAssertEqual(scheme, .classic)
    }

    func testControlSchemeFileTextMatchesAndroid() {
        XCTAssertEqual(ControlScheme.tactical.fileText, "attack_move=1\narmy_buttons=1\ncamera_high=1\n")
        XCTAssertEqual(ControlScheme(armyButtons: true).fileText, "attack_move=0\narmy_buttons=1\ncamera_high=0\n")
    }

    func testControlSchemeWriteAndRead() throws {
        let home = try TempHome()
        let file = home.paths.settingsFile(ControlScheme.fileName)
        let custom = ControlScheme(attackMove: true, cameraHigh: true)
        try custom.write(to: file)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "attack_move=1\narmy_buttons=0\ncamera_high=1\n")
        XCTAssertEqual(ControlScheme.read(from: file), custom)

        try ControlScheme.classic.write(to: file)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path), "Classic = no file (retail)")
        XCTAssertEqual(ControlScheme.read(from: file), .classic)
        try ControlScheme.classic.write(to: file)  // deleting twice is fine
    }

    func testControlSchemeParseIsTolerant() {
        let parsed = ControlScheme.parse("# comment\n camera_high = 1 \nattack_move=yes\nunknown=1\narmy_buttons=1\r\n")
        XCTAssertEqual(parsed, ControlScheme(attackMove: false, armyButtons: true, cameraHigh: true))
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
        let prefs = LauncherPreferences(skipIntro: true, preferImportedData: true)
        try prefs.save(to: home.paths.preferencesFile)
        XCTAssertEqual(LauncherPreferences.load(from: home.paths.preferencesFile), prefs)
        try Data("{\"skipIntro\": true}".utf8).write(to: home.paths.preferencesFile)
        XCTAssertEqual(LauncherPreferences.load(from: home.paths.preferencesFile),
                       LauncherPreferences(skipIntro: true, preferImportedData: false))
    }

    func testPathsMatchTheEngine() {
        let paths = LauncherPaths(home: URL(fileURLWithPath: "/h"), bundledGameData: URL(fileURLWithPath: "/b/GameData"))
        XCTAssertEqual(paths.optionsIni.path, "/h/Library/Application Support/GeneralsX/GeneralsZH/Options.ini")
        XCTAssertEqual(paths.settingsDir.path, "/h/Library/Application Support/GeneralsX/launcher")
        XCTAssertEqual(paths.importedGameData.path, "/h/Library/Application Support/GeneralsX/ImportedGameData")
        XCTAssertEqual(paths.currentLog.path, "/h/Documents/generals-stderr.log")
        XCTAssertEqual(paths.previousLog.path, "/h/Documents/generals-stderr-prev.log")
    }
}
