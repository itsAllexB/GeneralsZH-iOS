# Command & Conquer Generals: Zero Hour — iPhone, iPad & iPhone Duo

The real 2003 Zero Hour engine running natively on iOS and iPadOS — no emulation.
DirectX 8 is translated to Vulkan by [DXVK](https://github.com/doitsujin/dxvk) and
to Metal by [MoltenVK](https://github.com/KhronosGroup/MoltenVK); SDL3 handles the
window, input and lifecycle.

This repository is the iOS-focused continuation of two earlier ports:

- the **Android port** ([MYSOREZ/GeneralsZH-Android-Port](https://github.com/MYSOREZ/GeneralsZH-Android-Port)),
  which this repo is forked from — its native touch controls, interface scaling,
  Extras menu and army column all carry over to iOS;
- the **macOS / iOS / iPadOS port** ([ammaarreshi/Generals-Mac-iOS-iPad](https://github.com/ammaarreshi/Generals-Mac-iOS-iPad)),
  which the Android port itself grew out of.

What this repo adds on top is everything needed to build and run on **iOS 27 /
Xcode 27** and on Apple's foldable **iPhone Duo**, plus a native iOS launcher.

**No game assets are included or distributed.** You need your own copy of
Zero Hour ([Steam](https://store.steampowered.com/app/2732960/)).

The Android documentation (online play, Android builds, the Android launcher) is
kept in [`README.android.md`](README.android.md).

## Status

| | |
|---|---|
| Tested on | iPhone Duo, iOS 27.2 (inner display, landscape) |
| Minimum iOS | 17.0 |
| Works | Main menu, skirmish matches, native touch controls (pan, zoom, selection, orders, command-bar buttons) |
| Not on iOS | GeneralsOnline multiplayer (the client is compiled in, but not set up or tested on iOS) |
| Launcher | Native SwiftUI launcher — see [Launcher](#launcher) |

## What's new compared to the earlier ports

- **iOS 27 SDK support.** Apps built with the iOS 27 SDK must use the UIScene life
  cycle or iOS terminates them at launch; the app now declares SDL's scene delegate.
  SDL3 is taken from its `release-3.4.x` branch, which fixes windows keeping a
  portrait size when launched in landscape and lost focus events with the iOS 27 SDK
  ([libsdl-org/SDL#16436](https://github.com/libsdl-org/SDL/issues/16436)).
- **iPhone Duo.** Built against the iOS 27.1 SDK the game fills the inner display.
  The inner display ignores orientation locks, so the app is resizable and allows
  all orientations; the engine always picks a landscape resolution.
- **Touch on letterboxed screens.** When the game's aspect ratio differs from the
  screen's, touches were mapped with a pixel density of 1 instead of the screen's
  (~2.8–3×), so taps landed at about a third of their position. Fixed in
  `dx8wrapper.cpp`.
- **Xcode 27.** DXVK builds with Xcode 27's libc++
  ([`Patches/dxvk-libcxx-xcode27.patch`](Patches/dxvk-libcxx-xcode27.patch), applied
  automatically like `dxvk-ios.patch`).
- **Android features on iOS.** The launcher settings the engine reads (control
  scheme, mouse mode, logging, managed mods) come from `$GX_SETTINGS_DIR` on iOS
  ([`GXSettingsPath.h`](Core/GameEngine/Include/Common/GXSettingsPath.h)), and the
  port's extra window layouts (army column, Extras menu) are bundled.
- **File picker.** The app no longer declares open-in-place: combined with file
  sharing it leaves the system document picker stuck on an empty Recents page in
  re-signed apps on iOS 27.2.
- **Apple Pencil** no longer also produces mouse events.
- **Native launcher** (see below), and the system allocator instead of the game's memory
  pool, which is not thread-safe and crashed Apple's text rendering inside the process.
- **iOS Simulator build** (optional, `cmake/triplets/arm64-ios-simulator.cmake`):
  it builds, but cannot render — the simulator's GPU lacks a Vulkan 1.2 feature
  DXVK requires.

## Touch controls

Battlefield input is native — a finger is not turned into a mouse. The gestures
come from the Android port:

| Gesture | Action |
|---|---|
| Tap on the map | Select what is under your finger, or — with units selected — give the order that point implies (move, attack, enter, repair …) |
| Double-tap | Select every unit of that type on screen |
| Drag | Pan the camera, with momentum |
| Press and hold, then drag | Selection box |
| Two fingers | Pan, pinch to zoom, twist to rotate |
| Long press on the map | Cancel an armed ability or a pending building; otherwise clear the selection |
| Two-finger tap | The same cancel |
| Tap / hold a UI button | Press it / read its description |
| With an ability armed: touch, drag, release | Aim it — the radius follows your finger; release fires; a second finger cancels |
| With a building picked: tap | Place it under your finger |
| Drag inside a list | Scroll it |
| Force-attack / waypoint buttons on the command bar | The touch equivalents of Ctrl-click and Alt-click |

Details: [`docs/port/TOUCH_CONTROLS.md`](docs/port/TOUCH_CONTROLS.md).

## Launcher

Before the game starts, a native SwiftUI launcher (source in [`ios/Launcher`](ios/Launcher))
lets you set up the game. It adapts to the screen: a tab bar on narrow screens, a sidebar
on iPad and the iPhone Duo's inner display.

- **Home** — Play; skip the intro movies; a check of the game data (every `.big` archive
  and the files the game needs at startup); import a game folder from Files.
- **Interface** — Interface Size (the in-game HUD, 100–200 %), Menu Text Size, and the
  control scheme (Classic, Tactical, or your own mix: attack-move, army buttons, higher camera).
- **Tools** — the game logs of the last two sessions, with search and Share; "Collect logs";
  diagnostics switches (trace, performance, audio, touch overlay).
- **Help** — about, license and credits.

Settings are written to `Options.ini` and to files the engine reads from
`Library/Application Support/GeneralsX/launcher`. How it plugs into the engine:
[`ios/Launcher/INTEGRATION.md`](ios/Launcher/INTEGRATION.md).

## Building

### Requirements (one time)

- A Mac with **Xcode 27.1 or later**, signed in with an Apple ID (free or paid
  developer account).
- Homebrew tools: `brew install cmake ninja meson pkgconf xcodegen`
- vcpkg, as a **full** clone (a shallow clone breaks manifest baselines):
  `git clone https://github.com/microsoft/vcpkg ~/vcpkg && ~/vcpkg/bootstrap-vcpkg.sh`
- The [LunarG Vulkan SDK](https://vulkan.lunarg.com/sdk/home) for macOS **with the
  iOS component** (it provides MoltenVK for iOS and `glslangValidator`).
- Your own Zero Hour game data in `~/GeneralsX/GeneralsZH` — for example with
  `./scripts/get-assets.sh <steam_username>` (needs `brew install --cask steamcmd`),
  or copied from an existing install (leave out `.exe` and `.dll` files).

In every shell you build from:

```sh
export VCPKG_ROOT=~/vcpkg
export VULKAN_SDK=~/VulkanSDK/<version>/macOS
export PATH="$VULKAN_SDK/bin:$PATH"   # DXVK's build needs glslangValidator
```

### Build and install

```sh
git clone https://github.com/itsAllexB/GeneralsZH-iOS.git && cd GeneralsZH-iOS
git submodule update --init --recursive references/fbraz3-dxvk   # --recursive: DXVK's Vulkan/SPIR-V headers
./scripts/build/ios/fetch-moltenvk.sh     # pinned MoltenVK.framework (checksummed)
./scripts/build/ios/stage-fonts.sh        # Liberation fonts, renamed as the game expects
cmake --preset ios-vulkan
cmake --build build/ios-vulkan --target z_generals
GX_TEAM_ID=<your team id> GX_BUNDLE_ID=com.you.generalszh \
    ./scripts/build/ios/package-ios-zh.sh --install
```

- Your team ID is in Xcode → Settings → Accounts. If your keychain holds more than
  one "Apple Development" certificate (for example a personal team and an
  organization), pick one with `GX_SIGN_IDENTITY=<SHA-1 from security find-identity -v -p codesigning>`.
- The game data (~2.7 GB) is copied into the app; `--dev` skips it for code-only
  iterations.
- With a free account the app expires after 7 days; a paid account gives a year.

## Known issues

- The game renders at the window's size at 2× and is scaled up to the screen, with
  thin bars where the aspect ratio differs. A native-resolution option is planned.
- Long sessions on iPad can be ended by iOS for memory (~3 GB resident); inherited
  from the earlier iOS port.
- Backgrounding mid-game can occasionally crash; save often.
- GeneralsOnline is not available on iOS.

## Lineage & credits

- **Westwood / EA Pacific** — the game; **EA** — the GPL v3 source release
- **[TheSuperHackers/GeneralsGameCode](https://github.com/TheSuperHackers/GeneralsGameCode)** —
  the community mainline, including the FFmpeg video and OpenAL audio work by
  **[feliwir](https://github.com/feliwir)**
- **[Fighter19/CnC_Generals_Zero_Hour](https://github.com/Fighter19/CnC_Generals_Zero_Hour)** —
  the original Unix/64-bit port and the DXVK approach
- **[fbraz3/GeneralsX](https://github.com/fbraz3/GeneralsX)** — the macOS/Linux port
- **[ammaarreshi/Generals-Mac-iOS-iPad](https://github.com/ammaarreshi/Generals-Mac-iOS-iPad)** —
  the macOS / iOS / iPadOS port
- **[MYSOREZ/GeneralsZH-Android-Port](https://github.com/MYSOREZ/GeneralsZH-Android-Port)** —
  the Android port this repository is forked from: native touch controls, launcher
  design, interface scaling, Extras menu, managed mods; with work credited there to
  **realkot**'s GeneralsX fork
- **[GeneralsOnline Development Team](https://github.com/GeneralsOnlineDevelopmentTeam)** — GeneralsOnline
- **DXVK, MoltenVK, SDL, OpenAL Soft, FFmpeg, Liberation Fonts** — the load-bearing walls

## License

Engine code: **GPL v3** with EA's additional terms (see [`LICENSE.md`](LICENSE.md)).
This is a **modified version** of the original source release. Game assets and EA
artwork are not included and not licensed here; Command & Conquer and Generals are
trademarks of Electronic Arts.
