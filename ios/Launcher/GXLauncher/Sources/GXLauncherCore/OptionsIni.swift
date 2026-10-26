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

// GeneralsX @feature iOS launcher 25/10/2026 Options.ini, edited in place.
//
// The engine reads and writes Options.ini as "key = value" lines (UserPreferences::load()/write():
// the key is everything before the first '=', both sides trimmed, lines with an empty key or
// value skipped, a later duplicate wins). The Android launcher (SetupActivity.readKeyValueFile/
// writeKeyValueFile) re-wrote the whole file from a map in that same format. This editor goes one
// step further and is line-preserving: it changes only the value on the line(s) carrying the key,
// appends "key = value" when the key is new, and leaves every other byte alone -- comments, blank
// lines, odd spacing, the line-ending style and the final newline (or lack of one).
//
// Like Android (writeUiScalePercent): when Options.ini does not exist yet it is seeded from the
// game data's DefaultOptions.ini first, because the engine only seeds it itself when the file is
// missing, and a bare file holding one launcher key would permanently skip those defaults.

import Foundation

public struct OptionsIniDocument: Equatable, Sendable {
    /// The file's lines without their terminators.
    public private(set) var lines: [String]
    /// "\r\n" when the file used CRLF, "\n" otherwise.
    public let lineEnding: String
    /// Whether the last line was terminated.
    public private(set) var endsWithNewline: Bool

    public init(text: String) {
        lineEnding = text.contains("\r\n") ? "\r\n" : "\n"
        endsWithNewline = text.last?.isNewline ?? false
        // Character.isNewline treats "\r\n" as one character, so mixed files split cleanly too.
        var parts = text.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline }).map(String.init)
        if endsWithNewline { parts.removeLast() }
        lines = text.isEmpty ? [] : parts
        if lines.isEmpty {
            endsWithNewline = true  // new content gets a terminated last line
        }
    }

    /// Splits a line the way UserPreferences::load() does. nil when the engine would skip it.
    static func parse(_ line: String) -> (key: String, value: String)? {
        guard let eq = line.firstIndex(of: "=") else { return nil }
        let key = line[..<eq].trimmingCharacters(in: .whitespacesAndNewlines)
        let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !value.isEmpty else { return nil }
        return (key, value)
    }

    /// The value the engine would see for `key` (the last occurrence wins, as in the engine's map).
    public func value(for key: String) -> String? {
        var result: String?
        for line in lines {
            if let pair = Self.parse(line), pair.key == key {
                result = pair.value
            }
        }
        return result
    }

    /// Every key/value pair the engine would load, in file order (later duplicates override).
    public var entries: [(key: String, value: String)] {
        lines.compactMap(Self.parse)
    }

    /// Sets `key` to `value`. Existing lines keep their key text and the spacing after '=';
    /// a new key is appended as "key = value", matching UserPreferences::write().
    public mutating func set(_ key: String, _ value: String) {
        var found = false
        for (index, line) in lines.enumerated() {
            guard let eq = line.firstIndex(of: "="),
                  line[..<eq].trimmingCharacters(in: .whitespaces) == key else { continue }
            let afterEq = line[line.index(after: eq)...]
            var leading = String(afterEq.prefix { $0 == " " || $0 == "\t" })
            if leading.isEmpty && afterEq.trimmingCharacters(in: .whitespaces).isEmpty {
                leading = " "  // a "key =" line with no value yet
            }
            lines[index] = String(line[...eq]) + leading + value
            found = true
        }
        if !found {
            lines.append("\(key) = \(value)")
            endsWithNewline = true
        }
    }

    /// Removes every line that carries `key`.
    public mutating func remove(_ key: String) {
        lines.removeAll { line in
            guard let eq = line.firstIndex(of: "=") else { return false }
            return line[..<eq].trimmingCharacters(in: .whitespaces) == key
        }
    }

    public var text: String {
        if lines.isEmpty { return "" }
        return lines.joined(separator: lineEnding) + (endsWithNewline ? lineEnding : "")
    }
}

/// Reads and writes the real Options.ini.
public struct OptionsIniStore: Sendable {
    public let file: URL
    /// DefaultOptions.ini of the game data in use, used to seed a new Options.ini. May be nil.
    public let defaults: URL?

    public init(file: URL, defaults: URL?) {
        self.file = file
        self.defaults = defaults
    }

    /// The current document; an empty one when the file does not exist or cannot be read.
    public func load() -> OptionsIniDocument {
        OptionsIniDocument(text: Self.readText(file)?.text ?? "")
    }

    /// Applies `edit` to the file and saves it atomically, seeding from DefaultOptions.ini when new.
    public func update(_ edit: (inout OptionsIniDocument) -> Void) throws {
        var doc: OptionsIniDocument
        var encoding = String.Encoding.utf8
        if let read = Self.readText(file) {
            doc = OptionsIniDocument(text: read.text)
            encoding = read.encoding
        } else if FileManager.default.fileExists(atPath: file.path) {
            // Exists but undecodable: refuse rather than clobber the player's settings.
            throw CocoaError(.fileReadInapplicableStringEncoding)
        } else {
            doc = OptionsIniDocument(text: defaults.flatMap(Self.readText)?.text ?? "")
        }
        edit(&doc)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        // Written back in the encoding it was read in, so untouched lines keep their bytes.
        guard let data = doc.text.data(using: encoding) ?? doc.text.data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        try data.write(to: file, options: .atomic)
    }

    static func readText(_ url: URL) -> (text: String, encoding: String.Encoding)? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        // Options.ini is ASCII in practice; Latin-1 decodes any byte sequence, so a stray
        // non-UTF-8 byte (an old Windows copy) still round-trips instead of failing.
        if let text = String(data: data, encoding: .utf8) { return (text, .utf8) }
        if let text = String(data: data, encoding: .isoLatin1) { return (text, .isoLatin1) }
        return nil
    }
}

// MARK: - The two Options.ini keys the launcher edits

/// Interface Size: GXUiScale (percent), handed to the engine as GX_UI_SCALE (GXUiScale.cpp, which
/// accepts 70...300 and shrinks the layouts below 100). Slider 70...200, step 10, default 100.
/// Android's slider starts at 100 (SetupActivity.buildInterfaceScaleSection); iOS also lets the
/// interface shrink, for the large iPad and iPhone Duo screens.
public enum InterfaceScale {
    public static let key = "GXUiScale"
    public static let range: ClosedRange<Int> = 70...200
    public static let step = 10
    public static let defaultPercent = 100

    /// Like Android's readInterfaceScalePercent(): clamped to `range`, 100 when missing or unparsable.
    public static func read(_ doc: OptionsIniDocument) -> Int {
        guard let raw = doc.value(for: key), let value = parsePercent(raw) else { return defaultPercent }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    public static func clamp(_ percent: Int) -> Int {
        let stepped = Int((Double(percent) / Double(step)).rounded()) * step
        return min(max(stepped, range.lowerBound), range.upperBound)
    }
}

/// Menu Text Size: ResolutionFontAdjustment (percent), read by OptionPreferences::
/// getResolutionFontAdjustment(). Slider 0...150, step 10 (Android: step 1), default 70; a negative saved
/// value (the in-game Options menu writes -100 when never set) means "the game's default" and
/// shows as 70 (SetupActivity.readUiScalePercent).
public enum MenuTextSize {
    public static let key = "ResolutionFontAdjustment"
    public static let range: ClosedRange<Int> = 0...150
    public static let step = 10
    public static let defaultPercent = 70

    public static func read(_ doc: OptionsIniDocument) -> Int {
        guard let raw = doc.value(for: key), let value = parsePercent(raw), value >= 0 else { return defaultPercent }
        return min(value, range.upperBound)
    }

    /// A value set from the slider: rounded to the step and clamped. (A value read from the file
    /// is shown as stored, e.g. 85 written by the in-game menu, until the player moves the slider.)
    public static func clamp(_ percent: Int) -> Int {
        let stepped = Int((Double(percent) / Double(step)).rounded()) * step
        return min(max(stepped, range.lowerBound), range.upperBound)
    }
}

/// "120" -> 120; also tolerates "70.000000" (the engine reads these keys with atof/atoi).
func parsePercent(_ raw: String) -> Int? {
    if let value = Int(raw) { return value }
    if let value = Double(raw), value.isFinite { return Int(value.rounded()) }
    return nil
}
