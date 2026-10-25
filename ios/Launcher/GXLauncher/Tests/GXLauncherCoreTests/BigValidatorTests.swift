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

// GeneralsX @feature iOS launcher 25/10/2026 The BIG table reader and the game folder check.

import XCTest
@testable import GXLauncherCore

final class BigValidatorTests: XCTestCase {
    func testReadsEntries() throws {
        let home = try TempHome()
        let url = home.root.appendingPathComponent("INIZH.big")
        try BigWriter.write(["Data\\INI\\Default\\Weather.ini", "Data\\INI\\GameData.ini"], to: url)
        XCTAssertTrue(BigArchive.hasBigFHeader(url))
        XCTAssertEqual(try BigArchive.entries(in: url), ["data/ini/default/weather.ini", "data/ini/gamedata.ini"])
        XCTAssertTrue(BigArchive.contains("Data\\INI\\Default\\Weather.ini", in: url))
        XCTAssertTrue(BigArchive.contains("data/ini/default/WEATHER.ini", in: url))
        XCTAssertFalse(BigArchive.contains("data\\ini\\nope.ini", in: url))
    }

    func testTruncatedTableIsNotAMatch() throws {
        let home = try TempHome()
        let url = home.root.appendingPathComponent("INIZH.big")
        let full = BigWriter.archive(["Data\\INI\\A.ini", "Data\\INI\\Default\\Weather.ini"])
        // Cut in the middle of the second name.
        try full.prefix(16 + 8 + 16 + 8 + 10).write(to: url)
        XCTAssertFalse(BigArchive.contains("data\\ini\\default\\weather.ini", in: url))
        XCTAssertThrowsError(try BigArchive.entries(in: url)) { error in
            XCTAssertEqual(error as? BigArchive.ReadError, .truncated(afterEntries: 1))
        }
    }

    func testBadHeaderAndImplausibleCount() throws {
        let home = try TempHome()
        let bad = home.root.appendingPathComponent("bad.big")
        try Data("NOPE0000000000000000".utf8).write(to: bad)
        XCTAssertFalse(BigArchive.hasBigFHeader(bad))
        XCTAssertThrowsError(try BigArchive.entries(in: bad))

        var huge = Data("BIGF".utf8) + Data(count: 4)
        huge += BigWriter.be(UInt32(600_000)) + BigWriter.be(16)
        let hugeURL = home.root.appendingPathComponent("huge.big")
        try huge.write(to: hugeURL)
        XCTAssertThrowsError(try BigArchive.entries(in: hugeURL)) { error in
            XCTAssertEqual(error as? BigArchive.ReadError, .implausibleCount(600_000))
        }
    }

    func testCompleteFolderIsOK() throws {
        let home = try TempHome()
        try BigWriter.makeGameFolder(at: home.paths.bundledGameData)
        let report = GameDataValidator.validate(home.paths.bundledGameData)
        XCTAssertEqual(report.issues, [])
        XCTAssertTrue(report.isOK)
        XCTAssertTrue(report.archives.contains("ZH_Generals\\INI.big"))
        XCTAssertGreaterThan(report.totalBytes, 0)
    }

    func testWeatherInBaseIniArchiveIsEnough() throws {
        let home = try TempHome()
        try BigWriter.makeGameFolder(at: home.paths.bundledGameData, weatherIn: "INI.big")
        XCTAssertTrue(GameDataValidator.validate(home.paths.bundledGameData).isOK)
    }

    func testMissingFolderAndNotAGameFolder() throws {
        let home = try TempHome()
        XCTAssertEqual(GameDataValidator.validate(home.paths.bundledGameData).issues, [.folderMissing])
        try BigWriter.write(["x"], to: home.paths.bundledGameData.appendingPathComponent("Music.big"))
        XCTAssertEqual(GameDataValidator.validate(home.paths.bundledGameData).issues, [.notAGameFolder])
    }

    func testCorruptAndIncompleteArchives() throws {
        let home = try TempHome()
        let folder = home.paths.bundledGameData
        try BigWriter.makeGameFolder(at: folder)
        // An INIZH.big without Weather.ini, an empty archive and one with a bad header.
        try BigWriter.write(["Data\\INI\\GameData.ini"], to: folder.appendingPathComponent("INIZH.big"))
        try BigWriter.write(["Data\\INI\\GameData.ini"], to: folder.appendingPathComponent("ZH_Generals/INI.big"))
        try Data().write(to: folder.appendingPathComponent("SpeechZH.big"))
        try Data("garbage!".utf8).write(to: folder.appendingPathComponent("ZH_Generals/Music.big"))
        let report = GameDataValidator.validate(folder)
        XCTAssertEqual(Set(report.issues), [
            .emptyArchive("SpeechZH.big"),
            .badHeader("ZH_Generals\\Music.big"),
            .missingData(archives: ["INIZH.big", "ZH_Generals\\INI.big"]),
            .missingBaseArchives(["Music.big"]),
        ])
        XCTAssertFalse(report.isOK)
    }

    func testZeroHourOnlyFolderNeedsBaseGame() throws {
        let home = try TempHome()
        let folder = home.paths.bundledGameData
        try BigWriter.write(["Data\\INI\\Default\\Weather.ini"], to: folder.appendingPathComponent("INIZH.big"))
        let report = GameDataValidator.validate(folder)
        XCTAssertEqual(report.issues, [.missingBaseArchives(GameDataValidator.baseGameArchives)])
    }

    /// Real game data (read-only, headers only), when GX_REAL_GAMEDATA points at a folder,
    /// e.g. build/ios-package/GeneralsXZH.app/GameData of a packaged engine build.
    func testRealGameDataIfAvailable() throws {
        let candidates = [
            ProcessInfo.processInfo.environment["GX_REAL_GAMEDATA"],
        ].compactMap { $0 }
        guard let folder = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            throw XCTSkip("no real GameData on this machine")
        }
        let url = URL(fileURLWithPath: folder, isDirectory: true)
        let start = Date()
        let report = GameDataValidator.validate(url)
        XCTAssertEqual(report.issues, [], "real game data should validate")
        XCTAssertTrue(BigArchive.contains(GameDataValidator.zeroHourCriticalEntry, in: url.appendingPathComponent("INIZH.big"))
                      || BigArchive.contains(GameDataValidator.zeroHourCriticalEntry, in: url.appendingPathComponent("ZH_Generals/INI.big")))
        XCTAssertLessThan(Date().timeIntervalSince(start), 5, "only the tables are read")
    }
}
