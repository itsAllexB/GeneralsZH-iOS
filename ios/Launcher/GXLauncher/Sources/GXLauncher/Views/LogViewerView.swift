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

// GeneralsX @feature iOS launcher 25/10/2026 The log viewer (LogViewerActivity on Android):
// Documents/generals-stderr.log (this session's log -- the last game run, since the launcher runs
// before the engine rotates it) and generals-stderr-prev.log (the run before). Monospaced,
// selectable, searchable (matching lines with their line numbers), shareable as the whole file.

#if canImport(UIKit) && os(iOS)
import SwiftUI
import UIKit
import GXLauncherCore

struct LogViewerView: View {
    let paths: LauncherPaths
    @State private var file: LogFile = .current
    @State private var excerpt = LogExcerpt(text: "", fileSize: nil, elidedBytes: 0, modified: nil)
    @State private var query = ""
    @State private var confirmClear = false

    private var shown: (text: String, matches: Int) {
        LogReader.filter(excerpt.text, query: query)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker(L("Log"), selection: $file) {
                Text(L("Last session")).tag(LogFile.current)
                Text(L("Previous session")).tag(LogFile.previous)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            infoLine
                .padding(.horizontal)
                .padding(.bottom, 6)

            if excerpt.fileSize == nil {
                emptyState
            } else {
                let result = shown
                MonospacedTextView(text: query.isEmpty ? result.text
                                   : (result.matches == 0 ? L("No matching lines.") : result.text))
                    .background(Color(uiColor: .secondarySystemBackground))
            }
        }
        .navigationTitle(L("Logs"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: Text(L("Search log")))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if excerpt.fileSize != nil {
                    ShareLink(item: file.url(in: paths)) {
                        Label(L("Share"), systemImage: "square.and.arrow.up")
                    }
                }
                Menu {
                    Button {
                        reload()
                    } label: {
                        Label(L("Reload"), systemImage: "arrow.clockwise")
                    }
                    Button(role: .destructive) {
                        confirmClear = true
                    } label: {
                        Label(L("Clear logs"), systemImage: "trash")
                    }
                } label: {
                    Label(L("More"), systemImage: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog(L("Clear both logs?"), isPresented: $confirmClear, titleVisibility: .visible) {
            Button(L("Clear logs"), role: .destructive) {
                LogReader.clear(paths: paths)
                reload()
            }
        }
        .onAppear(perform: reload)
        .onChange(of: file) { _ in reload() }
    }

    private var infoLine: some View {
        HStack {
            if let size = excerpt.fileSize {
                Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                if let modified = excerpt.modified {
                    Text("·")
                    Text(modified, style: .relative) + Text(" ") + Text(L("ago"))
                }
                if excerpt.elidedBytes > 0 {
                    Text("·")
                    Text(L("middle shortened"))
                }
            }
            Spacer()
            if !query.isEmpty {
                Text(L("%d matching lines", shown.matches))
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "doc.text")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(L("No log yet")).font(.headline)
            Text(L("The game writes its log while it runs. Play once, then come back here."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func reload() {
        let url = file.url(in: paths)
        Task.detached(priority: .userInitiated) {
            let read = LogReader.read(url)
            await MainActor.run { excerpt = read }
        }
    }
}

/// A read-only, selectable UITextView: far cheaper than SwiftUI Text for ~200 KB of log.
struct MonospacedTextView: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.alwaysBounceVertical = true
        view.backgroundColor = .clear
        view.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        view.font = UIFontMetrics(forTextStyle: .caption1)
            .scaledFont(for: .monospacedSystemFont(ofSize: 12, weight: .regular))
        view.adjustsFontForContentSizeCategory = true
        view.textColor = .label
        view.accessibilityIdentifier = "gx.log.text"
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        if view.text != text {
            view.text = text
        }
    }
}
#endif
