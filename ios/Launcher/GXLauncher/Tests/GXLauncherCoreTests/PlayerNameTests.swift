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

// GeneralsX @feature iOS launcher 26/10/2026 Player Name: the game's quoted-printable UTF-16 form
// and the UserName key of Skirmish.ini / Network.ini.

import XCTest
@testable import GXLauncherCore

final class PlayerNameTests: XCTestCase {
    func testEncodingMatchesTheGame() {
        XCTAssertEqual(QuotedPrintable.encode("Al"), "A_00l_00")
        XCTAssertEqual(QuotedPrintable.encode("Bo b"), "B_00o_00_20_00b_00")
        XCTAssertEqual(QuotedPrintable.encode(""), "")
        // "Ș" is U+0218: low byte 0x18, high byte 0x02.
        XCTAssertEqual(QuotedPrintable.encode("Ș"), "_18_02")
    }

    func testRoundTrips() {
        for name in ["Al", "Bo b", "Ștefan", "Zoë-42", "Иван", "李小龍", "A.b,c!(x)", "General_7"] {
            XCTAssertEqual(QuotedPrintable.decode(QuotedPrintable.encode(name)), name, name)
        }
        XCTAssertEqual(QuotedPrintable.decode("B_00o_00_20_00b_00"), "Bo b")
        XCTAssertEqual(QuotedPrintable.decode("_19_02t_00e_00f_00a_00n_00"), "\u{0219}tefan")  // lower-case ș, U+0219
        // Like the engine: a trailing odd byte or a broken escape ends the name.
        XCTAssertEqual(QuotedPrintable.decode("A_00l"), "A")
        XCTAssertEqual(QuotedPrintable.decode("A_00_Z"), "A")
    }

    func testSanitizeAndLimit() {
        XCTAssertEqual(PlayerName.maxLength, 12)
        XCTAssertEqual(PlayerName.sanitize("  Bo b  "), "Bo b")
        XCTAssertEqual(PlayerName.sanitize("ABCDEFGHIJKLMNOP"), "ABCDEFGHIJKL")
        XCTAssertEqual(PlayerName.sanitize("Ștefan the Great"), "Ștefan the G")
        XCTAssertEqual(PlayerName.sanitize("Al\u{1F600}x\n"), "Alx", "emoji and newlines are dropped")
        XCTAssertEqual(PlayerName.sanitize("   "), "")
        XCTAssertEqual(PlayerName.filterTyping("abc "), "abc ", "typing keeps a trailing space")
        XCTAssertEqual(PlayerName.sanitize("[GLA] Tank-1"), "[GLA] Tank-1")
    }

    func testWriteBothFilesPreservingOtherLines() throws {
        let home = try TempHome()
        let paths = home.paths
        try FileManager.default.createDirectory(at: paths.userDataDir, withIntermediateDirectories: true)
        try Data("Color = 3\nUserName = O_00l_00d_00\nMap = maps\\alpine assault\\alpine assault.map\n".utf8)
            .write(to: paths.skirmishIni)

        XCTAssertEqual(PlayerName.read(paths: paths), "Old")
        XCTAssertTrue(try PlayerName.write("  Bo b ", paths: paths))
        XCTAssertEqual(try String(contentsOf: paths.skirmishIni, encoding: .utf8),
                       "Color = 3\nUserName = B_00o_00_20_00b_00\nMap = maps\\alpine assault\\alpine assault.map\n")
        XCTAssertEqual(try String(contentsOf: paths.networkIni, encoding: .utf8), "UserName = B_00o_00_20_00b_00\n",
                       "a missing Network.ini is created")
        XCTAssertEqual(PlayerName.read(paths: paths), "Bo b")
    }

    func testReadFallsBackToNetworkIniAndEmpty() throws {
        let home = try TempHome()
        let paths = home.paths
        XCTAssertEqual(PlayerName.read(paths: paths), "", "no files: empty field")
        try FileManager.default.createDirectory(at: paths.userDataDir, withIntermediateDirectories: true)
        try Data("Color = 1\n".utf8).write(to: paths.skirmishIni)
        try Data("UserName = \(QuotedPrintable.encode("Ștefan"))\n".utf8).write(to: paths.networkIni)
        XCTAssertEqual(PlayerName.read(paths: paths), "Ștefan")
        // A name of only spaces counts as none.
        try Data("UserName = _20_00_20_00\n".utf8).write(to: paths.skirmishIni)
        XCTAssertEqual(PlayerName.read(paths: paths), "Ștefan")
    }

    func testEmptyNameWritesNothing() throws {
        let home = try TempHome()
        XCTAssertFalse(try PlayerName.write("   ", paths: home.paths))
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.paths.skirmishIni.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.paths.networkIni.path))
        // An existing name is left alone too.
        try FileManager.default.createDirectory(at: home.paths.userDataDir, withIntermediateDirectories: true)
        try Data("UserName = A_00l_00\n".utf8).write(to: home.paths.skirmishIni)
        XCTAssertFalse(try PlayerName.write("", paths: home.paths))
        XCTAssertEqual(try String(contentsOf: home.paths.skirmishIni, encoding: .utf8), "UserName = A_00l_00\n")
    }
}
