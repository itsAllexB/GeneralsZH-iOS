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

// GeneralsX @feature iOS launcher 25/10/2026 The launcher's state, loaded from and written straight
// back to the files the engine reads (see GXLauncherCore). Every change is saved immediately, so
// leaving the launcher by any route -- Play, or the app being killed -- never loses a setting.

#if canImport(UIKit) && os(iOS)
import Foundation
import SwiftUI
import GXLauncherCore

@MainActor
final class LauncherModel: ObservableObject {
    enum Section: String, CaseIterable, Identifiable, Hashable {
        case home, interface, tools, help
        var id: String { rawValue }

        var title: String {
            switch self {
            case .home: return L("Home")
            case .interface: return L("Interface")
            case .tools: return L("Tools")
            case .help: return L("Help")
            }
        }

        var symbol: String {
            switch self {
            case .home: return "play.circle"
            case .interface: return "slider.horizontal.3"
            case .tools: return "wrench.and.screwdriver"
            case .help: return "questionmark.circle"
            }
        }
    }

    /// The folder chosen in Files (GameFolderStore).
    enum ExternalStatus: Equatable {
        /// No folder chosen.
        case none
        /// Opening / checking it.
        case checking(name: String)
        /// Chosen, but cannot be reached right now.
        case unavailable(name: String, reason: String)
        /// iCloud Drive is still downloading `pending` of the archives.
        case waitingForICloud(name: String, pending: Int, total: Int)
        /// Opened and validated.
        case ready(GameDataReport)
    }

    let paths: LauncherPaths

    @Published var section: Section = .home
    /// Pushes the log viewer on the Tools stack (also used for deep-linking during testing).
    @Published var showLogs = false

    @Published private(set) var preferences: LauncherPreferences
    @Published private(set) var interfaceScale: Int
    @Published private(set) var menuTextSize: Int
    @Published private(set) var controlScheme: ControlScheme
    @Published private(set) var mouseMode: MouseMode
    @Published private(set) var collectLogs: Bool
    @Published private(set) var diagnostics: Set<MarkerFile>

    @Published private(set) var bundledReport: GameDataReport?
    @Published private(set) var isValidating = false

    @Published private(set) var externalStatus: ExternalStatus = .none
    /// The opened game folder while `externalStatus` is `.ready`.
    @Published private(set) var externalFolder: URL?
    @Published private(set) var externalLocation: FolderLocation?
    /// Set when the support files could not be copied into the game folder.
    @Published private(set) var supportNotice: String?
    /// A picked folder that was not accepted.
    @Published var pickError: String?
    private var iCloudTotal = 0
    private var iCloudPolling = false

    /// The last failed save, shown as an alert.
    @Published var saveError: String?

    /// Set when the player tapped Play; the runner's run loop watches it.
    @Published private(set) var finished = false

    /// Home > Options > Player Name, as typed. Read from Skirmish.ini / Network.ini whenever the
    /// launcher appears (the game writes those files too); written on commit and on Play.
    @Published var playerName: String

    /// The screen's maximum frame rate (120 on ProMotion), for the Frame Rate choices.
    let maximumFramesPerSecond: Int

    init(paths: LauncherPaths, maximumFramesPerSecond: Int = FrameRate.defaultRate) {
        self.paths = paths
        self.maximumFramesPerSecond = maximumFramesPerSecond
        _ = try? paths.ensureSettingsDir()
        preferences = LauncherPreferences.load(from: paths.preferencesFile)
        let options = OptionsIniStore(file: paths.optionsIni, defaults: nil).load()
        interfaceScale = InterfaceScale.read(options)
        menuTextSize = MenuTextSize.read(options)
        controlScheme = ControlScheme.read(from: paths.settingsFile(ControlScheme.fileName))
        mouseMode = MouseMode.read(from: paths.settingsFile(MouseMode.fileName))
        collectLogs = !MarkerFile.loggingOff.isPresent(in: paths)
        diagnostics = Set(MarkerFile.diagnostics.filter { $0.isPresent(in: paths) })
        playerName = PlayerName.read(paths: paths)
    }

    // MARK: - Play

    func play() {
        commitPlayerName()
        finished = true
    }

    /// Writes the Player Name into Skirmish.ini and Network.ini (nothing when empty).
    func commitPlayerName() {
        let name = PlayerName.sanitize(playerName)
        if name != playerName { playerName = name }
        report { try PlayerName.write(name, paths: paths) }
    }

    /// The chosen folder, when it can be played from right now.
    var usableExternalFolder: URL? {
        guard case .ready(let report) = externalStatus, let folder = externalFolder,
              !report.issues.contains(.notAGameFolder), !report.issues.contains(.folderMissing) else { return nil }
        return folder
    }

    /// Where the game data will come from (same priority as the runner).
    var activeSource: GameDataSource? {
        LaunchPlanBuilder.gameDataSource(paths: paths, externalFolder: usableExternalFolder)
    }

    /// The game data the engine will be pointed at.
    var activeDataFolder: URL? { activeSource?.url }

    var activeReport: GameDataReport? {
        switch activeSource {
        case .external?:
            if case .ready(let report) = externalStatus { return report }
            return nil
        case .bundled?: return bundledReport
        case nil: return nil
        }
    }

    /// True when Play should ask "play anyway?" first.
    var dataNeedsConfirmation: Bool {
        if isValidating { return false }
        guard let report = activeReport else { return false }
        return !report.isOK
    }

    /// Play needs some game data.
    var canPlay: Bool { activeSource != nil }

    var hasBundledData: Bool { FileManager.default.fileExists(atPath: paths.bundledGameData.path) }

    // MARK: - Launcher preferences

    func setSkipIntro(_ on: Bool) {
        var prefs = preferences
        prefs.skipIntro = on
        savePreferences(prefs)
    }

    func setPlaySoundInSilentMode(_ on: Bool) {
        var prefs = preferences
        prefs.playSoundInSilentMode = on
        savePreferences(prefs)
    }

    /// The Frame Rate choices this screen can show (120 only at 120 Hz).
    var frameRateChoices: [Int] { FrameRate.choices(maximumFramesPerSecond: maximumFramesPerSecond) }

    /// The saved frame rate as it will be used (120 falls back to 60 on a 60 Hz screen).
    var frameRate: Int {
        FrameRate.effective(preferences.frameRate, maximumFramesPerSecond: maximumFramesPerSecond)
    }

    func setFrameRate(_ fps: Int) {
        var prefs = preferences
        prefs.frameRate = FrameRate.effective(fps, maximumFramesPerSecond: maximumFramesPerSecond)
        savePreferences(prefs)
    }

    private func savePreferences(_ prefs: LauncherPreferences) {
        preferences = prefs
        report { try prefs.save(to: paths.preferencesFile) }
    }

    // MARK: - Options.ini

    private var optionsStore: OptionsIniStore {
        OptionsIniStore(file: paths.optionsIni, defaults: paths.defaultOptionsSource(dataFolder: activeDataFolder))
    }

    func setInterfaceScale(_ percent: Int) {
        let value = InterfaceScale.clamp(percent)
        guard value != interfaceScale else { return }
        interfaceScale = value
        report { try optionsStore.update { $0.set(InterfaceScale.key, String(value)) } }
    }

    func setMenuTextSize(_ percent: Int) {
        let value = MenuTextSize.clamp(percent)
        guard value != menuTextSize else { return }
        menuTextSize = value
        report { try optionsStore.update { $0.set(MenuTextSize.key, String(value)) } }
    }

    // MARK: - Controls

    func setControlScheme(_ scheme: ControlScheme) {
        controlScheme = scheme
        report { try scheme.write(to: paths.settingsFile(ControlScheme.fileName)) }
    }

    /// Home > Options > Allow higher camera (camera_high in control_scheme).
    func setCameraHigh(_ on: Bool) {
        var scheme = controlScheme
        scheme.cameraHigh = on
        setControlScheme(scheme)
    }

    func applyPreset(_ preset: ControlScheme.Preset) {
        var scheme = controlScheme
        scheme.apply(preset)
        setControlScheme(scheme)
    }

    func setMouseMode(_ mode: MouseMode) {
        mouseMode = mode
        report { try mode.write(to: paths.settingsFile(MouseMode.fileName)) }
    }

    // MARK: - Logs and diagnostics

    func setCollectLogs(_ on: Bool) {
        collectLogs = on
        report { try MarkerFile.loggingOff.set(!on, in: paths) }
    }

    func setDiagnostic(_ marker: MarkerFile, _ on: Bool) {
        if on { diagnostics.insert(marker) } else { diagnostics.remove(marker) }
        report { try marker.set(on, in: paths) }
    }

    private func report(_ work: () throws -> Void) {
        do {
            try work()
        } catch {
            saveError = error.localizedDescription
        }
    }

    // MARK: - Game data

    func validate() {
        refreshExternal()
        guard !isValidating else { return }
        isValidating = true
        let paths = paths
        Task.detached(priority: .userInitiated) {
            let bundled = FileManager.default.fileExists(atPath: paths.bundledGameData.path)
                ? GameDataValidator.validate(paths.bundledGameData) : nil
            await MainActor.run {
                self.bundledReport = bundled
                self.isValidating = false
            }
        }
    }

    // MARK: - Game folder chosen in Files

    /// Opens and checks the chosen folder in the background (also polls while iCloud downloads).
    func refreshExternal() {
        guard let reference = GameFolderStore.loadOrAdoptDocumentsFolder(paths: paths) else {
            externalStatus = .none
            externalFolder = nil
            externalLocation = nil
            return
        }
        if case .checking = externalStatus { return }
        if case .waitingForICloud = externalStatus {} else { externalStatus = .checking(name: reference.name) }
        let paths = paths
        Task.detached(priority: .userInitiated) { [self] in
            let state = GameFolderAccess.open(paths: paths)
            guard case .open(let folder, _) = state else {
                let reason: String
                if case .unavailable(_, let why) = state { reason = why } else { reason = "" }
                await MainActor.run {
                    self.externalFolder = nil
                    self.externalStatus = .unavailable(name: reference.name, reason: reason)
                }
                return
            }
            let location = FolderLocation.of(folder, paths: paths)
            let pending = UbiquitousFiles.pendingArchives(in: folder)
            if !pending.isEmpty {
                UbiquitousFiles.startDownloading(pending)
                await MainActor.run {
                    self.externalFolder = folder
                    self.externalLocation = location
                    self.iCloudTotal = max(self.iCloudTotal, pending.count)
                    self.externalStatus = .waitingForICloud(name: reference.name, pending: pending.count,
                                                            total: self.iCloudTotal)
                    self.pollICloud()
                }
                return
            }
            let report = GameDataValidator.validate(folder)
            // Put the support files in now, so a read-only folder is reported before Play.
            let sync = SupportFileSync.sync(from: paths.bundledSupport, to: folder)
            await MainActor.run {
                self.iCloudTotal = 0
                self.externalFolder = folder
                self.externalLocation = location
                self.externalStatus = .ready(report)
                self.supportNotice = sync.hadSupport && !sync.complete
                    ? L("This folder is read-only, so the port's files could not be copied into it. The game uses the app's own fonts and settings instead, but its interface fixes (Window layouts) will be missing. Move the folder to On My iPhone to fix this.")
                    : nil
            }
        }
    }

    private func pollICloud() {
        guard !iCloudPolling else { return }
        iCloudPolling = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            self.iCloudPolling = false
            if case .waitingForICloud = self.externalStatus, !self.finished {
                self.refreshExternal()
            }
        }
    }

    /// The player picked `url` in the folder picker.
    func chooseGameFolder(_ url: URL) {
        pickError = nil
        let paths = paths
        Task.detached(priority: .userInitiated) { [self] in
            GameFolderAccess.startAccessing(url)
            guard let gameFolder = GameDataValidator.findGameFolder(in: url) else {
                await MainActor.run {
                    self.pickError = L("No Zero Hour game folder was found in “%@”. Pick the folder that contains INIZH.big (or the one right above it).", url.lastPathComponent)
                }
                return
            }
            do {
                let reference = try GameFolderStore.makeReference(picked: url, gameFolder: gameFolder)
                try GameFolderStore.save(reference, paths: paths)
            } catch {
                await MainActor.run { self.pickError = error.localizedDescription }
                return
            }
            await MainActor.run {
                self.iCloudTotal = 0
                self.externalStatus = .none
                self.refreshExternal()
            }
        }
    }

    func forgetGameFolder() {
        GameFolderStore.forget(paths: paths)
        externalStatus = .none
        externalFolder = nil
        externalLocation = nil
        supportNotice = nil
    }
}
#endif
