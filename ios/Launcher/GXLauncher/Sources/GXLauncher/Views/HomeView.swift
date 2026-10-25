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

// GeneralsX @feature iOS launcher 25/10/2026 Home: Play, launch options, the game folder chosen in
// Files (Android's "Select game folder"), and copying a game folder into the app as the secondary
// option (SetupActivity.buildHomeSection on Android).
//
// The published app ships without game data. Data source priority (LaunchPlanBuilder.gameDataSource):
// the chosen folder > the copy inside the app > <App>/GameData (developer builds). Play is disabled
// when there is none, and Home explains how to get the data.

#if canImport(UIKit) && os(iOS)
import SwiftUI
import GXLauncherCore

struct HomeView: View {
    @ObservedObject var model: LauncherModel

    enum PickerPurpose: String, Identifiable {
        case choose, copy
        var id: String { rawValue }
    }

    @State private var picker: PickerPurpose?
    @State private var confirmDelete = false
    @State private var confirmForget = false

    var body: some View {
        Form {
            Section {
                PlayButton(model: model, compact: false)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            } footer: {
                if !model.canPlay {
                    Text(playFooter)
                }
            }

            gameFolderSection

            if !model.canPlay, model.externalStatus == .none {
                noDataSection
            }

            if let source = model.activeSource {
                Section {
                    LabeledContent(L("Playing from"), value: Self.sourceName(source))
                    // The chosen folder's report is already shown in its own section.
                    if case .external = source {
                    } else if let report = model.activeReport {
                        ReportSummary(report: report)
                    } else if model.isValidating {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text(L("Checking game data…"))
                        }
                    }
                    Button {
                        model.validate()
                    } label: {
                        Label(L("Check again"), systemImage: "arrow.clockwise")
                    }
                    .disabled(model.isValidating)
                } header: {
                    Text(L("Game data"))
                }
            }

            Section {
                Toggle(isOn: Binding(get: { model.preferences.skipIntro }, set: model.setSkipIntro)) {
                    SettingLabel(title: L("Skip intro movies"),
                                 detail: L("EA logos, the intro and other movies before the menu are skipped; the game goes straight to loading."))
                }
                Toggle(isOn: Binding(get: { model.preferences.playSoundInSilentMode }, set: model.setPlaySoundInSilentMode)) {
                    SettingLabel(title: L("Play sound in silent mode"),
                                 detail: L("Game sound plays even when the Ring/Silent switch is set to silent. Turn off to follow the switch. Other apps' audio keeps playing either way."))
                }
            } header: {
                Text(L("Options"))
            }

            importSection
        }
        .navigationTitle(LauncherInfo.appName)
        .sheet(item: $picker) { purpose in
            FolderPicker { url in
                switch purpose {
                case .choose: model.chooseGameFolder(url)
                case .copy: model.startImport(from: url)
                }
            }
            .ignoresSafeArea()
        }
        .alert(L("Not a game folder"), isPresented: Binding(
            get: { model.pickError != nil }, set: { if !$0 { model.pickError = nil } })) {
            Button(L("OK"), role: .cancel) {}
        } message: {
            Text(model.pickError ?? "")
        }
        .confirmationDialog(L("Delete the copy inside the app?"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(L("Delete copy"), role: .destructive) { model.removeImported() }
        } message: {
            Text(L("Your game folder in Files is not touched. You can copy a folder again at any time."))
        }
        .confirmationDialog(L("Forget this game folder?"), isPresented: $confirmForget, titleVisibility: .visible) {
            Button(L("Forget"), role: .destructive) { model.forgetGameFolder() }
        } message: {
            Text(L("The folder and its files stay where they are; the app just stops using it."))
        }
    }

    private var playFooter: String {
        switch model.externalStatus {
        case .waitingForICloud: return L("Play becomes available once iCloud Drive has downloaded the game.")
        case .unavailable: return L("The chosen game folder cannot be opened. Choose it again.")
        case .checking: return L("Checking the game folder…")
        default: return L("Choose your game folder below to play.")
        }
    }

    static func sourceName(_ source: GameDataSource) -> String {
        switch source {
        case .external: return L("Chosen game folder")
        case .imported: return L("Copy inside the app")
        case .bundled: return L("Bundled with the app (developer build)")
        }
    }

    // MARK: No game data yet

    private var noDataSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Label(L("This app does not include the game data"), systemImage: "shippingbox")
                    .font(.headline)
                Text(L("You need your own copy of Command & Conquer Generals: Zero Hour, for example from Steam or EA App on a PC."))
                Text(L("1. Copy the game folder (the one with INIZH.big) to this iPhone: in the Files app, into a folder under On My iPhone."))
                Text(L("2. Tap Choose game folder and select it."))
                Text(L("3. Tap Play."))
                Text(L("From a computer: connect the iPhone, open it in Finder (or the Apple Devices app on Windows), and drag the game folder onto %@ in its Files tab. The launcher finds it there on its own.", LauncherInfo.appName))
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
            .padding(.vertical, 4)
        }
    }

    // MARK: Chosen game folder

    @ViewBuilder
    private var gameFolderSection: some View {
        Section {
            switch model.externalStatus {
            case .none:
                Button {
                    picker = .choose
                } label: {
                    Label(L("Choose game folder…"), systemImage: "folder.badge.gearshape")
                }
                .accessibilityIdentifier("gx.chooseFolder")
            case .checking(let name):
                folderHeader(name: name)
                HStack(spacing: 12) {
                    ProgressView()
                    Text(L("Checking game data…"))
                }
                folderButtons
            case .unavailable(let name, let reason):
                folderHeader(name: name)
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("The folder cannot be opened")).font(.headline)
                        Text(L("It may have been moved, renamed or deleted, or the drive is not connected. Choose it again."))
                            .font(.subheadline).foregroundStyle(.secondary)
                        if !reason.isEmpty {
                            Text(reason).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } icon: {
                    Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                }
                folderButtons
            case .waitingForICloud(let name, let pending, let total):
                folderHeader(name: name)
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: Double(max(total - pending, 0)), total: Double(max(total, 1))) {
                        Label(L("Waiting for iCloud Drive"), systemImage: "icloud.and.arrow.down")
                    } currentValueLabel: {
                        Text(L("%d of %d game archives downloaded", max(total - pending, 0), total))
                    }
                    Text(L("The game can only start once every archive is on this iPhone. Keep the app open, or move the folder to On My iPhone."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                folderButtons
            case .ready(let report):
                folderHeader(name: model.externalFolder?.lastPathComponent ?? "")
                ReportSummary(report: report)
                if let notice = model.supportNotice {
                    Label {
                        Text(notice).font(.footnote)
                    } icon: {
                        Image(systemName: "info.circle").foregroundStyle(.orange)
                    }
                }
                folderButtons
            }
        } header: {
            Text(L("Game folder"))
        } footer: {
            Text(L("A folder on this iPhone (Files › On My iPhone) is recommended. Folders in iCloud Drive work too, but every file must be downloaded first, and the system may remove downloaded copies to free space."))
        }
    }

    private func folderHeader(name: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.headline).lineLimit(2)
                if let location = model.externalLocation {
                    Text(Self.locationName(location)).font(.subheadline).foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: model.externalLocation == .iCloudDrive ? "icloud" : "folder")
        }
    }

    @ViewBuilder
    private var folderButtons: some View {
        Button {
            picker = .choose
        } label: {
            Label(L("Change…"), systemImage: "folder.badge.gearshape")
        }
        Button(role: .destructive) {
            confirmForget = true
        } label: {
            Label(L("Forget"), systemImage: "minus.circle")
        }
    }

    static func locationName(_ location: FolderLocation) -> String {
        switch location {
        case .appDocuments: return L("%@ app folder (copied with Finder)", LauncherInfo.appName)
        case .onDevice: return L("On My iPhone")
        case .iCloudDrive: return L("iCloud Drive")
        case .externalDrive(let name): return name.isEmpty ? L("External drive") : L("External drive “%@”", name)
        case .other: return L("Files")
        }
    }

    // MARK: Copy into the app (secondary)

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
                Button(L("Cancel copying"), role: .cancel) { model.cancelImport() }
            case .failed(let message):
                Label {
                    Text(message)
                } icon: {
                    Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                }
                copyButton(title: L("Try again…"))
            case .idle:
                if model.hasImportedData {
                    if let report = model.importedReport {
                        ReportSummary(report: report)
                    }
                    copyButton(title: L("Replace with another folder…"))
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label(L("Delete copy"), systemImage: "trash")
                    }
                } else {
                    copyButton(title: L("Copy a game folder into the app…"))
                }
            }
        } header: {
            Text(L("Copy into the app instead"))
        } footer: {
            Text(L("Copies the whole game (about 2.7 GB) into the app's own storage, kept out of device backups. Used when no game folder is chosen above."))
        }
    }

    private func copyButton(title: String) -> some View {
        Button {
            picker = .copy
        } label: {
            Label(title, systemImage: "square.and.arrow.down.on.square")
        }
    }
}

/// The big Play button. Disabled without game data; asks before starting with game data that
/// failed the check.
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
        .disabled(!model.canPlay)
        .accessibilityIdentifier("gx.play")
        .alert(L("Game data has problems"), isPresented: $confirm) {
            Button(L("Play anyway")) { model.play() }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(L("The game may fail to start or show missing textures. See Home > Game data for details."))
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
