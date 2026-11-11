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

// GeneralsX @feature iOS port 11/11/2026 The game on an external display (iOS: a USB-C monitor or
// AirPlay). The iOS side lives in the launcher package (ios/Launcher/GXLauncher, ExternalDisplay.swift,
// C interface gx_external_display.h): it moves the game's window to the display's scene and back,
// sizes its drawable, and turns the phone into a trackpad. The engine's part:
//
//   - while the picture is on the display, the game has a pointer (GXPointerMode, GXMouseMode.h)
//     and the phone's fingers drive it (SDL3GameEngine.cpp, handleTouchpadEvent);
//   - the game window's loss of key status on the way to the display is not the app going inactive
//     (SDL3GameEngine.cpp, mobileLifecycleWatcher);
//   - the game's resolution follows the display at the menus, where the Options menu changes it
//     too; in a match the picture is fitted with bars until the match is over;
//   - the HUD's safe insets (a phone's notch) do not apply on the display (GXSafeArea.cpp).
//
// GX_HAS_EXTERNAL_DISPLAY is 1 on iOS only; elsewhere nothing here does anything.
#pragma once

#if defined(__APPLE__)
#include <TargetConditionals.h>
#endif

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
#define GX_HAS_EXTERNAL_DISPLAY 1
#include "gx_external_display.h"
#include "gx_hardware_input.h"
#else
#define GX_HAS_EXTERNAL_DISPLAY 0
#endif

// The SDL touch device of the phone's trackpad, and the SDL mouse id of a mouse over it
// (SDL3Main.cpp pushes their events; SDL3GameEngine.cpp reads them).
#define GX_EXTERNAL_PAD_TOUCH_ID 0x4758504144ull
#define GX_EXTERNAL_PAD_MOUSE_ID 0xFFFFFFFCu
// GeneralsX @feature iOS port 11/11/2026 The SDL mouse id of a hardware mouse read through
// GameController (HardwareInput.swift, gx_hardware_input.h): SDL3Main.cpp pushes its events.
#define GX_HARDWARE_MOUSE_ID 0xFFFFFFFBu

// Whether the game's picture is on an external display now.
inline bool GXPictureOnExternalDisplay()
{
#if GX_HAS_EXTERNAL_DISPLAY
	return gx_external_display_picture_away();
#else
	return false;
#endif
}

// GeneralsX @feature iOS port 11/11/2026 Whether a mouse is connected (GameController knows one), on
// the phone or with the picture on a display.
inline bool GXHardwareMouseConnected()
{
#if GX_HAS_EXTERNAL_DISPLAY
	return gx_hardware_mouse_connected();
#else
	return false;
#endif
}

// Whether the hardware mouse drives the game's pointer now: set by its motion and buttons, cleared by
// a finger on the game's own view, so a player can go from the mouse to the touch controls and back.
inline bool &GXHardwareMousePointer()
{
	static bool active = false;
	return active;
}

