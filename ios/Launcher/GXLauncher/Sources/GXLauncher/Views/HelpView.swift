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

// GeneralsX @feature iOS launcher 25/10/2026 Help: version, how to play (placeholder), the license
// notices the GPL-3.0 and EA's additional terms (LICENSE.md, section 7) require, the source code
// link and credits.

#if canImport(UIKit) && os(iOS)
import SwiftUI

struct HelpView: View {
    static let sourceURL = URL(string: "https://github.com/itsAllexB/GeneralsZH-iOS")!
    static let gplURL = URL(string: "https://www.gnu.org/licenses/gpl-3.0.html")!

    var body: some View {
        Form {
            Section {
                LabeledContent(L("App"), value: LauncherInfo.appName)
                LabeledContent(L("Version"), value: LauncherInfo.version)
                Text(L("This is a modified version of the Command & Conquer Generals: Zero Hour source code that Electronic Arts released under the GNU GPL v3. It is not the original program, and it is not made, endorsed or supported by Electronic Arts."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text(L("About"))
            }

            Section {
                // TODO(gestures): replace with the final iOS gesture list once the touch layer settles.
                ForEach(Self.howToPlay, id: \.self) { line in
                    Label(line, systemImage: "hand.tap")
                }
            } header: {
                Text(L("How to play"))
            } footer: {
                Text(L("The game data (the .big archives) comes from your own copy of the game."))
            }

            Section {
                Text(L("This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE."))
                    .font(.footnote)
                Text(L("Additional terms (GPL section 7): no trademark or publicity rights are granted. This license does not give you any right, title or interest in \"Command & Conquer\" or any other Electronic Arts trademark, and this program claims no affiliation with Electronic Arts Inc. Modified versions must be marked as such and not identified as the original program. The program is provided \"as is\", with all faults and without warranty of any kind; your use is at your sole risk."))
                    .font(.footnote)
                Link(destination: Self.gplURL) {
                    Label(L("GNU General Public License v3"), systemImage: "doc.plaintext")
                }
            } header: {
                Text(L("License"))
            }

            Section {
                Link(destination: Self.sourceURL) {
                    Label(Self.sourceURL.absoluteString, systemImage: "chevron.left.forwardslash.chevron.right")
                }
            } header: {
                Text(L("Source code"))
            } footer: {
                Text(L("The complete corresponding source code of this app is available at the address above."))
            }

            Section {
                Text(L("Electronic Arts (GPL source release) · TheSuperHackers · Fighter19 · fbraz3/GeneralsX · ammaarreshi · MYSOREZ (Android port) · realkot"))
                    .font(.footnote)
            } header: {
                Text(L("Credits"))
            }
        }
        .navigationTitle(L("Help"))
    }

    static var howToPlay: [String] {
        [
            L("TODO: Tap to select a unit or building"),
            L("TODO: Drag to draw a selection box"),
            L("TODO: Two fingers to scroll the map, pinch to zoom"),
            L("TODO: Long-press for the context action"),
        ]
    }
}
#endif
