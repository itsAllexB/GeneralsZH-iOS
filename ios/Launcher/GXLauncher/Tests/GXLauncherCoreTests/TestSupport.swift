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

// GeneralsX @feature iOS launcher 25/10/2026 Helpers for the launcher core tests: a throwaway
// home directory and a writer for small but well-formed .big archives.

import Foundation
import XCTest
@testable import GXLauncherCore

/// A temporary home directory laid out like the app's sandbox, removed on deinit.
final class TempHome {
    let root: URL
    let paths: LauncherPaths

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("gxlauncher-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        paths = LauncherPaths(home: root.appendingPathComponent("home", isDirectory: true),
                              bundledGameData: root.appendingPathComponent("App.app/GameData", isDirectory: true))
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }
}

enum BigWriter {
    /// A .big archive in the engine's layout holding `entries` (backslash paths) with tiny payloads.
    static func archive(_ entries: [String]) -> Data {
        var table = Data()
        let names = entries.map { Array($0.utf8) + [0] }
        let headerSize = 16 + names.reduce(0) { $0 + 8 + $1.count }
        var offset = UInt32(headerSize)
        var payload = Data()
        for (index, name) in names.enumerated() {
            let body = Data("payload \(index)\n".utf8)
            table.append(be(offset))
            table.append(be(UInt32(body.count)))
            table.append(contentsOf: name)
            payload.append(body)
            offset += UInt32(body.count)
        }
        var data = Data("BIGF".utf8)
        var size = UInt32(headerSize + payload.count).littleEndian
        data.append(Data(bytes: &size, count: 4))
        data.append(be(UInt32(entries.count)))
        data.append(be(UInt32(headerSize)))
        data.append(table)
        data.append(payload)
        return data
    }

    static func be(_ value: UInt32) -> Data {
        var v = value.bigEndian
        return Data(bytes: &v, count: 4)
    }

    static func write(_ entries: [String], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try archive(entries).write(to: url)
    }

    /// A complete fake Zero Hour folder: the ZH archives at the top, the base game in ZH_Generals.
    static func makeGameFolder(at folder: URL, weatherIn iniArchive: String = "INIZH.big") throws {
        try write(iniArchive == "INIZH.big"
                  ? ["Data\\INI\\GameData.ini", "Data\\INI\\Default\\Weather.ini", "Data\\INI\\Weather.ini"]
                  : ["Data\\INI\\GameData.ini"],
                  to: folder.appendingPathComponent("INIZH.big"))
        for name in ["TexturesZH.big", "W3DZH.big", "WindowZH.big"] {
            try write(["Art\\Textures\\\(name).tga"], to: folder.appendingPathComponent(name))
        }
        let base = folder.appendingPathComponent("ZH_Generals")
        try write(iniArchive == "INI.big"
                  ? ["Data\\INI\\GameData.ini", "Data\\INI\\Default\\Weather.ini"]
                  : ["Data\\INI\\GameData.ini"],
                  to: base.appendingPathComponent("INI.big"))
        for name in ["Terrain.big", "Textures.big", "W3D.big", "Window.big", "shaders.big",
                     "Audio.big", "Speech.big", "maps.big", "Music.big"] {
            try write(["Data\\\(name).dat"], to: base.appendingPathComponent(name))
        }
        try Data("IdealStaticGameLOD = High\nStaticGameLOD = High\n".utf8)
            .write(to: folder.appendingPathComponent("DefaultOptions.ini"))
    }
}
