# GXLauncher: linking the native iOS launcher into the engine

GXLauncher is a SwiftUI launcher (Home / Interface / Tools / Help) shown **before** the engine
starts. The engine calls one C function, the player taps Play, and the function returns the extra
command-line arguments. Along the way it sets environment variables and writes the settings files
the engine reads.

```
ios/Launcher/
  GXLauncher/                 Swift package (iOS 16+, no dependencies), static library product
    include/gx_launcher.h     the C API
    Sources/GXLauncherCore/   Foundation-only logic (Options.ini, control_scheme, BIG validator, ...)
    Sources/GXLauncher/       SwiftUI screens, the UIWindow runner, @_cdecl entry point
    Sources/GXLauncher/Resources/Localizable.xcstrings   String Catalog (English)
    Tests/GXLauncherCoreTests/  53 XCTest cases
  HostApp/                    XcodeGen test host that calls gx_launcher_run() the way SDL does
  scripts/                    run-host.sh, make-fake-gamedata.py, gen-strings.py
  screenshots/                simulator screenshots (iPhone 18 Pro Max, iOS 27.0)
```

## 1. The C API

```c
#include "gx_launcher.h"
const char *const *gx_launcher_run(void);
```

* **When:** in the iOS branch of `main()` (SDL_main) in `GeneralsMD/Code/Main/SDL3Main.cpp`,
  before SDL video init. Call it **first thing in the `TARGET_OS_IPHONE` block, before the
  stderr mirror** (see section 5) so that the log viewer shows the last game session as
  "Last session" and `logging_off` can be honoured.
* **Thread:** the main thread, from a run-loop callout. SDL3 already calls SDL_main that way
  (`performSelector:@selector(postFinishLaunch) afterDelay:0` from `SDLUIKitSceneDelegate`).
  Do **not** call it from inside a block on the main dispatch queue (the nested run loop cannot
  drain the main queue; a warning is printed) or from inside a UIKit/SwiftUI action handler
  (SwiftUI does not deliver a nested button action, so Play never fires -- reproduced in the host).
* **Scenes:** safe to call before any scene is active: it spins the run loop until a
  `UIWindowScene` is foreground-active (or foreground-inactive for 3 s), puts its own `UIWindow`
  (level `normal + 2`, above SDL's launch window) on it, spins default + `UITrackingRunLoopMode`
  like `UIKit_PumpEvents()` until Play, then hides and releases the window before returning.
* **Return value:** NULL-terminated array of NUL-terminated UTF-8 strings, never NULL, e.g.
  `{ "-gxSafeInsets", "0.0649,0.0000,0.0649,0.0773", "-nologo", NULL }`.
* **Memory:** owned by GXLauncher, valid until the next call of `gx_launcher_run()` (which frees
  the previous array) or process exit. Do not free or modify. Pointing argv entries at them is fine.
* **Off the main thread:** shows no UI, applies the saved settings and returns (no safe insets).
* **Development switches:** `GX_LAUNCHER_SKIP=1` (no UI, saved settings only),
  `GX_LAUNCHER_SECTION=home|interface|tools|help|logs` (open on that screen).

Example for SDL3Main.cpp (iOS block):

```cpp
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
#include "gx_launcher.h"
...
	// Before the stderr mirror and before chdir(): shows the launcher, sets GX_* env vars.
	{
		const char *const *extra = gx_launcher_run();
		static std::vector<char *> merged;
		merged.assign(__argv, __argv + __argc);
		for (int i = 0; extra[i] != nullptr; ++i)
			merged.push_back(const_cast<char *>(extra[i]));
		merged.push_back(nullptr);
		__argv = merged.data();
		__argc = (int)merged.size() - 1;
	}
#endif
```

Note the existing `-xres/-yres` injection later builds `newArgv[64]` from `__argv`/`__argc`, so it
picks the launcher's arguments up automatically (59 slots is plenty).

## 2. Building and linking the static library

### Option A: `swift build` (recommended for CMake; produces a real `.a`)

```sh
cd ios/Launcher/GXLauncher
swift build -c release --product GXLauncher \
  --triple arm64-apple-ios16.0 \
  --sdk "$(xcrun --sdk iphoneos --show-sdk-path)" \
  --scratch-path <builddir>/gxlauncher
# -> <builddir>/gxlauncher/out/Products/Release-iphoneos/libGXLauncher.a            (~1.4 MB, arm64)
# -> <builddir>/gxlauncher/out/Products/Release-iphoneos/GXLauncher_GXLauncher.bundle
```

For the simulator use `--triple arm64-apple-ios16.0-simulator --sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)"`.
(Verified 25/10/2026 with Xcode 27.1 / Swift 6.4: the output path is `out/Products/Release-iphoneos`.)

### Option B: `xcodebuild`

```sh
xcodebuild -scheme GXLauncher -destination 'generic/platform=iOS' -configuration Release \
  -derivedDataPath <builddir>/dd build
# Produces GXLauncher.o + GXLauncherCore.o (one merged object per target), not a .a:
libtool -static -o libGXLauncher.a <builddir>/dd/Build/Products/Release-iphoneos/GXLauncher{,Core}.o
```

### Linking from CMake

The archive's objects carry Swift autolink entries (`-lswiftCore`, `-lswift_Concurrency`,
`-lswiftUIKit`, `-lswiftCompatibilityPacks`, ...). A clang/clang++ link needs the two Swift library
search paths so ld can resolve them; nothing has to be listed by hand. Verified with a C++ test
program linked by `clang++ -target arm64-apple-ios16.0`:

```cmake
# iOS only
execute_process(COMMAND xcrun --sdk iphoneos --show-sdk-path OUTPUT_VARIABLE GX_IOS_SDK OUTPUT_STRIP_TRAILING_WHITESPACE)
execute_process(COMMAND xcrun --sdk iphoneos --find swiftc OUTPUT_VARIABLE GX_SWIFTC OUTPUT_STRIP_TRAILING_WHITESPACE)
get_filename_component(GX_TOOLCHAIN_USR "${GX_SWIFTC}/../.." ABSOLUTE)

set(GXL_DIR  ${CMAKE_SOURCE_DIR}/ios/Launcher/GXLauncher)
set(GXL_OUT  ${CMAKE_BINARY_DIR}/gxlauncher/out/Products/Release-iphoneos)
add_custom_command(
  OUTPUT ${GXL_OUT}/libGXLauncher.a
  COMMAND swift build -c release --product GXLauncher
          --triple arm64-apple-ios16.0 --sdk ${GX_IOS_SDK}
          --scratch-path ${CMAKE_BINARY_DIR}/gxlauncher
  WORKING_DIRECTORY ${GXL_DIR}
  COMMENT "Building GXLauncher (Swift)")
add_custom_target(gxlauncher_build DEPENDS ${GXL_OUT}/libGXLauncher.a)

add_library(GXLauncher STATIC IMPORTED)
set_target_properties(GXLauncher PROPERTIES
  IMPORTED_LOCATION ${GXL_OUT}/libGXLauncher.a
  INTERFACE_INCLUDE_DIRECTORIES ${GXL_DIR}/include)
add_dependencies(GXLauncher gxlauncher_build)

target_link_libraries(z_generals PRIVATE
  "-Wl,-force_load,${GXL_OUT}/libGXLauncher.a"      # keep all Swift metadata/conformances
  "-L${GX_IOS_SDK}/usr/lib/swift"
  "-L${GX_TOOLCHAIN_USR}/lib/swift/iphoneos"         # libswiftCompatibilityPacks.a lives here
  "-Wl,-rpath,/usr/lib/swift")
# and copy the resource bundle into the .app root (package-ios.sh):
#   cp -R ${GXL_OUT}/GXLauncher_GXLauncher.bundle <App>.app/
```

Swift runtime notes:

* iOS 16+ ships the Swift runtime and `libswift_Concurrency.dylib` in the OS (`/usr/lib/swift`),
  so nothing is embedded in the app and no `-lswiftCore` has to be added by hand (the autolink
  entries do it). The only static back-deploy library pulled in is `libswiftCompatibilityPacks.a`
  from the toolchain, hence the second `-L`.
* Optional OS overlays (`libswiftCoreAudio`, `libswiftSpatial`, `libswiftXPC`, ...) are linked
  weak; `libswiftObservation` is dead-stripped (unused). Check the final binary with
  `otool -L` once: every `/usr/lib/swift/*.dylib` must exist on iOS 16 or be marked `weak`.
* `-force_load` is belt and braces: Swift type metadata/protocol conformances in objects that
  are not referenced by a symbol could otherwise be dropped by the static-archive rules.
* The engine must link `SwiftUI`, `UIKit`, `UniformTypeIdentifiers`, `Combine` frameworks; the
  autolink entries add them, so nothing extra is needed when linking with clang.
* `package-ios.sh` re-signs the app; the resource bundle has no code, it only needs copying.
  Without the bundle the UI still works: every string key is its English text.

## 3. Environment variables set before `gx_launcher_run()` returns

| Variable | When | Value | Engine reader |
|---|---|---|---|
| `GX_SETTINGS_DIR` | always (created if missing) | `$HOME/Library/Application Support/GeneralsX/launcher` | control_scheme, mouse_mode, logging_off, mods_active.txt (engine side, per coordinator) |
| `GX_GAME_DATA_DIR` | when any game data is available | by priority: the folder chosen in Files > `$HOME/Library/Application Support/GeneralsX/ImportedGameData` > `<App>.app/GameData` (dev builds); see section 3a | SDL3Main.cpp `chdir()`s here |
| `GX_UI_SCALE` | Options.ini has `GXUiScale` and it is not 100 | clamped to 70..200, e.g. `70`, `140` | `GXUiScale::userScale()` (accepts 70..300, shrinks below 100) |
| `GX_TRACE` | Tools > Verbose trace log on | `1` | GXTrace.h (also checks `gx_trace.txt` in CWD) |
| `GX_PERF` | Tools > Performance summary on | `1` | GXTrace.h |
| `GX_AUDIO_TRACE` | Tools > Audio log on | `1` | GXTrace.h |
| `GX_TOUCH_DEBUG` | Tools > Touch input overlay on | `1` | SDL3GameEngine.cpp `touchDebugEnabled()` |
| `SDL_AUDIO_CATEGORY` | always | `playback` (Home > Play sound in silent mode, default ON) or `ambient` | SDL3 audio (UIKit backend) |
| `GENERALSX_BUNDLED_FONTS_DIR` | only when the support files could not be copied into the game folder | `<App>.app/GameSupport/fonts` | render2dsentence.cpp (searched after the game folder's `fonts/`) |
| `DXVK_CONFIG_FILE` | same | `<App>.app/GameSupport/dxvk.conf` | DXVK |

Before returning, `gx_launcher_run()` also configures the audio session (errors are logged, the
launch never fails): sound in silent mode ON -> `AVAudioSession.setCategory(.playback, mode:
.default, options: [.mixWithOthers])` + `setActive(true)`; OFF -> `.ambient` (respects the
Ring/Silent switch, mixes).

## 3a. Game data: where it comes from

The published IPA ships **without** game data. The bundle carries `<App>.app/GameSupport/`
(`fonts/*.ttf`, `Window/**/*.wnd`, `dxvk.conf`, `DefaultOptions.ini`: the port's files the engine
expects inside the game folder); developer builds may still carry `<App>.app/GameData/`.

Priority for `GX_GAME_DATA_DIR` (`LaunchPlanBuilder.gameDataSource`, `LaunchPreparation.prepare`):

1. **The folder chosen in Files** (Home > Game folder > Choose game folder…) -- used when its
   bookmark resolves, the folder exists, it has INIZH.big or INI.big at the top, and no `.big`
   archive is still waiting for iCloud Drive. Integrity problems (missing base archives, ...) do
   not disqualify it; Play asks "Play anyway?" as before.
2. **The copy inside the app** (Home > Copy into the app instead) in `ImportedGameData/`.
3. **`<App>.app/GameData`** (developer builds).

With none of them, Play is disabled and Home explains how to get the data (own copy of Zero Hour,
copy the game folder to Files › On My iPhone, Choose game folder).

**Choosing a folder.** `UIDocumentPickerViewController(forOpeningContentTypes: [.folder],
asCopy: false)`. The picked folder may be the game folder or a parent of it: like Android's
`findGameFolderBelow()`, the only game folder within three levels below is used (none or several
-> "Not a game folder" alert, nothing saved).

**Bookmark.** `$GX_SETTINGS_DIR/game_folder.json` = `{"bookmark": <base64>, "subpath": "<game folder
below the picked folder>", "name": "<game folder name>"}`. The bookmark is a plain
`URL.bookmarkData()` of the security-scoped *picked* URL (iOS has no `.withSecurityScope`; a plain
bookmark from a security-scoped URL carries the access). On every launch it is resolved, and
`startAccessingSecurityScopedResource()` is called once per process and **never stopped**: the
engine reads the data with POSIX `fopen()` for the life of the process, which the sandbox
extension covers. A stale bookmark is re-created and saved. If the folder is gone or the bookmark
does not resolve, Home shows "cannot be opened" with Change…/Forget, and the next source is used.

**iCloud Drive.** Archives that are not downloaded (`ubiquitousItemDownloadingStatus` != `.current`,
or old-style `.Name.big.icloud` placeholders) in the folder and its immediate subfolders are
requested with `startDownloadingUbiquitousItem`; Home shows "Waiting for iCloud Drive" with an
"n of m archives" progress (polled every 2 s) and Play stays on the next source / disabled until
all are local. The UI recommends a folder in On My iPhone (iOS may evict iCloud downloads).

**Support files.** Before returning (and already when the folder is checked, so problems show on
Home), every file below `<App>.app/GameSupport` is mirrored into the game folder in use (chosen
folder or the copy in the app; never the read-only bundle), creating subfolders. A file is written
only when missing or different (size, then bytes); nothing is ever deleted. If any file cannot be
written (read-only folder), the launcher logs a warning, shows a non-blocking notice on Home
("Window layouts will be missing"), and sets `GENERALSX_BUNDLED_FONTS_DIR` and `DXVK_CONFIG_FILE`
to the bundle's copies. Window overrides cannot be redirected that way.

**Options.ini seed.** When `Options.ini` is missing it is created from
`<App>.app/GameSupport/DefaultOptions.ini` (falling back to the data folder's), both by the
settings screens and right before returning.

Variables are only ever set (overwrite = 1), never unset, so values given in an Xcode scheme for
debugging still work when the switch is off. `GX_NET_TRACE` (Android's online trace) is not exposed.

## 4. Files written

All under the app's home directory; formats are byte-compatible with the Android launcher.

| File | Format | Android source |
|---|---|---|
| `Library/Application Support/GeneralsX/GeneralsZH/Options.ini` | engine `key = value` lines; see below | `SetupActivity.writeKeyValueFile` |
| `$GX_SETTINGS_DIR/control_scheme` | `attack_move=1\narmy_buttons=0\ncamera_high=1\n` (always all three keys, in this order); **deleted** for Classic | `writeControlScheme`, `GXControlScheme.h` |
| `$GX_SETTINGS_DIR/mouse_mode` | present = pointer mode; content = cursor percent, no newline (`"100"`), 50..200 step 10; deleted when off | `writeMouseMode`, `GXMouseMode.h` |
| `$GX_SETTINGS_DIR/logging_off` | empty; present = "Collect logs" **off** | `LOGGING_OFF_MARKER`, `GXLogging.h` |
| `$GX_SETTINGS_DIR/gx_trace.txt`, `gx_perf.txt`, `gx_audio_trace.txt`, `gx_touch_debug.txt` | empty markers (persistence; the env vars above are what take effect) | `DIAGNOSTIC_MARKERS` |
| `$GX_SETTINGS_DIR/launcher_prefs.json` | launcher-only: `{"skipIntro":bool,"playSoundInSilentMode":bool}` (sound defaults to `true` when absent; an older `preferImportedData` key is ignored) | SharedPreferences |
| `$GX_SETTINGS_DIR/game_folder.json` | the chosen game folder (section 3a) | `gamedata_path.txt` |
| `Library/Application Support/GeneralsX/ImportedGameData/` | copy of a game folder made in the app (excluded from backup) | -- |
| `<game folder>/fonts/`, `Window/`, `dxvk.conf`, `DefaultOptions.ini` | mirrored from `<App>.app/GameSupport` (section 3a) | `copyBundledRuntimeIfMissing`, `syncEngineWindowOverrides` |

Files read: `Documents/generals-stderr.log`, `Documents/generals-stderr-prev.log` (log viewer:
first 60,000 + last 140,000 bytes shown, Share sends the whole file, Clear deletes both),
`GameSupport/DefaultOptions.ini` (seed), `<data>/*.big` (validation).

### Options.ini keys

| Key | UI | Range / step | Default shown | Notes |
|---|---|---|---|---|
| `GXUiScale` | Interface > Interface Size | 70..200, step 10 | 100 (missing/unparsable) | clamped on read (Android's slider starts at 100; iOS can shrink to 70) |
| `ResolutionFontAdjustment` | Interface > Menu Text Size | 0..150, step 1 | 70 (missing, unparsable or negative) | the in-game Options menu writes -100 for "default"; shown as 70 |

Editing is **line-preserving**: only the value on the line(s) carrying the key changes (the key
text and the spacing after `=` are kept; every duplicate is updated, since the engine's map keeps
the last one); a new key is appended as `key = value` (`UserPreferences::write()` format);
comments, blank lines, CRLF vs LF, the final newline and the file's encoding (UTF-8 or Latin-1)
are preserved. Saves are atomic. When Options.ini does not exist it is first seeded from
`GameSupport/DefaultOptions.ini` (else the active game data's), like Android -- otherwise the engine's own first-run seed
(SDL3Main.cpp "Seeded default Options.ini") would be skipped forever.

### Arguments

| Argument | When | Engine |
|---|---|---|
| `-gxSafeInsets l,t,r,b` | safe-area insets not all zero | `parseGxSafeInsets` / GXSafeArea.h (**Android tree only**; the iOS tree ignores it until ported) |
| `-nologo` | Home > Skip intro movies (default off) | `parseNoLogo` (present in the iOS tree) |

Safe insets are fractions of the **landscape** window (POSIX decimal point, 4 decimals). Measured
from the launcher's window just before it closes; if the launcher is portrait they are rotated
(portrait top/bottom become left/right, both sides get the larger; bottom keeps the portrait
home-indicator inset -- a slight over-estimate, never clipping). Measured on iPhone 18 Pro Max:
landscape `0.0649,0.0000,0.0649,0.0455`, from portrait `0.0649,0.0000,0.0649,0.0773`. Long term
the engine could instead call SDL3's `SDL_GetWindowSafeArea()` once the window is landscape.

## 5. Engine side (done in this repository)

- `Core/Main/SDL3Main.cpp` calls `gx_launcher_run()` first in the iOS branch of `main()` and
  appends the returned arguments to `__argv`; it prefers `GX_GAME_DATA_DIR` as the working
  directory and skips the stderr mirror when "Collect logs" is off (`GXLoggingDisabled()`).
- `GeneralsMD/Code/Main/CMakeLists.txt` builds the package with SwiftPM and force-loads it
  (`GX_HAS_IOS_LAUNCHER`); `scripts/build/ios/package-ios-zh.sh` copies the resource bundle.
- The settings readers (`GXControlScheme.h`, `GXMouseMode.h`, `GXLogging.h`,
  `GXManagedMods.h`) use `Common/GXSettingsPath.h`, which resolves `$GX_SETTINGS_DIR/<name>` on
  iOS. `GXUiScale` is read from Options.ini by `SDL3Main.cpp`; `-gxSafeInsets` is parsed by
  `CommandLine.cpp` (`GXSafeArea`). Diagnostics use the `GX_TRACE` / `GX_PERF` /
  `GX_AUDIO_TRACE` / `GX_TOUCH_DEBUG` environment variables.
- iOS builds use the system allocator (`RTS_GAMEMEMORY_ENABLE=OFF`): the game's pool replaces
  `operator new`/`delete` process-wide and is not thread-safe, which crashed SwiftUI's
  multithreaded text rendering.

## 6. Behaviour decisions where Android was ambiguous

* **Base-game check:** Android's comment says "flag only when ALL base asset archives are absent",
  its code flags when ANY of the ten is missing. The code was ported (any missing -> issue,
  listing the names). Archives are looked for in the folder and its immediate subfolders, so the
  bundled `ZH_Generals/` counts.
* **Case:** archive names are compared case-insensitively everywhere (the bundled
  `ZH_Generals` has `maps.big`, `shaders.big`); Android used exact-case `File.exists()` for the
  INIZH.big/INI.big presence check.
* **Critical entry:** `Data\INI\Default\Weather.ini` must be listed by at least one of INIZH.big /
  INI.big (root or subfolder). Android's original-Generals variant (`Data\INI\GameData.ini`) is
  implemented (`GameDataValidator.generalsCriticalEntry`) but not offered: only Zero Hour ships.
* **BIG reader:** count sanity cap 500,000 (Android used 500,000 in one reader and 200,000 in the
  other); names longer than 511 bytes are truncated like Android's 512-byte buffer; a truncated
  table never counts as containing the entry.
* **Sliders apply immediately** (Android had Apply buttons); every change is written atomically.
* **Play with bad data** asks "Play anyway?" instead of refusing.
* **Mouse and touchpad** (Android puts it in the control-scheme card) is included.
* **Copy into the app:** copied to a `.partial` folder and swapped in only when complete; a parent
  folder is accepted like for "Choose game folder"; rejected if it has neither INIZH.big nor
  INI.big; free space checked first; hidden files and `._*` skipped; the GameSupport files are
  mirrored in (dev builds without GameSupport: the bundled GameData's `DefaultOptions.ini`,
  `dxvk.conf`, `fonts/`, as Android's `copyBundledRuntimeIfMissing`). The old "Use imported game
  data" switch is gone: the source follows the fixed priority of section 3a.
* **Chosen folder vs Android:** Android stores an absolute path (it has all-files access); iOS needs
  the security-scoped bookmark. A read-only chosen folder is still played from (with the bundle's
  fonts/dxvk.conf); Android would fail to copy and carry on the same way.
* **Collect logs off** does not delete existing logs (Android does not either).

## 7. Testing

```sh
# unit tests (53) on the simulator, or `swift test` on the Mac (core only)
cd GXLauncher && xcodebuild test -scheme GXLauncher -destination 'id=<sim udid>' -derivedDataPath ../build/dd
# host app: build, install, fake GameSupport (+ fake GameData unless --no-gamedata) + logs,
# optionally a fake retail folder in Files > On My iPhone > Games (--files), launch
# (stderr -> build/host-stderr.log)
scripts/run-host.sh [udid] [--broken] [--no-gamedata] [--files] [-- GX_LAUNCHER_SKIP=1 | GX_LAUNCHER_SECTION=logs]
# the host writes what it got to Documents/host_result.json in its data container
```

`testRealGameDataIfAvailable` validates real game data when `$GX_REAL_GAMEDATA` points at it
(e.g. `build/ios-package/GeneralsXZH.app/GameData` of a packaged engine build); otherwise skipped:
all 2.7 GB checks clean in about 10 ms because only the archive tables are read.

## 8. Extending (mods, language packs)

Add a case to `LauncherModel.Section` (title + SF Symbol) and a branch in
`LauncherRootView.content(for:)`; both the tab bar and the sidebar pick it up. Engine-facing
formats belong in `GXLauncherCore` (Foundation only, unit-testable); e.g. `mods_active.txt` would
be a sibling of `ControlScheme` in `SettingsFiles.swift`, and its env/argument effect goes into
`LaunchPlanBuilder.plan`. Run `python3 -I scripts/gen-strings.py` after adding `L("...")` strings.

## Known gaps / TODO

* "How to play / gestures" is a TODO placeholder list.
* "Choose game folder" was driven end to end in the simulator (picker > On My iPhone > a parent
  folder > nested detection > bookmark > support files > Play), but the simulator does not enforce
  the sandbox, so security-scoped access across launches is only verified on a real device.
  iCloud was simulated with `.icloud` placeholders; real iCloud Drive downloads are unverified.
* "Copy into the app" is verified by unit tests, not by driving the picker.
* The iPhone Duo inner display was not tested (runtime not installed); layout keys only on size
  classes. The iPhone 18 Pro Max reports regular width in landscape, so both layouts were exercised.
* The simulator was sluggish throughout (stock Settings also took seconds to draw), so input
  latency could not be judged there; the launcher's main thread sampled idle in `mach_msg`.
