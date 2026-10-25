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

    enum ImportState: Equatable {
        case idle
        case copying(ImportProgress)
        case failed(String)
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
    @Published private(set) var importedReport: GameDataReport?
    @Published private(set) var isValidating = false
    @Published private(set) var importState: ImportState = .idle

    /// The last failed save, shown as an alert.
    @Published var saveError: String?

    /// Set when the player tapped Play; the runner's run loop watches it.
    @Published private(set) var finished = false

    private var importTask: Task<Void, Never>?

    init(paths: LauncherPaths) {
        self.paths = paths
        _ = try? paths.ensureSettingsDir()
        preferences = LauncherPreferences.load(from: paths.preferencesFile)
        let options = OptionsIniStore(file: paths.optionsIni, defaults: nil).load()
        interfaceScale = InterfaceScale.read(options)
        menuTextSize = MenuTextSize.read(options)
        controlScheme = ControlScheme.read(from: paths.settingsFile(ControlScheme.fileName))
        mouseMode = MouseMode.read(from: paths.settingsFile(MouseMode.fileName))
        collectLogs = !MarkerFile.loggingOff.isPresent(in: paths)
        diagnostics = Set(MarkerFile.diagnostics.filter { $0.isPresent(in: paths) })
    }

    // MARK: - Play

    func play() {
        cancelImport()
        finished = true
    }

    /// The game data the engine will be pointed at.
    var activeDataFolder: URL? {
        LaunchPlanBuilder.gameDataDirectory(paths: paths, preferences: preferences)
    }

    var activeReport: GameDataReport? {
        guard let folder = activeDataFolder else { return nil }
        return folder == paths.importedGameData ? importedReport : bundledReport
    }

    /// True when Play should ask "play anyway?" first.
    var dataNeedsConfirmation: Bool {
        if isValidating { return false }
        guard let report = activeReport else { return activeDataFolder == nil }
        return !report.isOK
    }

    var hasImportedData: Bool { FileManager.default.fileExists(atPath: paths.importedGameData.path) }

    // MARK: - Launcher preferences

    func setSkipIntro(_ on: Bool) {
        var prefs = preferences
        prefs.skipIntro = on
        savePreferences(prefs)
    }

    func setPreferImportedData(_ on: Bool) {
        var prefs = preferences
        prefs.preferImportedData = on
        savePreferences(prefs)
    }

    private func savePreferences(_ prefs: LauncherPreferences) {
        preferences = prefs
        report { try prefs.save(to: paths.preferencesFile) }
    }

    // MARK: - Options.ini

    private var optionsStore: OptionsIniStore {
        let defaults = activeDataFolder?.appendingPathComponent("DefaultOptions.ini")
        return OptionsIniStore(file: paths.optionsIni, defaults: defaults)
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
        guard !isValidating else { return }
        isValidating = true
        let paths = paths
        Task.detached(priority: .userInitiated) {
            let bundled = GameDataValidator.validate(paths.bundledGameData)
            let imported = FileManager.default.fileExists(atPath: paths.importedGameData.path)
                ? GameDataValidator.validate(paths.importedGameData) : nil
            await MainActor.run {
                self.bundledReport = bundled
                self.importedReport = imported
                self.isValidating = false
            }
        }
    }

    func startImport(from source: URL) {
        guard importTask == nil else { return }
        importState = .copying(ImportProgress(copiedBytes: 0, totalBytes: 0, currentFile: ""))
        let paths = paths
        // The model outlives the launcher window, so a strong capture is fine (and Sendable:
        // the model is main-actor isolated).
        importTask = Task.detached(priority: .userInitiated) { [self] in
            let scoped = source.startAccessingSecurityScopedResource()
            defer { if scoped { source.stopAccessingSecurityScopedResource() } }
            // Throttle UI updates to ~10 per second.
            let throttle = ProgressThrottle()
            do {
                let result = try GameDataImporter.importFolder(from: source, paths: paths) { progress in
                    guard throttle.shouldEmit(progress) else { return }
                    Task { @MainActor in
                        if case .copying = self.importState { self.importState = .copying(progress) }
                    }
                }
                await MainActor.run {
                    self.importedReport = result
                    self.importState = .idle
                    self.importTask = nil
                    // A good import is presumably what the player wants to play.
                    if result.isOK { self.setPreferImportedData(true) }
                }
            } catch {
                let message = Self.describe(error)
                let cancelled = Task.isCancelled
                await MainActor.run {
                    self.importState = cancelled ? .idle : .failed(message)
                    self.importTask = nil
                }
            }
        }
    }

    func cancelImport() {
        importTask?.cancel()
    }

    func removeImported() {
        report { try GameDataImporter.removeImported(paths: paths) }
        importedReport = nil
        if preferences.preferImportedData { setPreferImportedData(false) }
        importState = .idle
        objectWillChange.send()
    }

    nonisolated static func describe(_ error: Error) -> String {
        switch error as? ImportError {
        case .sourceUnreadable?:
            return L("The selected folder could not be read.")
        case .notEnoughSpace(let needed, let available)?:
            return L("Not enough free space: %@ needed, %@ available.",
                     ByteCountFormatter.string(fromByteCount: needed, countStyle: .file),
                     ByteCountFormatter.string(fromByteCount: available, countStyle: .file))
        case .notAGameFolder?:
            return L("The selected folder does not contain INIZH.big or INI.big. Pick the folder the game is installed in.")
        case .cancelled?:
            return L("Import cancelled.")
        case .copyFailed(let name)?:
            return L("Copying %@ failed.", name)
        case nil:
            return error.localizedDescription
        }
    }
}

/// Lets the copying thread report progress at most ~10 times per second.
private final class ProgressThrottle: @unchecked Sendable {
    private var last = Date.distantPast
    private let lock = NSLock()

    func shouldEmit(_ progress: ImportProgress) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let now = Date()
        if now.timeIntervalSince(last) < 0.1 && progress.copiedBytes < progress.totalBytes { return false }
        last = now
        return true
    }
}
#endif
