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

// GeneralsX @feature iOS launcher 25/10/2026 The port's support files (<App>.app/GameSupport:
// fonts/*.ttf, Window/*.wnd, dxvk.conf, DefaultOptions.ini) go INTO the game folder, because the
// engine looks for them relative to its working directory -- Android does the same
// (copyBundledRuntimeIfMissing / syncEngineWindowOverrides).
//
// Rules:
//   - every regular file below GameSupport is mirrored to the same relative path in the game folder,
//     creating subfolders as needed;
//   - a file is written only when it is missing or different (size first, then contents), so
//     repeated launches cost a directory walk and a few compares;
//   - nothing in the game folder is ever deleted;
//   - failures are collected, not thrown: a read-only folder (or one the scope does not allow
//     writing to) leaves `complete == false`, and the launcher then points the engine at the bundle
//     instead (GENERALSX_BUNDLED_FONTS_DIR, DXVK_CONFIG_FILE). Window overrides cannot be redirected
//     that way, so the player is told.

import Foundation

public struct SupportSyncResult: Equatable, Sendable {
    /// Relative paths written (missing or different).
    public var written: [String] = []
    /// Relative paths already identical.
    public var unchanged: Int = 0
    /// Relative paths that could not be written.
    public var failed: [String] = []
    /// False when the bundle has no GameSupport folder at all.
    public var hadSupport: Bool = true

    public var complete: Bool { failed.isEmpty }
}

public enum SupportFileSync {
    /// Mirrors `support` into `gameFolder` (see the rules above).
    public static func sync(from support: URL, to gameFolder: URL) -> SupportSyncResult {
        var result = SupportSyncResult()
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: support.path, isDirectory: &isDir), isDir.boolValue else {
            result.hadSupport = false
            return result
        }
        for relative in files(below: support) {
            let source = support.appendingPathComponent(relative)
            let destination = gameFolder.appendingPathComponent(relative)
            if filesEqual(source, destination) {
                result.unchanged += 1
                continue
            }
            do {
                try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                let data = try Data(contentsOf: source)
                try data.write(to: destination, options: .atomic)
                result.written.append(relative)
            } catch {
                result.failed.append(relative)
            }
        }
        return result
    }

    /// Relative paths of every regular, non-hidden file below `root`, sorted.
    static func files(below root: URL) -> [String] {
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return [] }
        let base = root.standardizedFileURL.resolvingSymlinksInPath().pathComponents.count
        var out: [String] = []
        for case let url as URL in enumerator
        where (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
            let parts = url.standardizedFileURL.resolvingSymlinksInPath().pathComponents
            out.append(parts.dropFirst(base).joined(separator: "/"))
        }
        return out.sorted()
    }

    /// Same size and same bytes (compared in 1 MB chunks).
    static func filesEqual(_ a: URL, _ b: URL) -> Bool {
        let fm = FileManager.default
        guard let sa = (try? fm.attributesOfItem(atPath: a.path))?[.size] as? NSNumber,
              let sb = (try? fm.attributesOfItem(atPath: b.path))?[.size] as? NSNumber,
              sa == sb,
              let ha = try? FileHandle(forReadingFrom: a),
              let hb = try? FileHandle(forReadingFrom: b) else { return false }
        defer { try? ha.close(); try? hb.close() }
        while true {
            let ca = (try? ha.read(upToCount: 1 << 20)) ?? Data()
            let cb = (try? hb.read(upToCount: 1 << 20)) ?? Data()
            if ca != cb { return false }
            if ca.isEmpty { return true }
        }
    }
}
