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

// GeneralsX @feature iOS launcher 25/10/2026 Reading the engine's stderr mirror for the log viewer.
//
// Same budget as Android's LogViewerActivity: at most 200,000 characters per file are shown, the
// first 60,000 (startup banner, INI loading, device/GPU info) and the last 140,000 (where a hang
// or a crash shows up), with a marker line saying how much was left out. Sharing always hands
// over the whole file, which nothing truncates.

import Foundation

public enum LogFile: String, CaseIterable, Identifiable, Sendable {
    case current
    case previous

    public var id: String { rawValue }

    public func url(in paths: LauncherPaths) -> URL {
        switch self {
        case .current: return paths.currentLog
        case .previous: return paths.previousLog
        }
    }
}

public struct LogExcerpt: Equatable, Sendable {
    public var text: String
    /// File size in bytes; nil when the file does not exist.
    public var fileSize: Int64?
    /// Bytes left out of the middle; 0 when the whole file is shown.
    public var elidedBytes: Int64
    public var modified: Date?

    public init(text: String, fileSize: Int64?, elidedBytes: Int64, modified: Date?) {
        self.text = text
        self.fileSize = fileSize
        self.elidedBytes = elidedBytes
        self.modified = modified
    }
}

public enum LogReader {
    public static let maxBytes = 200_000
    public static let headBytes = 60_000

    public static func read(_ url: URL) -> LogExcerpt {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = (attributes?[.size] as? NSNumber)?.int64Value,
              let handle = try? FileHandle(forReadingFrom: url) else {
            return LogExcerpt(text: "", fileSize: nil, elidedBytes: 0, modified: nil)
        }
        defer { try? handle.close() }
        let modified = attributes?[.modificationDate] as? Date
        if size <= Int64(maxBytes) {
            let data = (try? handle.readToEnd()) ?? Data()
            return LogExcerpt(text: decode(data), fileSize: size, elidedBytes: 0, modified: modified)
        }
        let head = (try? handle.read(upToCount: headBytes)) ?? Data()
        let tailBytes = maxBytes - headBytes
        try? handle.seek(toOffset: UInt64(size) - UInt64(tailBytes))
        let tail = (try? handle.readToEnd()) ?? Data()
        let elided = size - Int64(head.count) - Int64(tail.count)
        let marker = "\n\n[... \(elided) bytes omitted; Share sends the whole file ...]\n\n"
        return LogExcerpt(text: decode(head) + marker + decode(tail), fileSize: size, elidedBytes: elided, modified: modified)
    }

    /// The lines containing `query` (case-insensitive), each prefixed with its 1-based line number.
    public static func filter(_ text: String, query: String) -> (text: String, matches: Int) {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return (text, 0) }
        var out: [String] = []
        var number = 0
        text.enumerateLines { line, _ in
            number += 1
            if line.range(of: needle, options: [.caseInsensitive]) != nil {
                out.append(String(format: "%6d  ", number) + line)
            }
        }
        return (out.joined(separator: "\n"), out.count)
    }

    /// Lossy UTF-8: a chunk boundary may split a multi-byte character; never fail on it.
    static func decode(_ data: Data) -> String {
        String(decoding: data, as: UTF8.self)
    }

    /// Empties both logs (the viewer's Clear button).
    public static func clear(paths: LauncherPaths) {
        for file in LogFile.allCases {
            try? FileManager.default.removeItem(at: file.url(in: paths))
        }
    }
}
