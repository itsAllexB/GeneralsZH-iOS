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

// GeneralsX @feature iOS launcher 25/10/2026 The game folder the player chose in Files (Android's
// "Select game folder"). The published app ships without game data; the player copies their own
// Zero Hour folder to the device and points the launcher at it.
//
// A folder picked with UIDocumentPickerViewController is security-scoped. iOS has no
// .withSecurityScope bookmark option: a plain bookmark created from the security-scoped URL
// carries the access, and resolving it later yields a URL that can be opened with
// startAccessingSecurityScopedResource(). The access is NEVER stopped: the engine reads the game
// data with POSIX fopen() for the whole life of the process, and the sandbox extension that
// startAccessing... grants covers those calls too.
//
// The bookmark is of the folder the player PICKED. When that was a parent of the real game folder
// (GameDataValidator.findGameFolder), the path below it is stored alongside, so the picked
// folder's scope covers the game folder.
//
// Stored as $GX_SETTINGS_DIR/game_folder.json: {"bookmark": <base64>, "subpath": "...", "name": "..."}.

import Foundation

public struct GameFolderReference: Codable, Equatable, Sendable {
    /// Bookmark of the picked folder.
    public var bookmark: Data
    /// Path of the game folder below the picked folder; "" when the picked folder is the game folder.
    public var subpath: String
    /// Name of the game folder, for display when the bookmark cannot be resolved.
    public var name: String

    public init(bookmark: Data, subpath: String, name: String) {
        self.bookmark = bookmark
        self.subpath = subpath
        self.name = name
    }
}

public enum GameFolderStore {
    public static func load(paths: LauncherPaths) -> GameFolderReference? {
        guard let data = try? Data(contentsOf: paths.gameFolderFile) else { return nil }
        return try? JSONDecoder().decode(GameFolderReference.self, from: data)
    }

    public static func save(_ reference: GameFolderReference, paths: LauncherPaths) throws {
        try paths.ensureSettingsDir()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(reference).write(to: paths.gameFolderFile, options: .atomic)
    }

    public static func forget(paths: LauncherPaths) {
        // A folder found in Documents would be found again at the next check: remember that the
        // player let go of it.
        if let reference = load(paths: paths), let picked = try? resolve(reference),
           FolderLocation.of(picked, paths: paths) == .appDocuments {
            let folder = reference.subpath.isEmpty ? picked : picked.appendingPathComponent(reference.subpath)
            try? Data(folder.standardizedFileURL.path.utf8).write(to: paths.forgottenDocumentsFolderFile, options: .atomic)
        }
        try? FileManager.default.removeItem(at: paths.gameFolderFile)
    }

    /// The saved reference, or else a game folder copied into the app's Documents (Finder's file
    /// sharing, which is how most players get 2-3 GB onto the device). The app's own folder does
    /// not show up in Files: that needs LSSupportsOpeningDocumentsInPlace, which with file sharing
    /// leaves the document picker of development-signed apps stuck (iOS 27.2). A Documents folder
    /// the player forgot is not taken again.
    public static func loadOrAdoptDocumentsFolder(paths: LauncherPaths) -> GameFolderReference? {
        if let saved = load(paths: paths) { return saved }
        guard let found = GameDataValidator.findGameFolder(in: paths.documents) else { return nil }
        if let forgotten = try? String(contentsOf: paths.forgottenDocumentsFolderFile, encoding: .utf8),
           forgotten == found.standardizedFileURL.path {
            return nil
        }
        guard let reference = try? makeReference(picked: paths.documents, gameFolder: found) else { return nil }
        try? save(reference, paths: paths)
        return reference
    }

    static func resolve(_ reference: GameFolderReference) throws -> URL {
        var stale = false
        return try URL(resolvingBookmarkData: reference.bookmark, options: [], relativeTo: nil,
                       bookmarkDataIsStale: &stale)
    }

    /// A reference for `gameFolder`, found at or below the `picked` folder. Call while the picked
    /// folder's security scope is open.
    public static func makeReference(picked: URL, gameFolder: URL) throws -> GameFolderReference {
        let bookmark = try picked.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        return GameFolderReference(bookmark: bookmark, subpath: relativePath(of: gameFolder, below: picked),
                                   name: gameFolder.lastPathComponent)
    }

    /// "Sub/Dir" for `child` below `parent`; "" when they are the same folder.
    static func relativePath(of child: URL, below parent: URL) -> String {
        let p = parent.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let c = child.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        guard c.count >= p.count, Array(c.prefix(p.count)) == p else { return "" }
        return c.dropFirst(p.count).joined(separator: "/")
    }
}

/// Opens the saved game folder for the rest of the process.
public enum GameFolderAccess {
    public enum State: Equatable, Sendable {
        /// No folder chosen.
        case none
        /// A folder was chosen but cannot be reached (deleted, moved, drive unplugged...).
        case unavailable(name: String, reason: String)
        /// The game folder (scope open) and the folder that was picked.
        case open(gameFolder: URL, picked: URL)
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var opened = Set<String>()

    /// Resolves the bookmark, opens its security scope (once per process, never closed),
    /// re-creates the bookmark when it is stale, and checks the game folder is there.
    public static func open(paths: LauncherPaths) -> State {
        guard let reference = GameFolderStore.loadOrAdoptDocumentsFolder(paths: paths) else { return .none }
        var stale = false
        let picked: URL
        do {
            picked = try URL(resolvingBookmarkData: reference.bookmark, options: [], relativeTo: nil,
                             bookmarkDataIsStale: &stale)
        } catch {
            return .unavailable(name: reference.name, reason: error.localizedDescription)
        }
        startAccessing(picked)
        if stale, let fresh = try? picked.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            var updated = reference
            updated.bookmark = fresh
            try? GameFolderStore.save(updated, paths: paths)
        }
        let gameFolder = reference.subpath.isEmpty
            ? picked : picked.appendingPathComponent(reference.subpath, isDirectory: true)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: gameFolder.path, isDirectory: &isDir), isDir.boolValue else {
            return .unavailable(name: reference.name, reason: "folder not found")
        }
        return .open(gameFolder: gameFolder, picked: picked)
    }

    /// startAccessingSecurityScopedResource(), at most once per URL per process, never stopped.
    /// Returns whether the URL is (now) in a security scope -- false for ordinary sandbox paths.
    @discardableResult
    public static func startAccessing(_ url: URL) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if opened.contains(url.path) { return true }
        let started = url.startAccessingSecurityScopedResource()
        if started { opened.insert(url.path) }
        return started
    }
}

// MARK: - iCloud Drive

/// Finding game archives that iCloud Drive has not downloaded yet. Reading such a file blocks
/// until it arrives (or fails), which the engine must never meet, so Play waits for them.
public enum UbiquitousFiles {
    /// The .big archives in `folder` and its immediate subfolders that are not downloaded:
    /// dataless files reported by ubiquitousItemDownloadingStatus, and old-style ".Name.big.icloud"
    /// placeholders (returned under their real name).
    public static func pendingArchives(in folder: URL) -> [URL] {
        var pending: [URL] = []
        var roots = [folder]
        let fm = FileManager.default
        if let subs = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: []) {
            roots += subs.filter { !$0.lastPathComponent.hasPrefix(".")
                && (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        }
        let keys: Set<URLResourceKey> = [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]
        for root in roots {
            let items = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: Array(keys), options: [])) ?? []
            for item in items {
                let name = item.lastPathComponent
                if let real = placeholderTarget(name), real.lowercased().hasSuffix(".big") {
                    pending.append(root.appendingPathComponent(real))
                    continue
                }
                guard item.pathExtension.lowercased() == "big",
                      let values = try? item.resourceValues(forKeys: keys),
                      values.isUbiquitousItem == true else { continue }
                if let status = values.ubiquitousItemDownloadingStatus, status != .current {
                    pending.append(item)
                }
            }
        }
        return pending.sorted { $0.path < $1.path }
    }

    /// "INIZH.big" for ".INIZH.big.icloud".
    public static func placeholderTarget(_ name: String) -> String? {
        guard name.hasPrefix("."), name.hasSuffix(".icloud"), name.count > ".x.icloud".count - 1 else { return nil }
        return String(name.dropFirst().dropLast(".icloud".count))
    }

    /// Asks iCloud Drive to download them. Errors are returned per file, not thrown.
    @discardableResult
    public static func startDownloading(_ files: [URL]) -> [URL: Error] {
        var errors: [URL: Error] = [:]
        for file in files {
            do {
                try FileManager.default.startDownloadingUbiquitousItem(at: file)
            } catch {
                errors[file] = error
            }
        }
        return errors
    }
}

// MARK: - Where the folder is

public enum FolderLocation: Equatable, Sendable {
    /// Inside this app's Documents ("On My iPhone" > the app's folder).
    case appDocuments
    /// iCloud Drive.
    case iCloudDrive
    /// "On My iPhone" outside this app.
    case onDevice
    /// A USB drive / external volume.
    case externalDrive(String)
    /// Anything else (another app's file provider, ...).
    case other

    /// Classifies `url` from its path and resource values. Heuristic: iOS does not expose a
    /// public "which file provider" API for a plain URL.
    public static func of(_ url: URL, paths: LauncherPaths) -> FolderLocation {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        let docs = paths.documents.standardizedFileURL.resolvingSymlinksInPath().path
        if path == docs || path.hasPrefix(docs + "/") { return .appDocuments }
        if (try? url.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem) == true
            || path.contains("/Mobile Documents/") {
            return .iCloudDrive
        }
        if let range = path.range(of: "/LiveFiles/") {
            // .../LiveFiles/com.apple.filesystems.userfsd/<Volume>/...
            let rest = path[range.upperBound...].split(separator: "/")
            return .externalDrive(rest.count > 1 ? String(rest[1]) : "")
        }
        if path.contains("/File Provider Storage") || path.contains("FileProvider.LocalStorage") {
            return .onDevice
        }
        return .other
    }
}
