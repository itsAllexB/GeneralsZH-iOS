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

// GeneralsX @feature iOS launcher 25/10/2026 Arguments, environment, the importer and the log reader.

import XCTest
@testable import GXLauncherCore

final class LaunchPlanTests: XCTestCase {
    func testArgumentsOrderAndFormat() {
        let insets = SafeInsets(left: 0.0675, top: 0, right: 0.0675, bottom: 0.047727)
        XCTAssertEqual(LaunchPlanBuilder.arguments(preferences: LauncherPreferences(skipIntro: true), safeInsets: insets),
                       ["-gxSafeInsets", "0.0675,0.0000,0.0675,0.0477", "-nologo"])
        XCTAssertEqual(LaunchPlanBuilder.arguments(preferences: LauncherPreferences(), safeInsets: nil), [])
        XCTAssertEqual(LaunchPlanBuilder.arguments(preferences: LauncherPreferences(skipIntro: true),
                                                   safeInsets: SafeInsets(left: 0, top: 0, right: 0, bottom: 0)),
                       ["-nologo"], "zero insets are the default; not passed")
    }

    func testSafeInsetsLandscapeAndPortrait() {
        // Landscape: straight fractions.
        let land = SafeInsets.landscapeFractions(top: 0, left: 62, bottom: 21, right: 62, width: 956, height: 440)!
        XCTAssertEqual(land.left, 62.0 / 956, accuracy: 1e-9)
        XCTAssertEqual(land.bottom, 21.0 / 440, accuracy: 1e-9)
        // Portrait: rotated into the landscape frame the game will use.
        let port = SafeInsets.landscapeFractions(top: 62, left: 0, bottom: 34, right: 0, width: 440, height: 956)!
        XCTAssertEqual(port.left, 62.0 / 956, accuracy: 1e-9)
        XCTAssertEqual(port.right, 62.0 / 956, accuracy: 1e-9)
        XCTAssertEqual(port.top, 0)
        XCTAssertEqual(port.bottom, 34.0 / 440, accuracy: 1e-9)
        XCTAssertNil(SafeInsets.landscapeFractions(top: 0, left: 0, bottom: 0, right: 0, width: 0, height: 0))
    }

    func testDecimalPointIgnoresLocale() {
        XCTAssertEqual(SafeInsets(left: 0.5, top: 0.25, right: 0.5, bottom: 0.125).argument, "0.5000,0.2500,0.5000,0.1250")
    }

    func testPlanEnvironment() throws {
        let home = try TempHome()
        let paths = home.paths
        try paths.ensureSettingsDir()

        // Nothing on disk: only GX_SETTINGS_DIR.
        var plan = LaunchPlanBuilder.plan(paths: paths, preferences: LauncherPreferences(), safeInsets: nil)
        XCTAssertEqual(plan.environment.map(\.name), ["GX_SETTINGS_DIR"])
        XCTAssertEqual(plan.value(of: "GX_SETTINGS_DIR"), paths.settingsDir.path)

        // Bundled data, a UI scale and two diagnostics.
        try BigWriter.makeGameFolder(at: paths.bundledGameData)
        try OptionsIniStore(file: paths.optionsIni, defaults: nil).update { $0.set("GXUiScale", "140") }
        try MarkerFile.trace.set(true, in: paths)
        try MarkerFile.touchDebug.set(true, in: paths)
        try MarkerFile.loggingOff.set(true, in: paths)
        plan = LaunchPlanBuilder.plan(paths: paths, preferences: LauncherPreferences(skipIntro: true), safeInsets: nil)
        XCTAssertEqual(plan.arguments, ["-nologo"])
        XCTAssertEqual(plan.environment.map(\.name),
                       ["GX_SETTINGS_DIR", "GX_GAME_DATA_DIR", "GX_UI_SCALE", "GX_TRACE", "GX_TOUCH_DEBUG"])
        XCTAssertEqual(plan.value(of: "GX_GAME_DATA_DIR"), paths.bundledGameData.path)
        XCTAssertEqual(plan.value(of: "GX_UI_SCALE"), "140")
        XCTAssertEqual(plan.value(of: "GX_TRACE"), "1")

        // Imported data wins only when preferred.
        try BigWriter.makeGameFolder(at: paths.importedGameData)
        plan = LaunchPlanBuilder.plan(paths: paths, preferences: LauncherPreferences(), safeInsets: nil)
        XCTAssertEqual(plan.value(of: "GX_GAME_DATA_DIR"), paths.bundledGameData.path)
        plan = LaunchPlanBuilder.plan(paths: paths, preferences: LauncherPreferences(preferImportedData: true), safeInsets: nil)
        XCTAssertEqual(plan.value(of: "GX_GAME_DATA_DIR"), paths.importedGameData.path)

        // No bundle: the imported copy is used even when not preferred.
        try FileManager.default.removeItem(at: paths.bundledGameData)
        plan = LaunchPlanBuilder.plan(paths: paths, preferences: LauncherPreferences(), safeInsets: nil)
        XCTAssertEqual(plan.value(of: "GX_GAME_DATA_DIR"), paths.importedGameData.path)
    }

    func testApplySetsEnvironment() {
        let plan = LaunchPlan(arguments: [], environment: [("GX_LAUNCHER_TEST_VAR", "abc")])
        LaunchPlanBuilder.apply(plan)
        XCTAssertEqual(ProcessInfo.processInfo.environment["GX_LAUNCHER_TEST_VAR"], "abc")
        unsetenv("GX_LAUNCHER_TEST_VAR")
    }

    func testImporterCopiesValidatesAndAddsRuntimeFiles() throws {
        let home = try TempHome()
        let source = home.root.appendingPathComponent("Picked/Zero Hour", isDirectory: true)
        try BigWriter.makeGameFolder(at: source)
        try FileManager.default.removeItem(at: source.appendingPathComponent("DefaultOptions.ini"))
        try Data().write(to: source.appendingPathComponent("._INIZH.big"))  // macOS metadata, skipped
        // The bundle provides the port's runtime files.
        try FileManager.default.createDirectory(at: home.paths.bundledGameData.appendingPathComponent("fonts"),
                                                withIntermediateDirectories: true)
        try Data("defaults".utf8).write(to: home.paths.bundledGameData.appendingPathComponent("DefaultOptions.ini"))
        try Data("font".utf8).write(to: home.paths.bundledGameData.appendingPathComponent("fonts/a.ttf"))

        let updates = UpdateCounter()
        let report = try GameDataImporter.importFolder(from: source, paths: home.paths) { progress in
            XCTAssertLessThanOrEqual(progress.copiedBytes, progress.totalBytes)
            updates.increment()
        }
        XCTAssertTrue(report.isOK, "\(report.issues)")
        XCTAssertGreaterThan(updates.value, 0)
        let fm = FileManager.default
        XCTAssertTrue(fm.fileExists(atPath: home.paths.importedGameData.appendingPathComponent("ZH_Generals/INI.big").path))
        XCTAssertFalse(fm.fileExists(atPath: home.paths.importedGameData.appendingPathComponent("._INIZH.big").path))
        XCTAssertTrue(fm.fileExists(atPath: home.paths.importedGameData.appendingPathComponent("DefaultOptions.ini").path))
        XCTAssertTrue(fm.fileExists(atPath: home.paths.importedGameData.appendingPathComponent("fonts/a.ttf").path))
        XCTAssertFalse(fm.fileExists(atPath: home.paths.importStaging.path))
        XCTAssertEqual(try Data(contentsOf: home.paths.importedGameData.appendingPathComponent("INIZH.big")),
                       try Data(contentsOf: source.appendingPathComponent("INIZH.big")))

        try GameDataImporter.removeImported(paths: home.paths)
        XCTAssertFalse(fm.fileExists(atPath: home.paths.importedGameData.path))
    }

    func testImporterRejectsNonGameFolder() throws {
        let home = try TempHome()
        let source = home.root.appendingPathComponent("Photos", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("jpeg".utf8).write(to: source.appendingPathComponent("a.jpg"))
        XCTAssertThrowsError(try GameDataImporter.importFolder(from: source, paths: home.paths) { _ in }) { error in
            XCTAssertEqual(error as? ImportError, .notAGameFolder)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.paths.importedGameData.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.paths.importStaging.path))
    }

    func testLogReaderHeadAndTail() throws {
        let home = try TempHome()
        try FileManager.default.createDirectory(at: home.paths.documents, withIntermediateDirectories: true)
        let small = "INFO: one\nERROR: two\nINFO: three\n"
        try Data(small.utf8).write(to: home.paths.currentLog)
        let excerpt = LogReader.read(home.paths.currentLog)
        XCTAssertEqual(excerpt.text, small)
        XCTAssertEqual(excerpt.elidedBytes, 0)
        XCTAssertEqual(LogReader.filter(excerpt.text, query: "error").text, "     2  ERROR: two")

        let big = String(repeating: "H", count: 70_000) + String(repeating: "M", count: 100_000) + String(repeating: "T", count: 140_000)
        try Data(big.utf8).write(to: home.paths.previousLog)
        let cut = LogReader.read(home.paths.previousLog)
        XCTAssertEqual(cut.fileSize, 310_000)
        XCTAssertEqual(cut.elidedBytes, 110_000)
        XCTAssertTrue(cut.text.hasPrefix(String(repeating: "H", count: 60_000) + "\n"))
        XCTAssertTrue(cut.text.hasSuffix(String(repeating: "T", count: 140_000)))

        XCTAssertNil(LogReader.read(home.root.appendingPathComponent("missing.log")).fileSize)
        LogReader.clear(paths: home.paths)
        XCTAssertNil(LogReader.read(home.paths.currentLog).fileSize)
    }
}

final class UpdateCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}
