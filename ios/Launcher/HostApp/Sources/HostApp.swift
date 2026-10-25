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

// GeneralsX @feature iOS launcher 25/10/2026 Test host for GXLauncher. It reproduces the engine's
// start-up on iOS and then shows what gx_launcher_run() produced:
//
//   1. HostSceneDelegate, like SDL3's SDLUIKitSceneDelegate, puts up a launch window at
//      UIWindowLevelNormal + 1 when the scene connects and schedules "main" with
//      performSelector:afterDelay:0 -- a run-loop timer, not a main-queue block.
//   2. hostMain() calls the C function gx_launcher_run() (via the bridging header), which shows
//      the launcher and returns once Play is tapped.
//   3. The host collects the returned arguments, the GX_* environment and the files written, shows
//      them, prints them to stderr and saves them as Documents/host_result.json for scripted checks.

import SwiftUI
import UIKit

@main
final class HostAppDelegate: UIResponder, UIApplicationDelegate {}

final class HostSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var started = false

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene, !started else { return }
        started = true
        // SDL's launch-screen window.
        let launch = UIWindow(windowScene: windowScene)
        launch.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.normal.rawValue + 1)
        launch.rootViewController = UIHostingController(rootView: StartingView())
        launch.makeKeyAndVisible()
        window = launch
        // SDL: [self performSelector:@selector(postFinishLaunch) withObject:nil afterDelay:0.0]
        perform(#selector(hostMain), with: nil, afterDelay: 0)
    }

    /// Stands in for the engine's main().
    @objc private func hostMain() {
        let result = HostResult.runLauncher()
        guard let scene = window?.windowScene else { return }
        let resultWindow = UIWindow(windowScene: scene)
        resultWindow.rootViewController = UIHostingController(rootView: ResultView(initial: result))
        resultWindow.makeKeyAndVisible()
        window?.isHidden = true
        window = resultWindow
    }
}

struct StartingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Starting…").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
    }
}

/// Everything the launcher handed over.
struct HostResult: Codable, Equatable {
    var arguments: [String]
    var environment: [String: String]
    var optionsIni: String?
    var settingsFiles: [String: String]
    var runCount: Int

    static let variables = ["GX_SETTINGS_DIR", "GX_GAME_DATA_DIR", "GX_UI_SCALE",
                            "GX_TRACE", "GX_PERF", "GX_AUDIO_TRACE", "GX_TOUCH_DEBUG"]
    private static var runs = 0

    /// Calls gx_launcher_run() and records what it produced.
    static func runLauncher() -> HostResult {
        runs += 1
        let argv = gx_launcher_run()
        var arguments: [String] = []
        if let argv {
            var index = 0
            while let arg = argv[index] {
                arguments.append(String(cString: arg))
                index += 1
            }
        }
        var environment: [String: String] = [:]
        for name in variables {
            if let value = getenv(name) { environment[name] = String(cString: value) }
        }
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let options = home.appendingPathComponent("Library/Application Support/GeneralsX/GeneralsZH/Options.ini")
        var files: [String: String] = [:]
        if let dir = environment["GX_SETTINGS_DIR"],
           let names = try? FileManager.default.contentsOfDirectory(atPath: dir) {
            for name in names.sorted() {
                let data = FileManager.default.contents(atPath: dir + "/" + name) ?? Data()
                files[name] = String(decoding: data, as: UTF8.self)
            }
        }
        let result = HostResult(arguments: arguments, environment: environment,
                                optionsIni: try? String(contentsOf: options, encoding: .utf8),
                                settingsFiles: files, runCount: runs)
        result.save(home: home)
        return result
    }

    private func save(home: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self) else { return }
        let docs = home.appendingPathComponent("Documents")
        try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        try? data.write(to: docs.appendingPathComponent("host_result.json"))
        fputs("[GX-Host] result:\n\(String(decoding: data, as: UTF8.self))\n", stderr)
    }
}

/// The plain screen listing the result.
struct ResultView: View {
    @State var result: HostResult

    init(initial: HostResult) {
        _result = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Extra arguments (\(result.arguments.count))") {
                    if result.arguments.isEmpty {
                        Text("none").foregroundStyle(.secondary)
                    }
                    ForEach(Array(result.arguments.enumerated()), id: \.offset) { _, arg in
                        Text(arg).font(.body.monospaced())
                    }
                }
                Section("Environment") {
                    ForEach(HostResult.variables, id: \.self) { name in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name).font(.caption.weight(.semibold))
                            Text(result.environment[name] ?? "(unset)")
                                .font(.caption.monospaced())
                                .foregroundStyle(result.environment[name] == nil ? .secondary : .primary)
                                .textSelection(.enabled)
                        }
                    }
                }
                Section("GX_SETTINGS_DIR files") {
                    if result.settingsFiles.isEmpty {
                        Text("none").foregroundStyle(.secondary)
                    }
                    ForEach(result.settingsFiles.keys.sorted(), id: \.self) { name in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name).font(.caption.weight(.semibold))
                            let content = result.settingsFiles[name] ?? ""
                            Text(content.isEmpty ? "(empty)" : content)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Options.ini") {
                    Text(result.optionsIni ?? "(missing)")
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
                Section {
                    Button("Run launcher again") {
                        // Like SDL, call it from a run-loop timer -- not from inside this SwiftUI
                        // action, which would nest the launcher inside SwiftUI's own event handling.
                        Timer.scheduledTimer(withTimeInterval: 0, repeats: false) { _ in
                            result = HostResult.runLauncher()
                        }
                    }
                }
            }
            .navigationTitle("Launcher result #\(result.runCount)")
        }
    }
}
