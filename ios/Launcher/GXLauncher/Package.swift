// swift-tools-version:5.9
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

// GeneralsX @feature iOS launcher 25/10/2026 The native SwiftUI launcher for the iOS port.
//
//   GXLauncherCore  Foundation-only settings contract: Options.ini editing, control_scheme,
//                   marker files, the BIG archive validator, the extra-argument builder and the
//                   game-data importer. No UIKit, so it is unit-testable anywhere.
//   GXLauncher      SwiftUI screens, the UIWindow runner and the C entry point
//                   gx_launcher_run() (declared in include/gx_launcher.h).
//
// The single product is a STATIC library so the CMake-built engine can link it directly; see
// ../INTEGRATION.md.

import PackageDescription

let package = Package(
    name: "GXLauncher",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v16),
        // macOS only so `swift test` can run the Foundation-only core on the build machine.
        .macOS(.v13),
    ],
    products: [
        .library(name: "GXLauncher", type: .static, targets: ["GXLauncher", "GXLauncherCore"]),
    ],
    targets: [
        .target(
            name: "GXLauncherCore",
            path: "Sources/GXLauncherCore"
        ),
        .target(
            name: "GXLauncher",
            dependencies: ["GXLauncherCore"],
            path: "Sources/GXLauncher",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "GXLauncherCoreTests",
            dependencies: ["GXLauncherCore"],
            path: "Tests/GXLauncherCoreTests"
        ),
    ]
)
