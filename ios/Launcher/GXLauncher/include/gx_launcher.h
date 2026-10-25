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

// GeneralsX @feature iOS launcher 25/10/2026 C interface of the native iOS launcher (GXLauncher).
//
// The engine's iOS main() calls gx_launcher_run() before SDL video init. It shows the launcher
// (Home / Interface / Tools / Help) in its own UIWindow on the foreground-active UIWindowScene,
// spins the main run loop until the player taps Play, removes the window, applies the settings
// and returns the EXTRA command-line arguments to append to argv.
//
// Threading: call on the main thread, from a run-loop callout -- which is how SDL3 calls
// SDL_main on iOS (performSelector:afterDelay: from the scene delegate). Do not call it from
// inside a block running on the main dispatch queue (the nested run loop could not drain the
// main queue, and the SwiftUI interface would freeze; a warning is printed to stderr), nor from
// inside a UIKit/SwiftUI action handler (nested button actions are not delivered). Safe to
// call before any scene is active: it spins the run loop until one is. Called off the main thread
// it shows no UI and only applies the saved settings.
//
// Returns a NULL-terminated array of NUL-terminated UTF-8 strings, e.g.
//     { "-gxSafeInsets", "0.0670,0.0000,0.0670,0.0773", "-nologo", NULL }
// Never returns NULL; with nothing to add, the array holds just the terminating NULL.
//
// Memory: the array and its strings belong to GXLauncher. They stay valid until the next call to
// gx_launcher_run() (which frees them) or process exit. Do not free or modify them; copy them if
// they must outlive a second call. The engine calls it once, so pointing argv entries straight at
// them is fine.
//
// Side effects before returning (setenv(..., 1)):
//     GX_SETTINGS_DIR    always: <home>/Library/Application Support/GeneralsX/launcher (created)
//     GX_GAME_DATA_DIR   the game data folder to use (bundled <App>.app/GameData, or the
//                        imported copy <home>/Library/Application Support/GeneralsX/ImportedGameData)
//     GX_UI_SCALE        Options.ini GXUiScale, when set
//     GX_TRACE, GX_PERF, GX_AUDIO_TRACE, GX_TOUCH_DEBUG = "1" when that diagnostic is switched on
// and writes Options.ini / the files in GX_SETTINGS_DIR as the player changes settings.
// See INTEGRATION.md for the full contract.
//
// Development: GX_LAUNCHER_SKIP=1 in the environment skips the UI; GX_LAUNCHER_SECTION=
// home|interface|tools|help|logs opens that screen first.

#ifndef GX_LAUNCHER_H
#define GX_LAUNCHER_H

#ifdef __cplusplus
extern "C" {
#endif

const char *const *gx_launcher_run(void);

#ifdef __cplusplus
}
#endif

#endif /* GX_LAUNCHER_H */
