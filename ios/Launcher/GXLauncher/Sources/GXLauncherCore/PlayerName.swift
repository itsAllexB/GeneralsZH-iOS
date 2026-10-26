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

// GeneralsX @feature iOS launcher 26/10/2026 "Player Name" (Home > Options): the name the game shows
// for the player in skirmish and LAN games.
//
// The game keeps it as `UserName` in two files of its user-data folder, next to Options.ini:
// Skirmish.ini (SkirmishPreferences, slot 0's name) and Network.ini (LANPreferences, the LAN
// lobby). Both use the UserPreferences "Key = value" format, and the value is the game's
// quoted-printable form of the UTF-16 name (QuotedPrintable.cpp, UnicodeStringToQuotedPrintable):
// for every UTF-16 code unit the low byte, then the high byte; a byte that is ASCII [0-9A-Za-z] is
// written as that character, any other byte as '_' and two uppercase hex digits. "Al" ->
// "A_00l_00". Without a name the game falls back to the device's host name.
//
// The game writes these files itself too (the LAN lobby saves the name typed there, skirmish saves
// slot 0's), so the launcher reads the current value every time it appears and never caches it.

import Foundation

/// The game's quoted-printable encoding of UTF-16 strings.
public enum QuotedPrintable {
    /// UnicodeStringToQuotedPrintable().
    public static func encode(_ string: String) -> String {
        var out = ""
        for unit in string.utf16 {
            for byte in [UInt8(unit & 0xFF), UInt8(unit >> 8)] {
                if isAsciiAlphaNumeric(byte) {
                    out.unicodeScalars.append(Unicode.Scalar(byte))
                } else {
                    out += "_" + String(format: "%02X", byte)
                }
            }
        }
        return out
    }

    /// QuotedPrintableToUnicodeString(): "_HH" is a byte, anything else a literal byte, byte pairs
    /// are little-endian UTF-16 code units. Stops, like the engine, at a malformed escape or a
    /// trailing odd byte; invalid UTF-16 is repaired rather than rejected.
    public static func decode(_ encoded: String) -> String {
        let bytes = Array(encoded.utf8)
        var units: [UInt16] = []
        var index = 0
        func nextByte() -> UInt8? {
            guard index < bytes.count else { return nil }
            if bytes[index] == UInt8(ascii: "_") {
                guard index + 2 < bytes.count,
                      let high = hexValue(bytes[index + 1]), let low = hexValue(bytes[index + 2]) else { return nil }
                index += 3
                return high << 4 | low
            }
            defer { index += 1 }
            return bytes[index]
        }
        while index < bytes.count {
            guard let low = nextByte(), let high = nextByte() else { break }
            units.append(UInt16(low) | UInt16(high) << 8)
        }
        return String(decoding: units, as: UTF16.self)
    }

    static func isAsciiAlphaNumeric(_ byte: UInt8) -> Bool {
        (byte >= 0x30 && byte <= 0x39) || (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A)
    }

    static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 0x30...0x39: return byte - 0x30
        case 0x41...0x46: return byte - 0x41 + 10
        case 0x61...0x66: return byte - 0x61 + 10
        default: return nil
        }
    }
}

public enum PlayerName {
    /// The game's limit, g_lanPlayerNameLength (LANAPI.h), in UTF-16 code units.
    public static let maxLength = 12
    public static let key = "UserName"
    /// Punctuation allowed besides letters, digits and spaces.
    public static let punctuation = Set(".,-_'!?()[]{}&+#@:;/*~^$%=<>|")

    /// Letters (any script, with their combining marks), digits, the space and common punctuation,
    /// all inside the Basic Multilingual Plane (one UTF-16 unit each, like the game's WideChar text).
    public static func isAllowed(_ character: Character) -> Bool {
        if character == " " || punctuation.contains(character) { return true }
        return character.unicodeScalars.allSatisfy { scalar in
            scalar.value <= 0xFFFF
                && (CharacterSet.letters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar))
        }
    }

    /// What the text field keeps while typing: allowed characters only, at most `maxLength` UTF-16
    /// units (whole characters only), no trimming yet.
    public static func filterTyping(_ text: String) -> String {
        var out = ""
        for character in text where isAllowed(character) {
            if out.utf16.count + String(character).utf16.count > maxLength { break }
            out.append(character)
        }
        return out
    }

    /// The name to store: filtered, capped and trimmed; "" means "no name, keep the game's own".
    public static func sanitize(_ text: String) -> String {
        filterTyping(text.trimmingCharacters(in: .whitespacesAndNewlines))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The current name: Skirmish.ini's, else Network.ini's, decoded and trimmed; "" when neither has one.
    public static func read(paths: LauncherPaths) -> String {
        for file in [paths.skirmishIni, paths.networkIni] {
            let doc = OptionsIniStore(file: file, defaults: nil).load()
            if let raw = doc.value(for: key) {
                let name = QuotedPrintable.decode(raw).trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { return name }
            }
        }
        return ""
    }

    /// Writes `UserName = <encoded>` into Skirmish.ini and Network.ini (created when missing, every
    /// other line kept, an existing UserName replaced). An empty name writes nothing.
    /// Returns whether anything was written.
    @discardableResult
    public static func write(_ text: String, paths: LauncherPaths) throws -> Bool {
        let name = sanitize(text)
        guard !name.isEmpty else { return false }
        let encoded = QuotedPrintable.encode(name)
        for file in [paths.skirmishIni, paths.networkIni] {
            try OptionsIniStore(file: file, defaults: nil).update { $0.set(key, encoded) }
        }
        return true
    }
}
