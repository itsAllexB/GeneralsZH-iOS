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

// GeneralsX @feature iOS launcher 25/10/2026 Options.ini editing: in-place, format-preserving,
// seeded from DefaultOptions.ini, read with the engine's rules and Android's defaults/clamping.

import XCTest
@testable import GXLauncherCore

final class OptionsIniTests: XCTestCase {
    func testParsesLikeUserPreferences() {
        let doc = OptionsIniDocument(text: "A = 1\n  B=two words  \nnot a pair\nEmpty =\n = orphan\nA = 3\n")
        XCTAssertEqual(doc.value(for: "A"), "3", "a later duplicate wins, as in the engine's map")
        XCTAssertEqual(doc.value(for: "B"), "two words")
        XCTAssertNil(doc.value(for: "Empty"), "empty values are skipped by UserPreferences::load()")
        XCTAssertEqual(doc.entries.count, 3, "A, B and the second A")
    }

    func testSetReplacesInPlaceAndKeepsEverythingElse() {
        let original = "Resolution = 2868 1320\n; a comment line\n\nGXUiScale=120\nMusicVolume = 55\n"
        var doc = OptionsIniDocument(text: original)
        doc.set("GXUiScale", "150")
        XCTAssertEqual(doc.text, "Resolution = 2868 1320\n; a comment line\n\nGXUiScale=150\nMusicVolume = 55\n")
    }

    func testSetUpdatesEveryDuplicate() {
        var doc = OptionsIniDocument(text: "X = 1\nY = 2\nX = 3\n")
        doc.set("X", "9")
        XCTAssertEqual(doc.text, "X = 9\nY = 2\nX = 9\n")
    }

    func testSetAppendsNewKeyInEngineFormat() {
        var doc = OptionsIniDocument(text: "A = 1\n")
        doc.set("ResolutionFontAdjustment", "85")
        XCTAssertEqual(doc.text, "A = 1\nResolutionFontAdjustment = 85\n")
    }

    func testAppendToUnterminatedFile() {
        var doc = OptionsIniDocument(text: "A = 1")
        doc.set("B", "2")
        XCTAssertEqual(doc.text, "A = 1\nB = 2\n")
    }

    func testCRLFIsPreserved() {
        var doc = OptionsIniDocument(text: "A = 1\r\nB = 2\r\n")
        doc.set("B", "5")
        doc.set("C", "6")
        XCTAssertEqual(doc.text, "A = 1\r\nB = 5\r\nC = 6\r\n")
    }

    func testEmptyValueLineIsReused() {
        var doc = OptionsIniDocument(text: "GXUiScale =\n")
        doc.set("GXUiScale", "110")
        XCTAssertEqual(doc.text, "GXUiScale = 110\n")
    }

    func testRoundTripUntouched() {
        let text = "a=1\n\n  # x\n\tb =  2  \nc = 3"
        XCTAssertEqual(OptionsIniDocument(text: text).text, text)
        XCTAssertEqual(OptionsIniDocument(text: "").text, "")
    }

    func testRemove() {
        var doc = OptionsIniDocument(text: "A = 1\nB = 2\n")
        doc.remove("A")
        XCTAssertEqual(doc.text, "B = 2\n")
    }

    func testStoreSeedsFromDefaultOptionsWhenNew() throws {
        let home = try TempHome()
        let defaults = home.root.appendingPathComponent("DefaultOptions.ini")
        try Data("IdealStaticGameLOD = High\nHeatEffects = yes\n".utf8).write(to: defaults)
        let store = OptionsIniStore(file: home.paths.optionsIni, defaults: defaults)
        try store.update { $0.set(InterfaceScale.key, "130") }
        let written = try String(contentsOf: home.paths.optionsIni, encoding: .utf8)
        XCTAssertEqual(written, "IdealStaticGameLOD = High\nHeatEffects = yes\nGXUiScale = 130\n")

        // Existing file: defaults are not merged in again.
        try Data("Gamma = 50\n".utf8).write(to: home.paths.optionsIni)
        try store.update { $0.set(MenuTextSize.key, "90") }
        XCTAssertEqual(try String(contentsOf: home.paths.optionsIni, encoding: .utf8), "Gamma = 50\nResolutionFontAdjustment = 90\n")
    }

    func testStoreCreatesFileWithoutDefaults() throws {
        let home = try TempHome()
        try OptionsIniStore(file: home.paths.optionsIni, defaults: nil).update { $0.set("GXUiScale", "100") }
        XCTAssertEqual(try String(contentsOf: home.paths.optionsIni, encoding: .utf8), "GXUiScale = 100\n")
    }

    func testLatin1FileRoundTrips() throws {
        let home = try TempHome()
        try FileManager.default.createDirectory(at: home.paths.userDataDir, withIntermediateDirectories: true)
        let bytes: [UInt8] = Array("Name = Jos".utf8) + [0xE9] + Array("\nA = 1\n".utf8)
        try Data(bytes).write(to: home.paths.optionsIni)
        try OptionsIniStore(file: home.paths.optionsIni, defaults: nil).update { $0.set("A", "2") }
        let written = try Data(contentsOf: home.paths.optionsIni)
        XCTAssertEqual(Array(written), Array("Name = Jos".utf8) + [0xE9] + Array("\nA = 2\n".utf8),
                       "untouched lines keep their original bytes")
    }

    func testInterfaceScaleReadMatchesAndroid() {
        XCTAssertEqual(InterfaceScale.read(OptionsIniDocument(text: "")), 100)
        XCTAssertEqual(InterfaceScale.read(OptionsIniDocument(text: "GXUiScale = 140\n")), 140)
        XCTAssertEqual(InterfaceScale.read(OptionsIniDocument(text: "GXUiScale = 300\n")), 200)
        XCTAssertEqual(InterfaceScale.read(OptionsIniDocument(text: "GXUiScale = 70\n")), 70)
        XCTAssertEqual(InterfaceScale.read(OptionsIniDocument(text: "GXUiScale = 60\n")), 70, "clamped to the 70% floor")
        XCTAssertEqual(InterfaceScale.read(OptionsIniDocument(text: "GXUiScale = 100\n")), 100)
        XCTAssertEqual(InterfaceScale.read(OptionsIniDocument(text: "GXUiScale = abc\n")), 100)
        XCTAssertEqual(InterfaceScale.clamp(134), 130)
        XCTAssertEqual(InterfaceScale.clamp(95), 100)
        XCTAssertEqual(InterfaceScale.clamp(64), 70)
        XCTAssertEqual(InterfaceScale.clamp(80), 80)
        XCTAssertEqual(InterfaceScale.range, 70...200)
        XCTAssertEqual(InterfaceScale.defaultPercent, 100)
    }

    func testMenuTextSizeReadMatchesAndroid() {
        XCTAssertEqual(MenuTextSize.read(OptionsIniDocument(text: "")), 70)
        XCTAssertEqual(MenuTextSize.read(OptionsIniDocument(text: "ResolutionFontAdjustment = -100\n")), 70,
                       "negative = the game's default (what the in-game Options menu writes)")
        XCTAssertEqual(MenuTextSize.read(OptionsIniDocument(text: "ResolutionFontAdjustment = 0\n")), 0)
        XCTAssertEqual(MenuTextSize.read(OptionsIniDocument(text: "ResolutionFontAdjustment = 999\n")), 150)
        XCTAssertEqual(MenuTextSize.read(OptionsIniDocument(text: "ResolutionFontAdjustment = 85.000000\n")), 85)
    }

    func testMenuTextSizeStepAndRoundTrip() throws {
        XCTAssertEqual(MenuTextSize.step, 10)
        XCTAssertEqual(MenuTextSize.clamp(84), 80)
        XCTAssertEqual(MenuTextSize.clamp(86), 90)
        XCTAssertEqual(MenuTextSize.clamp(-5), 0)
        XCTAssertEqual(MenuTextSize.clamp(155), 150)
        // Every slider value round-trips through Options.ini.
        let home = try TempHome()
        let store = OptionsIniStore(file: home.paths.optionsIni, defaults: nil)
        for value in stride(from: 0, through: 150, by: 10) {
            try store.update { $0.set(MenuTextSize.key, String(MenuTextSize.clamp(value))) }
            XCTAssertEqual(MenuTextSize.read(store.load()), value)
        }
        // A value off the step (written by the in-game menu) is read as stored, not rewritten.
        try store.update { $0.set(MenuTextSize.key, "85") }
        XCTAssertEqual(MenuTextSize.read(store.load()), 85)
        XCTAssertEqual(store.load().value(for: MenuTextSize.key), "85")
    }
}
