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

// GeneralsX @feature iOS port 25/10/2026 Where the launcher keeps its settings files
// (control_scheme, mouse_mode, logging_off, mods_active.txt, ...).
//
//   Android: the app's own files directory, derived from the uid (before any Android storage
//            API is reachable): /data/user/<id>/com.generalsx.zerohour/files
//   iOS:     $GX_SETTINGS_DIR, set by the native launcher before the engine starts
//            (Library/Application Support/GeneralsX/launcher)
//
// GX_HAS_SETTINGS_DIR is 1 on the platforms that have a launcher; the readers in GXControlScheme.h,
// GXLogging.h, GXMouseMode.h and GXManagedMods.h keep the retail behaviour everywhere else.
#pragma once

#include <cstdio>
#include <cstdlib>
#if defined(__APPLE__)
#include <TargetConditionals.h>
#endif

#if defined(__ANDROID__) || (defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE)
#define GX_HAS_SETTINGS_DIR 1
#include <sys/stat.h>
#include <unistd.h>
#else
#define GX_HAS_SETTINGS_DIR 0
#endif

// GeneralsX @feature iOS port 25/10/2026 Bumped each time the iOS launcher has been shown again over
// the running game: readers that cache a settings file read it again when the generation they
// loaded at is no longer current. Always 0 elsewhere.
inline int &GXSettingsGeneration()
{
	static int generation = 0;
	return generation;
}

// GeneralsX @feature iOS port 25/10/2026 Back to the launcher. iOS apps do not quit themselves, so on
// iOS Exit Game (main menu) and Quit to Launcher (pause menu) ask for the launcher instead
// (GXLauncherRequested); SDL3GameEngine::update shows it once the game is back at the menus, through
// the hook SDL3Main installs. The engine keeps running underneath -- it was never written to start
// twice in one process. No hook (other platforms): the menus quit as they always did.
// GeneralsX @feature iOS port 25/10/2026 The launcher's Frame Rate, GX_FPS_LIMIT = 60 or 120. At 120
// the screen is drawn at least 120 times a second while the game logic keeps the rate the game's
// frame limit asks for (FramePacer): smoother scrolling and animation on ProMotion screens, the same
// game speed. Read again after the launcher was shown. Off (60) without the variable.
inline bool GXHighFrameRate()
{
	static bool high = false;
	static int loadedGeneration = -1;
	if (loadedGeneration != GXSettingsGeneration())
	{
		loadedGeneration = GXSettingsGeneration();
		const char *fps = getenv("GX_FPS_LIMIT");
		high = fps != nullptr && atoi(fps) >= 120;
	}
	return high;
}

typedef void (*GXLauncherHookFn)();
inline GXLauncherHookFn &GXLauncherHook()
{
	static GXLauncherHookFn hook = nullptr;
	return hook;
}

inline bool &GXLauncherRequested()
{
	static bool requested = false;
	return requested;
}

// Writes the full path of the launcher settings file `name` into out. False when there is no
// settings directory (other platforms, or iOS started without the launcher).
inline bool GXSettingsFilePath(const char *name, char *out, size_t size)
{
#if defined(__ANDROID__)
	const int userId = (int)(getuid() / 100000);
	snprintf(out, size, "/data/user/%d/com.generalsx.zerohour/files/%s", userId, name);
	return true;
#elif GX_HAS_SETTINGS_DIR
	const char *dir = getenv("GX_SETTINGS_DIR");
	if (dir == nullptr || dir[0] == '\0')
		return false;
	snprintf(out, size, "%s/%s", dir, name);
	return true;
#else
	(void)name;
	(void)out;
	(void)size;
	return false;
#endif
}
