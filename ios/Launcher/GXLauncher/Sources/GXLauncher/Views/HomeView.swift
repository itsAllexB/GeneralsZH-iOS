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

// GeneralsX @feature iOS launcher 25/10/2026 Home: Play, the game folder chosen in Files (Android's
// "Select game folder") and the launch options (SetupActivity.buildHomeSection on Android).
//
// The published app ships without game data. Data source priority (LaunchPlanBuilder.gameDataSource):
// the chosen folder (or one found in Documents) > <App>/GameData (developer builds). Play is
// disabled when there is none, and Home explains how to get the data.

#if canImport(UIKit) && os(iOS)
import SwiftUI
import GXLauncherCore

struct HomeView: View {
    @ObservedObject var model: LauncherModel

    @State private var showPicker = false
    @FocusState private var nameFocused: Bool
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

            Section {
                playerNameRow
                Toggle(isOn: Binding(get: { model.preferences.skipIntro }, set: model.setSkipIntro)) {
                    SettingLabel(title: L("Skip intro movies"),
                                 detail: L("EA logos, the intro and other movies before the menu are skipped; the game goes straight to loading."))
                }
                Toggle(isOn: Binding(get: { model.preferences.playSoundInSilentMode }, set: model.setPlaySoundInSilentMode)) {
                    SettingLabel(title: L("Play sound in silent mode"),
                                 detail: L("Game sound plays even when the Ring/Silent switch is set to silent. Turn off to follow the switch. Other apps' audio keeps playing either way."))
                }
                Toggle(isOn: Binding(get: { model.controlScheme.cameraHigh }, set: model.setCameraHigh)) {
                    SettingLabel(title: L("Allow higher camera"),
                                 detail: L("The camera zooms out up to four times further than the map allows."))
                }
                // Only 60 Hz screens: nothing to choose, so no row (GX_FPS_LIMIT is still 60).
                if model.frameRateChoices.count > 1 {
                    frameRateRow
                }
            } header: {
                Text(L("Options"))
            }
        }
        .navigationTitle(LauncherInfo.appName)
        .refreshable { model.validate() }
        .sheet(isPresented: $showPicker) {
            FolderPicker { url in model.chooseGameFolder(url) }
                .ignoresSafeArea()
        }
        .alert(L("Not a game folder"), isPresented: Binding(
            get: { model.pickError != nil }, set: { if !$0 { model.pickError = nil } })) {
            Button(L("OK"), role: .cancel) {}
        } message: {
            Text(model.pickError ?? "")
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

    // MARK: Player name

    private var playerNameRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent(L("Player Name")) {
                // Bound straight to the model and filtered in onChange: a filtering Binding is not
                // reflected by the text field while it is being edited.
                TextField(L("Device name"), text: $model.playerName)
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($nameFocused)
                .onSubmit { model.commitPlayerName() }
                .accessibilityIdentifier("gx.playerName")
            }
            Text(L("Your name in skirmish and LAN games. Up to 12 characters; empty uses the device name."))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .onChange(of: nameFocused) { focused in
            if !focused { model.commitPlayerName() }
        }
        .onChange(of: model.playerName) { typed in
            let allowed = PlayerName.filterTyping(typed)
            if allowed != typed { model.playerName = allowed }
        }
    }

    // MARK: Frame rate

    private var frameRateRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Frame Rate"))
            Picker(L("Frame Rate"), selection: Binding(get: { model.frameRate }, set: model.setFrameRate)) {
                ForEach(model.frameRateChoices, id: \.self) { fps in
                    Text(L("%d fps", fps)).tag(fps)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text(L("The game itself always runs at 60 updates a second. 120 makes scrolling and animation smoother on ProMotion screens and uses more battery."))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
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
                    showPicker = true
                } label: {
                    Label(L("Choose game folder…"), systemImage: "folder.badge.gearshape")
                }
                .accessibilityIdentifier("gx.chooseFolder")
                // Developer builds carry GameData in the bundle; say so and show its check.
                if case .bundled? = model.activeSource {
                    Label(L("Using the game data bundled with this developer build"), systemImage: "hammer")
                        .font(.subheadline)
                    if let report = model.bundledReport {
                        ReportSummary(report: report)
                    }
                    checkAgainButton
                }
            case .checking(let name):
                folderHeader(name: name)
                HStack(spacing: 12) {
                    ProgressView()
                    Text(L("Checking game data…"))
                }
                folderButtons(checkAgain: false)
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
                folderButtons(checkAgain: true)
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
                folderButtons(checkAgain: false)
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
                folderButtons(checkAgain: true)
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

    /// Checks the folder (and its files) again; pull to refresh does the same.
    private var checkAgainButton: some View {
        Button {
            model.validate()
        } label: {
            Label(L("Check again"), systemImage: "arrow.clockwise")
        }
        .disabled(model.isValidating)
    }

    @ViewBuilder
    private func folderButtons(checkAgain: Bool) -> some View {
        if checkAgain {
            checkAgainButton
        }
        Button {
            showPicker = true
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
            Text(L("The game may fail to start or show missing textures. See Home > Game folder for details."))
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
