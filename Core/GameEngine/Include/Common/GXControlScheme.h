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

// GeneralsX @feature Android port 18/10/2026 The launcher's control scheme: "Classic" (retail) or
// "Tactical", with each Tactical behaviour also switchable on its own.
//
// The Tactical scheme comes from realkot's fork (https://github.com/realkot/GeneralsX, ported with
// the author's permission; parts by Codex/koreazolfakar-droid). The launcher writes a file named
// control_scheme into the app's own files directory with key=value lines; a missing file or key
// is the retail behaviour:
//   attack_move=1   a plain order to move a combat group is an attack-move (dozers, harvesters
//                   and structures still just move)
//   army_buttons=1  the army column (GroupPanel.cpp) starts with its Army (screen / map), Planes,
//                   Helicopters and Ground selection buttons
//   camera_high=1   the camera may be zoomed out up to four times the map's height (3600 max)
//   minimap_camera=1  a tap on the minimap moves the camera there even with units selected, and
//                   dragging on it keeps the camera under the finger (ControlBarCallback.cpp,
//                   LeftHUDInput); an armed ability or attack-move still targets through it
//                   (GeneralsX @feature iOS port 25/10/2026)
// Read again when the launcher was shown again (GXSettingsGeneration). Always the retail
// behaviour on platforms without a launcher.
#pragma once

#include "Common/GXSettingsPath.h"

#include <cstdio>
#include <cstring>
#if GX_HAS_SETTINGS_DIR
#include <unistd.h>
#endif

namespace GXControlScheme
{
	enum Option
	{
		ATTACK_MOVE,
		ARMY_BUTTONS,
		CAMERA_HIGH,
		MINIMAP_CAMERA,
		OPTION_COUNT
	};

	inline bool enabled(Option option)
	{
		static int s_state[OPTION_COUNT];
		static bool s_loaded = false;
		static int s_loadedGeneration = -1;
		if (!s_loaded || s_loadedGeneration != GXSettingsGeneration())
		{
			s_loaded = true;
			s_loadedGeneration = GXSettingsGeneration();
			for (int i = 0; i < OPTION_COUNT; ++i)
				s_state[i] = 0;
#if GX_HAS_SETTINGS_DIR
			static const char *const kNames[OPTION_COUNT] = { "attack_move", "army_buttons", "camera_high", "minimap_camera" };
			char path[256];
			if (!GXSettingsFilePath("control_scheme", path, sizeof(path)))
				path[0] = '\0';
			FILE *fp = fopen(path, "r");
			if (fp != nullptr)
			{
				char line[128];
				while (fgets(line, sizeof(line), fp) != nullptr)
				{
					char *eq = strchr(line, '=');
					if (eq == nullptr)
						continue;
					*eq = '\0';
					for (int i = 0; i < OPTION_COUNT; ++i)
					{
						if (strcmp(line, kNames[i]) == 0)
							s_state[i] = (eq[1] == '1') ? 1 : 0;
					}
				}
				fclose(fp);
				fprintf(stderr, "[GX-Controls] scheme: attack_move=%d army_buttons=%d camera_high=%d minimap_camera=%d\n",
					s_state[ATTACK_MOVE], s_state[ARMY_BUTTONS], s_state[CAMERA_HIGH], s_state[MINIMAP_CAMERA]);
				fflush(stderr);
			}
#endif
		}
		return s_state[option] != 0;
	}
}
