# Command & Conquer Generals: Zero Hour — iPhone, iPad & iPhone Duo

The real 2003 Zero Hour engine running natively on iOS and iPadOS — no emulation.
**Optimized for the iPhone Duo**: full-screen on its inner display, with touch controls,
interface sizing and a launcher made for it — and it runs on other iPhones and iPads too.

DirectX 8 is translated to Vulkan by [DXVK](https://github.com/doitsujin/dxvk) and to Metal
by [MoltenVK](https://github.com/KhronosGroup/MoltenVK); SDL3 handles the window, input and
lifecycle. This repository continues the
**Android port** ([MYSOREZ/GeneralsZH-Android-Port](https://github.com/MYSOREZ/GeneralsZH-Android-Port)),
which it is forked from, and the earlier
**macOS / iOS / iPadOS port** ([ammaarreshi/Generals-Mac-iOS-iPad](https://github.com/ammaarreshi/Generals-Mac-iOS-iPad))
that the Android port grew out of.

**No game assets are included or distributed.** You need your own copy of Zero Hour
([Steam](https://store.steampowered.com/app/2732960/)): copy its folder to the device and
choose it in the launcher.

## Features

- **Optimized for the iPhone Duo** — fills the inner display in landscape, ProMotion
  120 fps, an interface you can size from 70 % to 200 %, and a launcher with a sidebar
  layout for the wide screen.
- **Native touch controls** — tap to select and order, drag to pan with momentum, pinch to
  zoom, twist to rotate, hold-and-drag for a selection box, aim abilities with your finger,
  and a minimap you can tap or drag to move the camera (see [Touch controls](#touch-controls)).
- **60 fps gameplay** — the game simulates at 60 Hz (the Windows GeneralsOnline rate);
  **120 fps** drawing on ProMotion screens.
- **Native iOS launcher** — choose your game folder, check the game data, player name,
  interface size, control scheme (Classic / Tactical / your own mix), frame rate, sound in
  silent mode, logs and diagnostics (see [Launcher](#launcher)).
- **Back to the launcher** — Exit Game, or **QUIT TO LAUNCHER** in the pause menu, opens the
  launcher over the running game; Play takes you back.
- **Your game folder stays yours** — the app is ~22 MB; it reads Zero Hour from a folder on
  the device (copied with Finder, or anywhere in Files).
- **Game sound in silent mode** (on by default), and system edge swipes that need a second
  swipe, so a palm on the edge doesn't interrupt a match.
- **Landscape** on iPhones and iPads (both directions); the iPhone Duo's inner display, which
  ignores orientation locks, keeps every orientation.

## Install

1. Download `GeneralsZH-iOS.ipa` from the [Releases](https://github.com/itsAllexB/GeneralsZH-iOS/releases)
   page.
2. Install it with a sideloading tool that signs it with your own Apple ID — SideStore,
   AltStore, Sideloadly, LiveContainer — or build and sign it yourself (see [Building](#building)).
3. Copy your Zero Hour folder to the device (see [Game data](#game-data)), open **Generals ZH**
   and tap **Play**.

Requires iOS 17 or later.

## Status

| | |
|---|---|
| Version | 1.0 |
| Tested on | iPhone Duo, iOS 27.2 (inner display, landscape) |
| Should work | Other iPhones and iPads on iOS 17+ (not tested yet) |
| Works | Main menu, skirmish matches, native touch controls, launcher, 60/120 fps |
| Not on iOS | GeneralsOnline multiplayer (the client is compiled in, but not set up or tested on iOS) |

The Android documentation (online play, Android builds, the Android launcher) is kept in
[`README.android.md`](README.android.md).

## Under the hood — changes compared to the earlier ports

- **iOS 27 SDK support.** Apps built with the iOS 27 SDK must use the UIScene life
  cycle or iOS terminates them at launch; the app declares SDL's scene delegate.
  SDL3 is taken from its `release-3.4.x` branch, which fixes windows keeping a
  portrait size when launched in landscape and lost focus events with the iOS 27 SDK
  ([libsdl-org/SDL#16436](https://github.com/libsdl-org/SDL/issues/16436)).
- **iPhone Duo.** Built against the iOS 27.1 SDK the game fills the inner display. The
  inner display ignores orientation locks, so Info.plist allows every orientation and the
  launcher limits every other device to landscape at run time (`SDL_IOS_ORIENTATIONS`); the
  engine always picks a landscape resolution.
- **System edge gestures deferred** (`SDL_HINT_IOS_HIDE_HOME_INDICATOR=2`): a finger or palm
  resting on an edge made iOS start a home / Control Center swipe and took the game out of
  the active state for seconds at a time.
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
- **60 Hz simulation** (`SAGE_HIGH_FPS_SIM`, the Android port's "60 fps" build): replays
  recorded by the original 30 Hz game do not play back on it. **120 fps** draws at least
  120 frames a second while the logic keeps the frame limit's rate (`FramePacer`).
- **Launcher over the running game.** The engine is started once per process (it keeps
  statics that only hold for its first start); leaving the game shows the launcher on
  top, and the settings readers pick up its changes.
- **File picker.** The app does not declare open-in-place: combined with file
  sharing it leaves the system document picker stuck on an empty Recents page in
  re-signed apps on iOS 27.2.
- **Apple Pencil** no longer also produces mouse events.
- **System allocator** instead of the game's memory pool, which is not thread-safe and
  crashed Apple's text rendering inside the process.
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
| Tap / drag on the minimap | With units selected: a move order there. With **Minimap moves camera** on (Interface › Control scheme): the camera jumps there and follows your finger |
| Force-attack / waypoint buttons on the command bar | The touch equivalents of Ctrl-click and Alt-click |

Details: [`docs/port/TOUCH_CONTROLS.md`](docs/port/TOUCH_CONTROLS.md).

## Launcher

Before the game starts, a native SwiftUI launcher (source in [`ios/Launcher`](ios/Launcher))
lets you set up the game. It adapts to the screen: a tab bar on narrow screens, a sidebar
on iPad and the iPhone Duo's inner display.

- **Home** — Play; **Choose game folder** (see below) with a check of the game data (every
  `.big` archive and the files the game needs at startup); **Player Name** (skirmish and
  LAN, up to 12 characters); skip the intro movies; **Play
  sound in silent mode** (on by default — off follows the ring/silent switch); **Allow
  higher camera**; **Frame Rate** 60 or 120 fps (120 on ProMotion screens: the game still
  updates 60 times a second, scrolling and animation are drawn at 120).
- **Interface** — Interface Size (the in-game HUD and menus, 70–200 %), Menu Text Size, and the
  control scheme (Classic, Tactical, or your own mix of attack-move, army buttons and
  **Minimap moves camera** — tap the minimap to jump there, drag on it to scroll).
- **Tools** — the game logs of the last two sessions, with search and Share; "Collect logs";
  diagnostics switches (trace, performance, audio, touch overlay).
- **Help** — about, license and credits.

### Game data

- **From a computer (easiest):** connect the device, open it in Finder (Windows: the
  Apple Devices app), and drag your Zero Hour folder (the one with `INIZH.big`,
  `Music.big` …) onto **Generals ZH** in its **Files** tab. The launcher finds it there on
  its own — nothing to pick.
- **On the device:** put the folder anywhere under **Files › On My iPhone** (not in the
  app's own folder, which iOS doesn't show in Files — see below), then **Choose game
  folder…** in the launcher. Picking a folder above it works too; the launcher looks up to
  three levels down. Keep it out of iCloud Drive if you can: archives iCloud has offloaded
  have to download again before the game can start.

Either way the launcher remembers the folder, checks it, and copies the port's own support
files (fonts, extra window layouts, `dxvk.conf`) into it. Nothing in the folder is deleted.

Why the app's folder is not in Files: that needs `LSSupportsOpeningDocumentsInPlace`, and
together with Finder file sharing it leaves the document picker of development-signed
apps stuck on an empty Recents page on iOS 27.2.

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
- Your own Zero Hour game data — for example with
  `./scripts/get-assets.sh <steam_username>` (needs `brew install --cask steamcmd`),
  or copied from an existing install (leave out `.exe` and `.dll` files). It goes onto the
  device separately (see [Game data](#game-data)); only `--with-data` builds bundle it from
  `~/GeneralsX/GeneralsZH`.

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
- The app is about 22 MB and has no game data; choose your folder in the launcher.
  `--with-data` copies `~/GeneralsX/GeneralsZH` (~2.7 GB) into the app instead.
- `--install` uses the first paired iPhone or iPad (USB or Wi-Fi); `GX_DEVICE=<name or id>`
  picks another.
- With a free account the app expires after 7 days; a paid account gives a year.
- Release builds: `GX_GIT_AUTHOR_NAME=<name>` replaces the last commit's author in the game's
  version text.

### Unsigned IPA (for SideStore, AltStore, LiveContainer …)

```sh
./scripts/build/ios/package-ios-zh.sh --unsigned --ipa
```

Writes `build/ios-package/GeneralsZH-iOS.ipa`: ad-hoc signed, no provisioning profile, no
game data. The sideloading tool signs it with your own account. Ready-made IPAs are on the
[Releases](https://github.com/itsAllexB/GeneralsZH-iOS/releases) page.

## Known issues

- The game renders at the screen's native resolution, which is a lot of pixels for older
  iPhones; a lower render resolution option is planned. Only the iPhone Duo has been
  tested so far — other iPhones and iPads should adapt (the resolution, interface and touch
  follow the screen), but are unverified.
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
