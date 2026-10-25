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
