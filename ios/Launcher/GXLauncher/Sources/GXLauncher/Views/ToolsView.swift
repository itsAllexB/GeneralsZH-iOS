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

// GeneralsX @feature iOS launcher 25/10/2026 Tools: the log viewer, "Collect logs" (logging_off)
// and the diagnostics switches (gx_trace.txt, gx_perf.txt, gx_audio_trace.txt,
// gx_touch_debug.txt), all kept in GX_SETTINGS_DIR (SetupActivity.buildDiagnosticsSection).

#if canImport(UIKit) && os(iOS)
import SwiftUI
import GXLauncherCore

struct ToolsView: View {
    @ObservedObject var model: LauncherModel

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    LogViewerView(paths: model.paths)
                } label: {
                    Label {
                        SettingLabel(title: L("View logs"),
                                     detail: L("The game's log from the last session and the one before it. Share it with a bug report."))
                    } icon: {
                        Image(systemName: "doc.text.magnifyingglass")
                    }
                }
                Toggle(isOn: Binding(get: { model.collectLogs }, set: model.setCollectLogs)) {
                    SettingLabel(title: L("Collect logs"),
                                 detail: L("Write the game's log to the device. Turn off to keep nothing in the background; the logs stay off until you turn this back on. Needed for bug reports."))
                }
            } header: {
                Text(L("Logs"))
            }

            Section {
                ForEach(MarkerFile.diagnostics) { marker in
                    Toggle(isOn: Binding(
                        get: { model.diagnostics.contains(marker) },
                        set: { model.setDiagnostic(marker, $0) }
                    )) {
                        SettingLabel(title: Self.title(marker), detail: Self.detail(marker) + " (\(marker.rawValue))")
                    }
                }
            } header: {
                Text(L("Diagnostics"))
            } footer: {
                Text(L("These turn on extra logging for bug reports. Leave them all off for normal play: they can slow the game down or produce large logs. If someone asks you to turn one on, enable it, reproduce the problem, then share the log."))
            }

            Section {
                LabeledContent(L("Settings folder")) {
                    Text(model.paths.settingsDir.path)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .multilineTextAlignment(.trailing)
                }
            } header: {
                Text(L("Files"))
            }
        }
        .navigationTitle(L("Tools"))
        .navigationDestination(isPresented: $model.showLogs) {
            LogViewerView(paths: model.paths)
        }
    }

    static func title(_ marker: MarkerFile) -> String {
        switch marker {
        case .trace: return L("Verbose trace log")
        case .perf: return L("Performance summary")
        case .audioTrace: return L("Audio log")
        case .touchDebug: return L("Touch input overlay")
        case .loggingOff: return L("Collect logs")
        }
    }

    static func detail(_ marker: MarkerFile) -> String {
        switch marker {
        case .trace:
            return L("Very detailed internal logging (UI, fonts, INI files) for chasing a specific hang or bug. Can grow to a huge log over a long session.")
        case .perf:
            return L("One short line per second showing where frame time goes. Safe to leave on for a whole session; turn this on for FPS or slowdown reports.")
        case .audioTrace:
            return L("Records what the sound system is doing: music and speech buffers, movie audio, every sound that starts or stops.")
        case .touchDebug:
            return L("Draws the touch layer's state over the game: the current gesture, your finger, the pointer and the camera scroll anchor.")
        case .loggingOff:
            return ""
        }
    }
}
#endif
