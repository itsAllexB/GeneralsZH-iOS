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

// GeneralsX @feature iOS launcher 25/10/2026 A reader for the directory table of a .big archive,
// ported from the Android launcher (SetupActivity.hasBigFHeader / bigArchiveHasEntry /
// forEachBigEntry), which in turn follows the engine's own parser (StdBIGFileSystem.cpp,
// openArchiveFile()):
//
//   offset 0    "BIGF"
//   offset 4    archive size, little-endian (not needed)
//   offset 8    file count, BIG-endian
//   offset 12   offset of the first file's data, big-endian (not needed)
//   offset 16   one record per file: data offset (BE u32), data size (BE u32),
//               NUL-terminated backslash-separated path
//
// Only the table is read -- a few kilobytes however large the archive is -- so checking every
// archive of a 2.7 GB install takes milliseconds.

import Foundation

public enum BigArchive {
    /// The archive magic.
    public static let magic: [UInt8] = Array("BIGF".utf8)
    /// Sanity cap on the file count, as Android's bigArchiveHasEntry().
    public static let maxEntries = 500_000
    /// Longest path kept per entry; longer names are truncated like Android's 512-byte buffer.
    static let maxNameLength = 511

    public enum ReadError: Error, Equatable {
        case unreadable
        case badHeader
        case implausibleCount(Int)
        case truncated(afterEntries: Int)
    }

    /// True when the file starts with "BIGF".
    public static func hasBigFHeader(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 4) else { return false }
        return Array(data) == magic
    }

    /// Calls `visit` with every entry path, lowercased with '\' turned into '/', the form every
    /// caller compares against (Android's forEachBigEntry). Return false from `visit` to stop.
    /// Throws when the table cannot be walked to the end (bad header, truncated table).
    public static func forEachEntry(in url: URL, _ visit: (String) -> Bool) throws {
        guard let handle = try? FileHandle(forReadingFrom: url) else { throw ReadError.unreadable }
        defer { try? handle.close() }
        var reader = BufferedReader(handle: handle)

        guard let header = reader.read(16), header.count == 16 else { throw ReadError.badHeader }
        guard Array(header[0..<4]) == magic else { throw ReadError.badHeader }
        let count = Int(bigEndianUInt32(header, at: 8))
        guard count >= 0, count <= maxEntries else { throw ReadError.implausibleCount(count) }

        var name = [UInt8]()
        name.reserveCapacity(64)
        for index in 0..<count {
            guard let record = reader.read(8), record.count == 8 else {
                throw ReadError.truncated(afterEntries: index)
            }
            name.removeAll(keepingCapacity: true)
            while true {
                guard let byte = reader.readByte() else { throw ReadError.truncated(afterEntries: index) }
                if byte == 0 { break }
                if name.count < maxNameLength {
                    name.append(byte == UInt8(ascii: "\\") ? UInt8(ascii: "/") : byte)
                }
            }
            let path = String(decoding: name, as: UTF8.self).lowercased()
            if !visit(path) { return }
        }
    }

    /// Every entry path (normalised as in `forEachEntry`).
    public static func entries(in url: URL) throws -> [String] {
        var result: [String] = []
        try forEachEntry(in: url) { result.append($0); return true }
        return result
    }

    /// Whether the archive's table lists `path` (any case, '\' or '/'). False for an unreadable,
    /// malformed or truncated archive -- as Android, a truncated table does not answer "yes".
    public static func contains(_ path: String, in url: URL) -> Bool {
        let wanted = normalise(path)
        var hit = false
        do {
            try forEachEntry(in: url) { entry in
                if entry == wanted { hit = true; return false }
                return true
            }
        } catch {
            return false
        }
        return hit
    }

    /// Lowercase, forward slashes.
    public static func normalise(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/").lowercased()
    }

    static func bigEndianUInt32(_ bytes: Data, at offset: Int) -> UInt32 {
        let start = bytes.startIndex + offset
        return bytes[start..<start + 4].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }
}

/// A minimal buffered reader: the table is read byte by byte, so read the file in 64 KB chunks.
struct BufferedReader {
    let handle: FileHandle
    var buffer = Data()
    var position = 0
    var eof = false

    init(handle: FileHandle) { self.handle = handle }

    mutating func fill() -> Bool {
        if position < buffer.count { return true }
        if eof { return false }
        guard let chunk = try? handle.read(upToCount: 1 << 16), !chunk.isEmpty else {
            eof = true
            return false
        }
        buffer = chunk
        position = 0
        return true
    }

    mutating func readByte() -> UInt8? {
        guard fill() else { return nil }
        let byte = buffer[buffer.startIndex + position]
        position += 1
        return byte
    }

    /// Up to `count` bytes; fewer only at end of file.
    mutating func read(_ count: Int) -> Data? {
        var out = Data()
        out.reserveCapacity(count)
        while out.count < count {
            guard fill() else { break }
            let take = min(count - out.count, buffer.count - position)
            let start = buffer.startIndex + position
            out.append(buffer[start..<start + take])
            position += take
        }
        return out.isEmpty && count > 0 ? nil : out
    }
}
