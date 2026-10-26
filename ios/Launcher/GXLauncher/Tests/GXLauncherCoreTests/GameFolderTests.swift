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

// GeneralsX @feature iOS launcher 25/10/2026 The chosen game folder: nested-folder detection,
// bookmarks, iCloud placeholders, GameSupport sync and the whole launch preparation.

import XCTest
@testable import GXLauncherCore

final class GameFolderTests: XCTestCase {
    private func makeSupport(_ paths: LauncherPaths) throws {
        let support = paths.bundledSupport
        try FileManager.default.createDirectory(at: support.appendingPathComponent("fonts"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: support.appendingPathComponent("Window/Menus"), withIntermediateDirectories: true)
        try Data("font-a".utf8).write(to: support.appendingPathComponent("fonts/Arial.ttf"))
        try Data("<wnd/>".utf8).write(to: support.appendingPathComponent("Window/Menus/MainMenu.wnd"))
        try Data("dxvk.logLevel = none\n".utf8).write(to: support.appendingPathComponent("dxvk.conf"))
        try Data("StaticGameLOD = High\n".utf8).write(to: support.appendingPathComponent("DefaultOptions.ini"))
    }

    private func read(_ url: URL) -> String? { try? String(contentsOf: url, encoding: .utf8) }

    // MARK: Finding the game folder

    func testFindGameFolder() throws {
        let home = try TempHome()
        let picked = home.root.appendingPathComponent("Picked")
        let game = picked.appendingPathComponent("Games/Command and Conquer Generals Zero Hour")
        try BigWriter.makeGameFolder(at: game)
        XCTAssertEqual(GameDataValidator.findGameFolder(in: game)?.standardizedFileURL, game.standardizedFileURL, "the folder itself")
        XCTAssertEqual(GameDataValidator.findGameFolder(in: picked)?.standardizedFileURL, game.standardizedFileURL, "unique, two levels down")

        // Two candidates: ambiguous, the player has to pick.
        try BigWriter.makeGameFolder(at: picked.appendingPathComponent("Other ZH"))
        XCTAssertNil(GameDataValidator.findGameFolder(in: picked))

        // Too deep (more than three levels below the picked folder).
        let deepRoot = home.root.appendingPathComponent("Deep")
        try BigWriter.makeGameFolder(at: deepRoot.appendingPathComponent("a/b/c/ZH"))
        XCTAssertNil(GameDataValidator.findGameFolder(in: deepRoot))
        XCTAssertNotNil(GameDataValidator.findGameFolder(in: deepRoot.appendingPathComponent("a")))

        // Nothing at all.
        XCTAssertNil(GameDataValidator.findGameFolder(in: home.paths.documents))
    }

    func testRelativePath() {
        let parent = URL(fileURLWithPath: "/a/b")
        XCTAssertEqual(GameFolderStore.relativePath(of: URL(fileURLWithPath: "/a/b/c d/e"), below: parent), "c d/e")
        XCTAssertEqual(GameFolderStore.relativePath(of: parent, below: parent), "")
        XCTAssertEqual(GameFolderStore.relativePath(of: URL(fileURLWithPath: "/x"), below: parent), "")
    }

    // MARK: Bookmarks

    func testBookmarkRoundTripAndForget() throws {
        let home = try TempHome()
        let picked = home.root.appendingPathComponent("Files")
        let game = picked.appendingPathComponent("Zero Hour")
        try BigWriter.makeGameFolder(at: game)

        XCTAssertEqual(GameFolderAccess.open(paths: home.paths), .none)
        let reference = try GameFolderStore.makeReference(picked: picked, gameFolder: game)
        XCTAssertEqual(reference.subpath, "Zero Hour")
        XCTAssertEqual(reference.name, "Zero Hour")
        try GameFolderStore.save(reference, paths: home.paths)
        XCTAssertEqual(GameFolderStore.load(paths: home.paths), reference)

        guard case .open(let folder, _) = GameFolderAccess.open(paths: home.paths) else {
            return XCTFail("bookmark should resolve")
        }
        XCTAssertEqual(folder.resolvingSymlinksInPath().path, game.resolvingSymlinksInPath().path)

        // The folder disappears: unavailable, named.
        try FileManager.default.removeItem(at: game)
        if case .unavailable(let name, _) = GameFolderAccess.open(paths: home.paths) {
            XCTAssertEqual(name, "Zero Hour")
        } else {
            XCTFail("expected unavailable")
        }

        GameFolderStore.forget(paths: home.paths)
        XCTAssertEqual(GameFolderAccess.open(paths: home.paths), .none)
    }

    // MARK: iCloud

    func testGameFolderInDocumentsIsAdoptedUntilForgotten() throws {
        let home = try TempHome()
        let paths = home.paths
        XCTAssertNil(GameFolderStore.loadOrAdoptDocumentsFolder(paths: paths), "nothing in Documents")
        let game = paths.documents.appendingPathComponent("Command and Conquer Generals Zero Hour")
        try BigWriter.makeGameFolder(at: game)

        // Copied in with Finder: taken without a pick, and saved like a chosen folder.
        let adopted = try XCTUnwrap(GameFolderStore.loadOrAdoptDocumentsFolder(paths: paths))
        XCTAssertEqual(adopted.subpath, "Command and Conquer Generals Zero Hour")
        XCTAssertNotNil(GameFolderStore.load(paths: paths))
        guard case .open(let folder, _) = GameFolderAccess.open(paths: paths) else { return XCTFail("not opened") }
        XCTAssertEqual(folder.standardizedFileURL, game.standardizedFileURL)
        XCTAssertEqual(FolderLocation.of(folder, paths: paths), .appDocuments)

        // Forgotten: not taken again, until a different folder turns up.
        GameFolderStore.forget(paths: paths)
        XCTAssertNil(GameFolderStore.loadOrAdoptDocumentsFolder(paths: paths))
        XCTAssertEqual(GameFolderAccess.open(paths: paths), .none)
        try FileManager.default.moveItem(at: game, to: paths.documents.appendingPathComponent("ZH"))
        XCTAssertEqual(GameFolderStore.loadOrAdoptDocumentsFolder(paths: paths)?.subpath, "ZH")
    }

    func testICloudPlaceholders() throws {
        let home = try TempHome()
        let game = home.root.appendingPathComponent("iCloud ZH")
        try BigWriter.makeGameFolder(at: game)
        // INIZH.big not downloaded yet: only its placeholder is there.
        try FileManager.default.removeItem(at: game.appendingPathComponent("INIZH.big"))
        try Data().write(to: game.appendingPathComponent(".INIZH.big.icloud"))
        try Data().write(to: game.appendingPathComponent("ZH_Generals/.Music.big.icloud"))
        try Data().write(to: game.appendingPathComponent(".notes.txt.icloud"))  // not an archive

        XCTAssertEqual(UbiquitousFiles.placeholderTarget(".INIZH.big.icloud"), "INIZH.big")
        XCTAssertNil(UbiquitousFiles.placeholderTarget("INIZH.big"))
        XCTAssertTrue(GameDataValidator.isGameFolder(game), "a placeholder still marks the game folder")
        XCTAssertEqual(UbiquitousFiles.pendingArchives(in: game).map(\.lastPathComponent).sorted(), ["INIZH.big", "Music.big"])
        XCTAssertEqual(UbiquitousFiles.pendingArchives(in: home.root.appendingPathComponent("nope")), [])
    }

    // MARK: Location

    func testFolderLocation() {
        let paths = LauncherPaths(home: URL(fileURLWithPath: "/var/mobile/Containers/Data/Application/X"),
                                  bundledGameData: URL(fileURLWithPath: "/b/App.app/GameData"))
        XCTAssertEqual(FolderLocation.of(paths.documents.appendingPathComponent("ZH"), paths: paths), .appDocuments)
        XCTAssertEqual(FolderLocation.of(URL(fileURLWithPath: "/private/var/mobile/Library/Mobile Documents/com~apple~CloudDocs/ZH"), paths: paths), .iCloudDrive)
        XCTAssertEqual(FolderLocation.of(URL(fileURLWithPath: "/private/var/mobile/Library/LiveFiles/com.apple.filesystems.userfsd/USB/ZH"), paths: paths), .externalDrive("USB"))
        XCTAssertEqual(FolderLocation.of(URL(fileURLWithPath: "/private/var/mobile/Containers/Shared/AppGroup/U/File Provider Storage/ZH"), paths: paths), .onDevice)
        XCTAssertEqual(FolderLocation.of(URL(fileURLWithPath: "/somewhere/else"), paths: paths), .other)
    }

    // MARK: Support files

    func testSupportSyncWritesOnlyWhatDiffersAndNeverDeletes() throws {
        let home = try TempHome()
        try makeSupport(home.paths)
        let game = home.root.appendingPathComponent("ZH")
        try BigWriter.makeGameFolder(at: game)
        try FileManager.default.removeItem(at: game.appendingPathComponent("DefaultOptions.ini"))
        // The player's own files: an extra font and a changed dxvk.conf.
        try FileManager.default.createDirectory(at: game.appendingPathComponent("fonts"), withIntermediateDirectories: true)
        try Data("mine".utf8).write(to: game.appendingPathComponent("fonts/Mine.ttf"))
        try Data("dxvk.hud = fps\n".utf8).write(to: game.appendingPathComponent("dxvk.conf"))

        var result = SupportFileSync.sync(from: home.paths.bundledSupport, to: game)
        XCTAssertTrue(result.complete)
        XCTAssertEqual(result.written, ["DefaultOptions.ini", "Window/Menus/MainMenu.wnd", "dxvk.conf", "fonts/Arial.ttf"])
        XCTAssertEqual(read(game.appendingPathComponent("dxvk.conf")), "dxvk.logLevel = none\n", "different -> replaced")
        XCTAssertEqual(read(game.appendingPathComponent("fonts/Mine.ttf")), "mine", "player's files are never deleted")
        XCTAssertEqual(read(game.appendingPathComponent("Window/Menus/MainMenu.wnd")), "<wnd/>", "subfolders created")

        // Second run: nothing to do.
        result = SupportFileSync.sync(from: home.paths.bundledSupport, to: game)
        XCTAssertEqual(result.written, [])
        XCTAssertEqual(result.unchanged, 4)

        // Same size, different bytes: rewritten.
        try Data("font-b".utf8).write(to: game.appendingPathComponent("fonts/Arial.ttf"))
        XCTAssertEqual(SupportFileSync.sync(from: home.paths.bundledSupport, to: game).written, ["fonts/Arial.ttf"])
    }

    func testSupportSyncReadOnlyFolderAndMissingSupport() throws {
        let home = try TempHome()
        let game = home.root.appendingPathComponent("ReadOnly ZH")
        try BigWriter.makeGameFolder(at: game)
        XCTAssertFalse(SupportFileSync.sync(from: home.paths.bundledSupport, to: game).hadSupport)

        try makeSupport(home.paths)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: game.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: game.path) }
        let result = SupportFileSync.sync(from: home.paths.bundledSupport, to: game)
        XCTAssertTrue(result.hadSupport)
        XCTAssertFalse(result.complete)
        XCTAssertEqual(result.failed.count, 4)
    }

    // MARK: Whole preparation

    func testPrepareUsesChosenFolderSyncsSupportAndSeedsOptions() throws {
        let home = try TempHome()
        let paths = home.paths
        try makeSupport(paths)
        try BigWriter.makeGameFolder(at: paths.bundledGameData)
        let picked = home.root.appendingPathComponent("On My iPhone")
        let game = picked.appendingPathComponent("Command and Conquer Generals Zero Hour")
        try BigWriter.makeGameFolder(at: game)
        try GameFolderStore.save(try GameFolderStore.makeReference(picked: picked, gameFolder: game), paths: paths)

        let outcome = LaunchPreparation.prepare(paths: paths, preferences: LauncherPreferences(), safeInsets: nil)
        guard case .external(let url)? = outcome.source else { return XCTFail("expected the chosen folder, got \(String(describing: outcome.source))") }
        XCTAssertEqual(url.resolvingSymlinksInPath().path, game.resolvingSymlinksInPath().path)
        XCTAssertEqual(outcome.plan.value(of: "GX_GAME_DATA_DIR").map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path },
                       game.resolvingSymlinksInPath().path)
        XCTAssertEqual(outcome.support?.complete, true)
        XCTAssertNil(outcome.plan.value(of: "DXVK_CONFIG_FILE"))
        XCTAssertEqual(read(game.appendingPathComponent("fonts/Arial.ttf")), "font-a")
        XCTAssertEqual(read(paths.optionsIni), "StaticGameLOD = High\n", "Options.ini seeded from GameSupport")
    }

    func testPrepareFallsBackWhenChosenFolderIsNotUsable() throws {
        let home = try TempHome()
        let paths = home.paths
        try makeSupport(paths)
        try BigWriter.makeGameFolder(at: paths.bundledGameData)
        let game = home.root.appendingPathComponent("iCloud ZH")
        try BigWriter.makeGameFolder(at: game)
        try GameFolderStore.save(try GameFolderStore.makeReference(picked: game, gameFolder: game), paths: paths)

        // Still downloading from iCloud: not used, the developer build's bundled data is.
        try FileManager.default.removeItem(at: game.appendingPathComponent("W3DZH.big"))
        try Data().write(to: game.appendingPathComponent(".W3DZH.big.icloud"))
        var outcome = LaunchPreparation.prepare(paths: paths, preferences: LauncherPreferences(), safeInsets: nil)
        XCTAssertEqual(outcome.source, .bundled(paths.bundledGameData))
        XCTAssertEqual(outcome.pendingDownloads.map(\.lastPathComponent), ["W3DZH.big"])
        XCTAssertNil(outcome.support, "the read-only bundle gets no support files")

        // Gone: still the bundle; without one, nothing.
        try FileManager.default.removeItem(at: game)
        outcome = LaunchPreparation.prepare(paths: paths, preferences: LauncherPreferences(), safeInsets: nil)
        XCTAssertEqual(outcome.source, .bundled(paths.bundledGameData))
        if case .unavailable = outcome.folderState {} else { XCTFail("expected unavailable") }
        try FileManager.default.removeItem(at: paths.bundledGameData)
        outcome = LaunchPreparation.prepare(paths: paths, preferences: LauncherPreferences(), safeInsets: nil)
        XCTAssertNil(outcome.source)
    }

    func testPrepareReadOnlyFolderSetsFallbackEnvironment() throws {
        let home = try TempHome()
        let paths = home.paths
        try makeSupport(paths)
        let game = home.root.appendingPathComponent("Locked ZH")
        try BigWriter.makeGameFolder(at: game)
        try GameFolderStore.save(try GameFolderStore.makeReference(picked: game, gameFolder: game), paths: paths)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: game.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: game.path) }

        let outcome = LaunchPreparation.prepare(paths: paths, preferences: LauncherPreferences(), safeInsets: nil)
        guard case .external? = outcome.source else { return XCTFail("a read-only folder is still played from") }
        XCTAssertEqual(outcome.support?.complete, false)
        XCTAssertEqual(outcome.plan.value(of: "GENERALSX_BUNDLED_FONTS_DIR"), paths.bundledSupport.appendingPathComponent("fonts").path)
        XCTAssertEqual(outcome.plan.value(of: "DXVK_CONFIG_FILE"), paths.bundledSupport.appendingPathComponent("dxvk.conf").path)
    }

    func testPrepareWithNothingAvailable() throws {
        let home = try TempHome()
        let outcome = LaunchPreparation.prepare(paths: home.paths, preferences: LauncherPreferences(), safeInsets: nil)
        XCTAssertNil(outcome.source)
        XCTAssertNil(outcome.plan.value(of: "GX_GAME_DATA_DIR"))
        XCTAssertEqual(outcome.plan.value(of: "SDL_AUDIO_CATEGORY"), "playback")
        XCTAssertTrue(FileManager.default.fileExists(atPath: home.paths.settingsDir.path))
    }
}
