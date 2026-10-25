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

// GeneralsX @feature iOS launcher 25/10/2026 The launcher's shell. It adapts to the horizontal size
// class, never to the device model: compact width (iPhone portrait, small iPhones in landscape)
// gets a tab bar; regular width (iPad, large iPhones in landscape, the iPhone Duo's inner display)
// gets a sidebar. Adding a section later (Mods, Languages) is one case in LauncherModel.Section
// plus one branch in `content(for:)`.

#if canImport(UIKit) && os(iOS)
import SwiftUI
import GXLauncherCore

struct LauncherRootView: View {
    @ObservedObject var model: LauncherModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                sidebarLayout
            } else {
                tabLayout
            }
        }
        .onAppear { model.validate() }
        .alert(L("Could not save the setting"), isPresented: Binding(
            get: { model.saveError != nil },
            set: { if !$0 { model.saveError = nil } }
        )) {
            Button(L("OK"), role: .cancel) {}
        } message: {
            Text(model.saveError ?? "")
        }
    }

    // MARK: Compact: tab bar

    private var tabLayout: some View {
        TabView(selection: $model.section) {
            ForEach(LauncherModel.Section.allCases) { section in
                NavigationStack {
                    content(for: section)
                }
                .tabItem { Label(section.title, systemImage: section.symbol) }
                .tag(section)
            }
        }
    }

    // MARK: Regular: sidebar

    private var sidebarSelection: Binding<LauncherModel.Section?> {
        Binding(get: { model.section }, set: { if let s = $0 { model.section = s } })
    }

    private var sidebarLayout: some View {
        NavigationSplitView {
            List(selection: sidebarSelection) {
                ForEach(LauncherModel.Section.allCases) { section in
                    NavigationLink(value: section) {
                        Label(section.title, systemImage: section.symbol)
                    }
                }
            }
            .navigationTitle(LauncherInfo.appName)
            .safeAreaInset(edge: .bottom) {
                // Home has its own big Play button; elsewhere keep one in reach.
                if model.section != .home {
                    PlayButton(model: model, compact: true)
                        .padding()
                }
            }
        } detail: {
            NavigationStack {
                content(for: model.section)
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private func content(for section: LauncherModel.Section) -> some View {
        switch section {
        case .home: HomeView(model: model)
        case .interface: InterfaceView(model: model)
        case .tools: ToolsView(model: model)
        case .help: HelpView()
        }
    }
}

/// App name and version from the host bundle (the engine's Info.plist in the real app).
enum LauncherInfo {
    static var appName: String {
        let info = Bundle.main.infoDictionary
        return (info?["CFBundleDisplayName"] as? String) ?? (info?["CFBundleName"] as? String) ?? "GeneralsX"
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = (info?["CFBundleShortVersionString"] as? String) ?? "?"
        let build = (info?["CFBundleVersion"] as? String) ?? "?"
        return "\(short) (\(build))"
    }
}
#endif
