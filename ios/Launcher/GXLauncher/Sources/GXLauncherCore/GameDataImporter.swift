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

// GeneralsX @feature iOS launcher 25/10/2026 Copies a game folder the player picked (Files app,
// external drive, iCloud Drive...) into Library/Application Support/GeneralsX/ImportedGameData.
//
//   - Copies into ImportedGameData.partial and only swaps it in when the copy completed, so an
//     interrupted or cancelled import never leaves a half-copied folder the engine would load.
//   - Byte-level progress (files are copied in 4 MB chunks, the big archives are hundreds of MB).
//   - Checks free space first; marks the result excluded from iCloud/iTunes backup (it is
//     re-importable and gigabytes large).
//   - Validates the result with GameDataValidator and returns the report; an import that is not a
//     game folder at all is rejected and removed.
//   - Fills in the port's runtime files a retail folder lacks (DefaultOptions.ini, dxvk.conf,
//     fonts/) from the bundled GameData when missing, like Android's copyBundledRuntimeIfMissing().
//
// Hidden files and macOS metadata (._*, .DS_Store) are skipped.

import Foundation

public struct ImportProgress: Sendable, Equatable {
    public var copiedBytes: Int64
    public var totalBytes: Int64
    public var currentFile: String
    public init(copiedBytes: Int64, totalBytes: Int64, currentFile: String) {
        self.copiedBytes = copiedBytes
        self.totalBytes = totalBytes
        self.currentFile = currentFile
    }

    public var fraction: Double { totalBytes > 0 ? min(1, Double(copiedBytes) / Double(totalBytes)) : 0 }
}

public enum ImportError: Error, Equatable, Sendable {
    case sourceUnreadable
    case notEnoughSpace(needed: Int64, available: Int64)
    case notAGameFolder
    case cancelled
    case copyFailed(String)
}

public enum GameDataImporter {
    static let chunkSize = 4 << 20
    /// Port runtime files copied from the bundled GameData when the import lacks them.
    public static let runtimeFiles = ["DefaultOptions.ini", "dxvk.conf", "fonts"]

    /// Copies `source` and returns the validation report of the imported copy.
    /// `progress` is called from the copying thread. Checks `Task.isCancelled` between chunks.
    public static func importFolder(from source: URL, paths: LauncherPaths,
                                    progress: @Sendable (ImportProgress) -> Void) throws -> GameDataReport {
        let fm = FileManager.default
        let files = try enumerateFiles(in: source)
        let total = files.reduce(Int64(0)) { $0 + $1.size }

        // Refuse up front rather than fill the device and fail at 90 %.
        try fm.createDirectory(at: paths.generalsXSupport, withIntermediateDirectories: true)
        if let available = availableCapacity(at: paths.generalsXSupport) {
            let needed = total + (64 << 20)
            if available < needed {
                throw ImportError.notEnoughSpace(needed: total, available: available)
            }
        }

        let staging = paths.importStaging
        try? fm.removeItem(at: staging)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)

        var copied: Int64 = 0
        do {
            for file in files {
                let destination = staging.appendingPathComponent(file.relativePath, isDirectory: false)
                try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try copyFile(file.url, to: destination) { bytes in
                    copied += Int64(bytes)
                    progress(ImportProgress(copiedBytes: copied, totalBytes: total, currentFile: file.relativePath))
                }
            }
        } catch {
            try? fm.removeItem(at: staging)
            throw error
        }

        // A picked folder that is not a game folder is not worth keeping.
        let check = GameDataValidator.validate(staging)
        if check.issues.contains(.notAGameFolder) || check.issues.contains(.folderMissing) {
            try? fm.removeItem(at: staging)
            throw ImportError.notAGameFolder
        }

        copyRuntimeFilesIfMissing(from: paths.bundledGameData, to: staging)

        // Swap in the finished copy.
        if fm.fileExists(atPath: paths.importedGameData.path) {
            try fm.removeItem(at: paths.importedGameData)
        }
        try fm.moveItem(at: staging, to: paths.importedGameData)
        excludeFromBackup(paths.importedGameData)
        return GameDataValidator.validate(paths.importedGameData)
    }

    /// Deletes the imported copy (and any leftover staging folder).
    public static func removeImported(paths: LauncherPaths) throws {
        let fm = FileManager.default
        try? fm.removeItem(at: paths.importStaging)
        if fm.fileExists(atPath: paths.importedGameData.path) {
            try fm.removeItem(at: paths.importedGameData)
        }
    }

    // MARK: - Helpers

    struct SourceFile {
        let url: URL
        let relativePath: String
        let size: Int64
    }

    static func enumerateFiles(in source: URL) throws -> [SourceFile] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .isHiddenKey]
        guard let enumerator = FileManager.default.enumerator(
            at: source, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
            throw ImportError.sourceUnreadable
        }
        let basePath = source.standardizedFileURL.resolvingSymlinksInPath().path
        var files: [SourceFile] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true else { continue }
            let name = url.lastPathComponent
            if name.hasPrefix("._") || name == ".DS_Store" { continue }
            let full = url.standardizedFileURL.resolvingSymlinksInPath().path
            var relative = full.hasPrefix(basePath) ? String(full.dropFirst(basePath.count)) : name
            while relative.hasPrefix("/") { relative.removeFirst() }
            files.append(SourceFile(url: url, relativePath: relative, size: Int64(values?.fileSize ?? 0)))
        }
        if files.isEmpty { throw ImportError.notAGameFolder }
        return files
    }

    static func copyFile(_ source: URL, to destination: URL, onChunk: (Int) -> Void) throws {
        guard let input = try? FileHandle(forReadingFrom: source) else {
            throw ImportError.copyFailed(source.lastPathComponent)
        }
        defer { try? input.close() }
        guard FileManager.default.createFile(atPath: destination.path, contents: nil),
              let output = try? FileHandle(forWritingTo: destination) else {
            throw ImportError.copyFailed(destination.lastPathComponent)
        }
        defer { try? output.close() }
        while true {
            if Task.isCancelled { throw ImportError.cancelled }
            let chunk: Data
            do {
                chunk = try autoreleasepool { try input.read(upToCount: chunkSize) ?? Data() }
            } catch {
                throw ImportError.copyFailed(source.lastPathComponent)
            }
            if chunk.isEmpty { break }
            do {
                try output.write(contentsOf: chunk)
            } catch {
                throw ImportError.copyFailed(source.lastPathComponent)
            }
            onChunk(chunk.count)
        }
    }

    static func copyRuntimeFilesIfMissing(from bundled: URL, to target: URL) {
        let fm = FileManager.default
        for name in runtimeFiles {
            let src = bundled.appendingPathComponent(name)
            let dst = target.appendingPathComponent(name)
            if fm.fileExists(atPath: src.path) && !fm.fileExists(atPath: dst.path) {
                try? fm.copyItem(at: src, to: dst)
            }
        }
    }

    static func availableCapacity(at url: URL) -> Int64? {
        #if os(iOS)
        if let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let capacity = values.volumeAvailableCapacityForImportantUsage, capacity > 0 {
            return capacity
        }
        #endif
        if let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey]),
           let capacity = values.volumeAvailableCapacity {
            return Int64(capacity)
        }
        return nil
    }

    static func excludeFromBackup(_ url: URL) {
        var target = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? target.setResourceValues(values)
    }
}

#if !canImport(ObjectiveC)
@inline(__always) func autoreleasepool<T>(_ body: () throws -> T) rethrows -> T { try body() }
#endif
