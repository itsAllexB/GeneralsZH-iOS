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

// GeneralsX @feature iOS launcher 25/10/2026 Arguments, environment, frame rate and the log reader.

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

        // Nothing on disk: GX_SETTINGS_DIR and the audio category (sound in silent mode is ON).
        var plan = LaunchPlanBuilder.plan(paths: paths, preferences: LauncherPreferences(), safeInsets: nil)
        XCTAssertEqual(plan.environment.map(\.name), ["GX_SETTINGS_DIR", "SDL_AUDIO_CATEGORY", "GX_FPS_LIMIT"])
        XCTAssertEqual(plan.value(of: "GX_SETTINGS_DIR"), paths.settingsDir.path)
        XCTAssertEqual(plan.value(of: "SDL_AUDIO_CATEGORY"), "playback")

        // Bundled data, a UI scale and two diagnostics.
        try BigWriter.makeGameFolder(at: paths.bundledGameData)
        try OptionsIniStore(file: paths.optionsIni, defaults: nil).update { $0.set("GXUiScale", "140") }
        try MarkerFile.trace.set(true, in: paths)
        try MarkerFile.touchDebug.set(true, in: paths)
        try MarkerFile.loggingOff.set(true, in: paths)
        plan = LaunchPlanBuilder.plan(paths: paths, preferences: LauncherPreferences(skipIntro: true, playSoundInSilentMode: false),
                                      safeInsets: nil)
        XCTAssertEqual(plan.arguments, ["-nologo"])
        XCTAssertEqual(plan.environment.map(\.name),
                       ["GX_SETTINGS_DIR", "GX_GAME_DATA_DIR", "GX_UI_SCALE", "GX_TRACE", "GX_TOUCH_DEBUG",
                        "SDL_AUDIO_CATEGORY", "GX_FPS_LIMIT"])
        XCTAssertEqual(plan.value(of: "GX_GAME_DATA_DIR"), paths.bundledGameData.path)
        XCTAssertEqual(plan.value(of: "GX_UI_SCALE"), "140")
        XCTAssertEqual(plan.value(of: "GX_TRACE"), "1")
        XCTAssertEqual(plan.value(of: "SDL_AUDIO_CATEGORY"), "ambient")
        XCTAssertNil(plan.value(of: "GENERALSX_BUNDLED_FONTS_DIR"))
        XCTAssertNil(plan.value(of: "DXVK_CONFIG_FILE"))

        // A chosen folder beats the bundle.
        let external = home.root.appendingPathComponent("Files/Zero Hour")
        plan = LaunchPlanBuilder.plan(paths: paths, preferences: LauncherPreferences(), safeInsets: nil, externalFolder: external)
        XCTAssertEqual(plan.value(of: "GX_GAME_DATA_DIR"), external.path)

        // Support files could not be copied: the engine is pointed at the bundle's copies.
        plan = LaunchPlanBuilder.plan(paths: paths, preferences: LauncherPreferences(), safeInsets: nil,
                                      externalFolder: external, supportFallback: true)
        XCTAssertEqual(plan.value(of: "GENERALSX_BUNDLED_FONTS_DIR"), paths.bundledSupport.appendingPathComponent("fonts").path)
        XCTAssertEqual(plan.value(of: "DXVK_CONFIG_FILE"), paths.bundledSupport.appendingPathComponent("dxvk.conf").path)
    }

    func testInterfaceScaleExport() throws {
        let home = try TempHome()
        let store = OptionsIniStore(file: home.paths.optionsIni, defaults: nil)
        func exported() -> String? {
            LaunchPlanBuilder.plan(paths: home.paths, preferences: LauncherPreferences(), safeInsets: nil).value(of: "GX_UI_SCALE")
        }
        XCTAssertNil(exported(), "no key: engine default")
        try store.update { $0.set("GXUiScale", "70") }
        XCTAssertEqual(exported(), "70", "below 100 is exported (the engine shrinks the interface)")
        try store.update { $0.set("GXUiScale", "60") }
        XCTAssertEqual(exported(), "70", "clamped to the 70% floor")
        try store.update { $0.set("GXUiScale", "100") }
        XCTAssertNil(exported(), "100 is the engine's default and may be omitted")
        try store.update { $0.set("GXUiScale", "250") }
        XCTAssertEqual(exported(), "200")
    }

    func testDataSourcePriority() throws {
        let home = try TempHome()
        let paths = home.paths
        let external = home.root.appendingPathComponent("Files/ZH")
        XCTAssertNil(LaunchPlanBuilder.gameDataSource(paths: paths, externalFolder: nil))
        try BigWriter.makeGameFolder(at: paths.bundledGameData)
        XCTAssertEqual(LaunchPlanBuilder.gameDataSource(paths: paths, externalFolder: nil), .bundled(paths.bundledGameData))
        XCTAssertEqual(LaunchPlanBuilder.gameDataSource(paths: paths, externalFolder: external), .external(external))
        XCTAssertFalse(GameDataSource.bundled(paths.bundledGameData).takesSupportFiles)
        XCTAssertTrue(GameDataSource.external(external).takesSupportFiles)
    }

    func testFrameRateExportAndFallback() throws {
        let home = try TempHome()
        func fps(_ saved: Int, screen: Int) -> String? {
            LaunchPlanBuilder.plan(paths: home.paths, preferences: LauncherPreferences(frameRate: saved), safeInsets: nil,
                                   maximumFramesPerSecond: screen).value(of: "GX_FPS_LIMIT")
        }
        XCTAssertEqual(fps(60, screen: 60), "60")
        XCTAssertEqual(fps(60, screen: 120), "60")
        XCTAssertEqual(fps(120, screen: 120), "120")
        XCTAssertEqual(fps(120, screen: 60), "60", "120 saved but the screen cannot show it")
        XCTAssertEqual(fps(30, screen: 120), "60", "30 is no longer offered")
        XCTAssertEqual(fps(7, screen: 120), "60")
        XCTAssertEqual(LaunchPlanBuilder.plan(paths: home.paths, preferences: LauncherPreferences(), safeInsets: nil)
            .value(of: "GX_FPS_LIMIT"), "60", "always exported, 60 by default")
        XCTAssertEqual(FrameRate.choices(maximumFramesPerSecond: 60), [60])
        XCTAssertEqual(FrameRate.choices(maximumFramesPerSecond: 120), [60, 120])
        XCTAssertEqual(FrameRate.choices(maximumFramesPerSecond: 0), [60])
    }

    func testApplyUnsetsWhatAnEarlierRunSet() {
        // gx_launcher_run() can run again over the running game: a switch turned off must go.
        setenv("GX_LAUNCHER_TEST_KEEP", "scheme", 1)  // set by someone else: never touched
        LaunchPlanBuilder.apply(LaunchPlan(arguments: [], environment: [("GX_LAUNCHER_TEST_A", "1"), ("GX_LAUNCHER_TEST_B", "70")]))
        XCTAssertEqual(ProcessInfo.processInfo.environment["GX_LAUNCHER_TEST_A"], "1")
        let unset = LaunchPlanBuilder.apply(LaunchPlan(arguments: [], environment: [("GX_LAUNCHER_TEST_B", "80")]))
        XCTAssertEqual(unset, ["GX_LAUNCHER_TEST_A"])
        XCTAssertNil(ProcessInfo.processInfo.environment["GX_LAUNCHER_TEST_A"], "dropped from the plan -> unset")
        XCTAssertEqual(ProcessInfo.processInfo.environment["GX_LAUNCHER_TEST_B"], "80")
        XCTAssertEqual(ProcessInfo.processInfo.environment["GX_LAUNCHER_TEST_KEEP"], "scheme")
        LaunchPlanBuilder.apply(LaunchPlan(arguments: [], environment: []))
        XCTAssertNil(ProcessInfo.processInfo.environment["GX_LAUNCHER_TEST_B"])
        unsetenv("GX_LAUNCHER_TEST_KEEP")
    }

    func testApplySetsEnvironment() {
        let plan = LaunchPlan(arguments: [], environment: [("GX_LAUNCHER_TEST_VAR", "abc")])
        LaunchPlanBuilder.apply(plan)
        XCTAssertEqual(ProcessInfo.processInfo.environment["GX_LAUNCHER_TEST_VAR"], "abc")
        unsetenv("GX_LAUNCHER_TEST_VAR")
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
