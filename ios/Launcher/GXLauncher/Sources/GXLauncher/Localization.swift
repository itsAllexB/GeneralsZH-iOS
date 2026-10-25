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

// GeneralsX @feature iOS launcher 25/10/2026 String lookup for the launcher.
//
// Every user-facing string goes through L("English text"): the English text is the key in
// Resources/Localizable.xcstrings, so a missing translation -- or a missing resource bundle when
// the engine links the static library without copying GXLauncher_GXLauncher.bundle -- still shows
// proper English instead of a key. Format strings use String(format:) with %d / %@.

#if canImport(UIKit) && os(iOS)
import Foundation

private final class GXLauncherBundleMarker {}

extension Bundle {
    /// The package's resource bundle, wherever the host put it; the main bundle as a fallback.
    static let gxLauncher: Bundle = {
        let name = "GXLauncher_GXLauncher.bundle"
        let candidates: [URL?] = [
            Bundle.main.resourceURL,
            Bundle(for: GXLauncherBundleMarker.self).resourceURL,
            Bundle.main.bundleURL,
            Bundle.main.privateFrameworksURL,
        ]
        for case let base? in candidates {
            if let bundle = Bundle(url: base.appendingPathComponent(name)) {
                return bundle
            }
        }
        return .main
    }()
}

/// The localized string for an English key.
func L(_ key: String) -> String {
    NSLocalizedString(key, tableName: "Localizable", bundle: .gxLauncher, value: key, comment: "")
}

/// L() with String(format:) arguments.
func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: L(key), arguments: args)
}
#endif
