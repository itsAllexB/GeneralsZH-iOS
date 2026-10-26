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

// GeneralsX @feature iOS launcher 25/10/2026 Is this folder a complete Zero Hour install?
//
// A port of the Android launcher's Zero Hour checks (SetupActivity.isValidGameFolder +
// findGameFolderIntegrityIssues), which exist because a truncated copy passes "the files are
// there" and then dies deep in GameEngine::init() ("No files read from directory
// 'Data\INI\Default\Weather'"), or renders the battlefield magenta when only *ZH.big is present:
//
//   0. The folder holds INIZH.big or INI.big (isValidGameFolder, Zero Hour).
//   1. Every *.big in the folder and in each immediate subfolder (e.g. ZH_Generals) is non-empty
//      and starts with "BIGF".
//   2. At least one of the ini archives found (INI.big / INIZH.big, root or subfolder) lists
//      Data\INI\Default\Weather.ini -- the merged filesystem only needs it in one of them.
//   3. The base Generals archives (INI, Terrain, Textures, W3D, Window, Shaders, Audio, Speech,
//      Maps, Music) are present somewhere in the scanned folders.
//
// Differences from Android, all deliberate:
//   - Names are compared case-insensitively everywhere (Android used File.exists() for step 0).
//     The bundled ZH_Generals ships "maps.big"/"shaders.big" in lower case.
//   - No separate "base Generals folder" setting: on iOS the base archives are bundled (in
//     GameData/ZH_Generals) or part of the chosen game folder.
//   - The original-Generals game mode (GameData.ini check) is not offered yet; the critical entry
//     is a parameter so it can be.

import Foundation

public struct GameDataReport: Equatable, Sendable {
    public enum Issue: Equatable, Sendable, Hashable {
        /// The folder does not exist or is not a directory.
        case folderMissing
        /// Neither INIZH.big nor INI.big at the top level.
        case notAGameFolder
        /// A .big of 0 bytes (relative name, subfolder prefixed with "Sub\").
        case emptyArchive(String)
        /// A .big without the BIGF magic.
        case badHeader(String)
        /// None of these ini archives lists the critical entry: an incomplete copy.
        case missingData(archives: [String])
        /// Base Generals archives absent from every scanned folder.
        case missingBaseArchives([String])
    }

    public var folder: URL
    public var issues: [Issue]
    /// Every .big found (relative names), for display.
    public var archives: [String]
    /// Total size of the archives found, in bytes.
    public var totalBytes: Int64

    public var isOK: Bool { issues.isEmpty }
}

public enum GameDataValidator {
    /// Zero Hour's required top-level archives: either is enough (Android REQUIRED_GAME_FILES).
    public static let requiredArchives = ["INIZH.big", "INI.big"]
    /// Zero Hour's critical ini entry (Android BIG_CRITICAL_ENTRY).
    public static let zeroHourCriticalEntry = "data\\ini\\default\\weather.ini"
    /// The original game's critical entry (Android GENERALS_BIG_CRITICAL_ENTRY), for a later pass.
    public static let generalsCriticalEntry = "data\\ini\\gamedata.ini"
    /// The base Generals archives, named as they ship (Android BASE_GAME_REQUIRED_ARCHIVES).
    public static let baseGameArchives = [
        "INI.big", "Terrain.big", "Textures.big", "W3D.big", "Window.big",
        "Shaders.big", "Audio.big", "Speech.big", "Maps.big", "Music.big",
    ]

    /// Validates `folder`. Synchronous and file-system bound: call it off the main thread.
    public static func validate(_ folder: URL, criticalEntry: String = zeroHourCriticalEntry) -> GameDataReport {
        var report = GameDataReport(folder: folder, issues: [], archives: [], totalBytes: 0)
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: folder.path, isDirectory: &isDir), isDir.boolValue else {
            report.issues = [.folderMissing]
            return report
        }

        let topLevel = bigFiles(in: folder)
        let topNames = Set(topLevel.map { $0.lastPathComponent.lowercased() })
        guard requiredArchives.contains(where: { topNames.contains($0.lowercased()) }) else {
            report.issues = [.notAGameFolder]
            report.archives = topLevel.map(\.lastPathComponent).sorted()
            return report
        }

        // The folder itself plus every immediate, non-hidden subfolder.
        var roots: [(url: URL, prefix: String)] = [(folder, "")]
        let subfolders = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey],
                                                      options: [.skipsHiddenFiles])) ?? []
        for sub in subfolders.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        where (try? sub.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            roots.append((sub, sub.lastPathComponent + "\\"))
        }

        var iniArchives: [(url: URL, label: String)] = []
        var present = Set<String>()
        for root in roots {
            let files = root.url == folder ? topLevel : bigFiles(in: root.url)
            for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let label = root.prefix + file.lastPathComponent
                let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
                report.archives.append(label)
                report.totalBytes += size
                if size == 0 {
                    report.issues.append(.emptyArchive(label))
                    continue
                }
                if !BigArchive.hasBigFHeader(file) {
                    report.issues.append(.badHeader(label))
                    continue
                }
                let lower = file.lastPathComponent.lowercased()
                if lower == "ini.big" || lower == "inizh.big" {
                    iniArchives.append((file, label))
                }
                present.insert(lower)
            }
        }

        if !iniArchives.isEmpty,
           !iniArchives.contains(where: { BigArchive.contains(criticalEntry, in: $0.url) }) {
            report.issues.append(.missingData(archives: iniArchives.map(\.label)))
        }

        let missingBase = baseGameArchives.filter { !present.contains($0.lowercased()) }
        if !missingBase.isEmpty {
            report.issues.append(.missingBaseArchives(missingBase))
        }
        return report
    }

    /// Android's isValidGameFolder() for Zero Hour: INIZH.big or INI.big at the top level (any
    /// case). An iCloud ".INIZH.big.icloud" placeholder counts: the archive is there, just not
    /// downloaded yet.
    public static func isGameFolder(_ folder: URL) -> Bool {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
            .map { (UbiquitousFiles.placeholderTarget($0) ?? $0).lowercased() }
        return requiredArchives.contains { names.contains($0.lowercased()) }
    }

    /// The game folder at or below `folder`: `folder` itself when it is one, else the ONLY game
    /// folder within three levels below it (nil when there is none or more than one, so the
    /// player has to choose). Bounded like Android's findGameFolderBelow(): at most 300 folders
    /// are listed, hidden folders are skipped, and a game folder is not searched further.
    public static func findGameFolder(in folder: URL) -> URL? {
        if isGameFolder(folder) { return folder }
        var queue: [(URL, Int)] = [(folder, 0)]
        var found: URL?
        var listed = 0
        while !queue.isEmpty && listed < 300 {
            let (dir, depth) = queue.removeFirst()
            listed += 1
            let children = ((try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? [])
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            for child in children {
                if isGameFolder(child) {
                    if found != nil { return nil }
                    found = child
                } else if depth + 1 < 3 {
                    queue.append((child, depth + 1))
                }
            }
        }
        return found
    }

    /// The *.big files directly inside `folder` (any case).
    static func bigFiles(in folder: URL) -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles])) ?? []
        return items.filter { $0.pathExtension.lowercased() == "big" }
    }
}
