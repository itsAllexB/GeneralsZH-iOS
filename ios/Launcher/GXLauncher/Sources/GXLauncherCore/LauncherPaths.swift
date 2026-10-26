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

// GeneralsX @feature iOS launcher 25/10/2026 Every file and folder the launcher reads or writes,
// in one place, derived from the app's home directory exactly as the engine derives them:
//
//   $HOME/Library/Application Support/GeneralsX/GeneralsZH/Options.ini
//       The engine's user-data dir (GlobalData.cpp, SDL3Main.cpp "Seed default settings").
//   $HOME/Library/Application Support/GeneralsX/launcher/
//       GX_SETTINGS_DIR: control_scheme, mouse_mode, logging_off, gx_*.txt markers and the
//       launcher's own preferences. The app bundle is read-only, so markers cannot live next to
//       the game data as they do on Android.
//   $HOME/Documents/generals-stderr.log, generals-stderr-prev.log
//       The engine's stderr mirror (SDL3Main.cpp), shown by the log viewer.
//   <App>.app/GameData/
//       Read-only bundled game data (dev builds only; the published IPA ships without it).
//   <App>.app/GameSupport/
//       The port's own files the engine expects inside the game folder (fonts/, Window/, dxvk.conf,
//       DefaultOptions.ini), copied into whichever game folder is used (SupportFileSync).
//   $GX_SETTINGS_DIR/game_folder.json
//       The game folder the player chose in Files: a bookmark plus the path below it.
//
// A value type with an injectable home and bundle so unit tests can point it at a temp folder.

import Foundation

public struct LauncherPaths: Sendable, Equatable {
    /// The app's home directory (NSHomeDirectory() in the app, a temp dir in tests).
    public var home: URL
    /// The game data shipped inside the app bundle (<App>.app/GameData). May not exist.
    public var bundledGameData: URL
    /// The port's support files shipped inside the app bundle (<App>.app/GameSupport).
    public var bundledSupport: URL

    /// `bundledSupport` defaults to the GameSupport folder next to `bundledGameData`.
    public init(home: URL, bundledGameData: URL, bundledSupport: URL? = nil) {
        self.home = home
        self.bundledGameData = bundledGameData
        self.bundledSupport = bundledSupport
            ?? bundledGameData.deletingLastPathComponent().appendingPathComponent("GameSupport", isDirectory: true)
    }

    /// The paths of the running app.
    public static var current: LauncherPaths {
        LauncherPaths(
            home: URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
            bundledGameData: Bundle.main.bundleURL.appendingPathComponent("GameData", isDirectory: true),
            bundledSupport: Bundle.main.bundleURL.appendingPathComponent("GameSupport", isDirectory: true)
        )
    }

    /// $HOME/Library/Application Support/GeneralsX
    public var generalsXSupport: URL {
        home.appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("GeneralsX", isDirectory: true)
    }

    /// GX_SETTINGS_DIR.
    public var settingsDir: URL { generalsXSupport.appendingPathComponent("launcher", isDirectory: true) }

    /// The engine's user-data directory (saves, maps, Options.ini).
    public var userDataDir: URL { generalsXSupport.appendingPathComponent("GeneralsZH", isDirectory: true) }

    public var optionsIni: URL { userDataDir.appendingPathComponent("Options.ini", isDirectory: false) }
    /// The game's skirmish and LAN preferences (UserName, see PlayerName).
    public var skirmishIni: URL { userDataDir.appendingPathComponent("Skirmish.ini", isDirectory: false) }
    public var networkIni: URL { userDataDir.appendingPathComponent("Network.ini", isDirectory: false) }

    public var documents: URL { home.appendingPathComponent("Documents", isDirectory: true) }
    public var currentLog: URL { documents.appendingPathComponent("generals-stderr.log", isDirectory: false) }
    public var previousLog: URL { documents.appendingPathComponent("generals-stderr-prev.log", isDirectory: false) }

    /// The launcher's own preferences (skip intro, data source), JSON.
    public var preferencesFile: URL { settingsDir.appendingPathComponent("launcher_prefs.json", isDirectory: false) }

    /// The chosen external game folder (bookmark), see GameFolderStore.
    public var gameFolderFile: URL { settingsDir.appendingPathComponent("game_folder.json", isDirectory: false) }
    /// A game folder in Documents the player chose to forget (its path), so it is not adopted again.
    public var forgottenDocumentsFolderFile: URL { settingsDir.appendingPathComponent("game_folder_forgotten", isDirectory: false) }

    /// DefaultOptions.ini to seed a new Options.ini from: GameSupport's, else the given data folder's.
    public func defaultOptionsSource(dataFolder: URL?) -> URL? {
        let candidates = [bundledSupport.appendingPathComponent("DefaultOptions.ini")]
            + (dataFolder.map { [$0.appendingPathComponent("DefaultOptions.ini")] } ?? [])
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// A file inside GX_SETTINGS_DIR.
    public func settingsFile(_ name: String) -> URL {
        settingsDir.appendingPathComponent(name, isDirectory: false)
    }

    /// Creates GX_SETTINGS_DIR (and its parents) if missing.
    @discardableResult
    public func ensureSettingsDir() throws -> URL {
        try FileManager.default.createDirectory(at: settingsDir, withIntermediateDirectories: true)
        return settingsDir
    }
}
