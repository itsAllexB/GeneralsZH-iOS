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

// GeneralsX @feature iOS launcher 25/10/2026 Home: Play, "Skip intro movies", the game data check
// and importing a game data folder (SetupActivity.buildHomeSection on Android).

#if canImport(UIKit) && os(iOS)
import SwiftUI
import GXLauncherCore

struct HomeView: View {
    @ObservedObject var model: LauncherModel
    @State private var showPicker = false
    @State private var confirmDelete = false

    var body: some View {
        Form {
            Section {
                PlayButton(model: model, compact: false)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section {
                Toggle(isOn: Binding(get: { model.preferences.skipIntro }, set: model.setSkipIntro)) {
                    SettingLabel(title: L("Skip intro movies"),
                                 detail: L("EA logos, the intro and other movies before the menu are skipped; the game goes straight to loading."))
                }
            }

            Section {
                GameDataStatusView(model: model)
                Button {
                    model.validate()
                } label: {
                    Label(L("Check again"), systemImage: "arrow.clockwise")
                }
                .disabled(model.isValidating)
            } header: {
                Text(L("Game data"))
            }

            importSection
        }
        .navigationTitle(LauncherInfo.appName)
        .sheet(isPresented: $showPicker) {
            FolderPicker { url in model.startImport(from: url) }
                .ignoresSafeArea()
        }
        .confirmationDialog(L("Delete the imported game data?"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(L("Delete imported copy"), role: .destructive) { model.removeImported() }
        } message: {
            Text(L("The bundled game data stays. You can import a folder again at any time."))
        }
    }

    @ViewBuilder
    private var importSection: some View {
        Section {
            switch model.importState {
            case .copying(let progress):
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: progress.fraction) {
                        Text(L("Copying game data…"))
                    } currentValueLabel: {
                        Text(L("%@ of %@",
                               ByteCountFormatter.string(fromByteCount: progress.copiedBytes, countStyle: .file),
                               ByteCountFormatter.string(fromByteCount: progress.totalBytes, countStyle: .file)))
                    }
                    if !progress.currentFile.isEmpty {
                        Text(progress.currentFile)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Button(L("Cancel import"), role: .cancel) { model.cancelImport() }
            case .failed(let message):
                Label {
                    Text(message)
                } icon: {
                    Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                }
                importButton(title: L("Try again…"))
            case .idle:
                if model.hasImportedData {
                    if let report = model.importedReport {
                        ReportSummary(report: report)
                    }
                    Toggle(isOn: Binding(get: { model.preferences.preferImportedData }, set: model.setPreferImportedData)) {
                        SettingLabel(title: L("Use imported game data"),
                                     detail: L("Play with the imported copy instead of the game data bundled with the app."))
                    }
                    importButton(title: L("Replace with another folder…"))
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label(L("Delete imported copy"), systemImage: "trash")
                    }
                } else {
                    importButton(title: L("Import game data folder…"))
                }
            }
        } header: {
            Text(L("Imported game data"))
        } footer: {
            Text(L("Pick the folder Zero Hour is installed in (with INIZH.big). It is copied into the app, checked, and kept out of device backups."))
        }
    }

    private func importButton(title: String) -> some View {
        Button {
            showPicker = true
        } label: {
            Label(title, systemImage: "folder.badge.plus")
        }
    }
}

/// The big Play button. Asks before starting with game data that failed the check.
struct PlayButton: View {
    @ObservedObject var model: LauncherModel
    var compact: Bool
    @State private var confirm = false

    var body: some View {
        Button {
            if model.dataNeedsConfirmation { confirm = true } else { model.play() }
        } label: {
            Label(L("Play"), systemImage: "play.fill")
                .labelStyle(.titleAndIcon)
                // Explicit: inside a Form row the symbol otherwise took the tint colour and
                // vanished into the prominent button's own tint.
                .foregroundStyle(.white)
                .font(compact ? .headline : .title2.weight(.bold))
                .frame(maxWidth: .infinity, minHeight: compact ? 32 : 52)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .accessibilityIdentifier("gx.play")
        .alert(L("Game data has problems"), isPresented: $confirm) {
            Button(L("Play anyway")) { model.play() }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(L("The game may fail to start or show missing textures. See Home > Game data for details."))
        }
    }
}

/// Status of the game data the engine will use.
struct GameDataStatusView: View {
    @ObservedObject var model: LauncherModel

    var body: some View {
        if model.isValidating && model.activeReport == nil {
            HStack(spacing: 12) {
                ProgressView()
                Text(L("Checking game data…"))
            }
        } else if let folder = model.activeDataFolder {
            VStack(alignment: .leading, spacing: 6) {
                LabeledContent(L("Source"),
                               value: folder == model.paths.importedGameData ? L("Imported copy") : L("Bundled with the app"))
                if let report = model.activeReport {
                    ReportSummary(report: report)
                }
            }
        } else {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("No game data found")).font(.headline)
                    Text(L("This build has no bundled GameData folder. Import a game data folder below."))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
            }
        }
    }
}

/// OK / problem verdict of one validation report, with the problems listed.
struct ReportSummary: View {
    let report: GameDataReport

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(report.isOK ? L("Game data OK") : L("Game data has problems"))
                    .font(.headline)
                Text(L("%d archives, %@", report.archives.count,
                       ByteCountFormatter.string(fromByteCount: report.totalBytes, countStyle: .file)))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ForEach(report.issues, id: \.self) { issue in
                    Text("• " + Self.describe(issue))
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                }
            }
        } icon: {
            Image(systemName: report.isOK ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(report.isOK ? .green : .orange)
        }
        .accessibilityElement(children: .combine)
    }

    /// Android's setup_folder_issue_* wording.
    static func describe(_ issue: GameDataReport.Issue) -> String {
        switch issue {
        case .folderMissing:
            return L("The game data folder is missing.")
        case .notAGameFolder:
            return L("Neither INIZH.big nor INI.big is in this folder: it is not a Zero Hour folder.")
        case .emptyArchive(let name):
            return L("%@ is empty (0 bytes)", name)
        case .badHeader(let name):
            return L("%@ doesn't look like a valid game archive", name)
        case .missingData(let archives):
            return L("%@ is missing expected game data — likely an incomplete copy", archives.joined(separator: ", "))
        case .missingBaseArchives(let names):
            return L("Base Generals game data missing: %@", names.joined(separator: ", "))
        }
    }
}

/// A setting's title with a secondary description underneath.
struct SettingLabel: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
#endif
