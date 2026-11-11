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

// GeneralsX @feature iOS port 11/11/2026 C interface of the external display support
// (Sources/GXLauncher/ExternalDisplay.swift). The engine includes it through
// Core/GameEngine/Include/Common/GXExternalDisplay.h, which also gives the other platforms (and an
// iOS binary without the launcher) inert defaults.
//
// All functions: main thread only, except gx_external_display_picture_away (any thread).

#ifndef GX_EXTERNAL_DISPLAY_H
#define GX_EXTERNAL_DISPLAY_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// What the phone's trackpad reports (ExternalDisplayPad.swift).
//   finger down/move/up/cancel: id = the finger, x/y = position as a fraction of the game window's
//                               points, already scaled for the display (may fall outside 0..1)
//   hover:                      a mouse over the pad; x/y = where the pointer goes, as a fraction
//                               of the game window (0..1)
//   button down/up:             a mouse button; id = SDL's button number (1 left, 3 right)
enum GXPadEventKind
{
	GX_PAD_FINGER_DOWN = 0,
	GX_PAD_FINGER_MOVE = 1,
	GX_PAD_FINGER_UP = 2,
	GX_PAD_FINGER_CANCEL = 3,
	GX_PAD_HOVER = 4,
	GX_PAD_BUTTON_DOWN = 5,
	GX_PAD_BUTTON_UP = 6,
};

// A finger's id carries this bit when the touch's button mask held the secondary button: an
// AssistiveTouch mouse's right button pressed as a touch (Core/.../GXMouseTouch.h).
#define GX_PAD_SECONDARY_BUTTON (1ull << 62)

typedef void (*GXPadCallback)(int32_t kind, uint64_t id, float x, float y);

// The game's window exists: uiwindow is SDL's UIWindow (SDL_PROP_WINDOW_UIKIT_WINDOW_POINTER). If a
// display is connected, the window moves to it now. The callback receives the pad's input.
void gx_external_display_start(void *uiwindow, GXPadCallback callback);

// Once per frame: keeps the game's view at the capped scale on the display, hides the title card
// once the game's window shows, and ends the display's resolution after the grace period.
void gx_external_display_update(void);

// Whether the game's window is on an external display now.
bool gx_external_display_picture_away(void);

// The resolution the game has on the phone (what SDL3Main picked for the phone at start).
void gx_external_display_set_phone_resolution(int32_t width, int32_t height);

// The resolution the game should have now: the display's while the picture is there (and for the
// grace period after it left), else the phone's. False when nothing is known.
bool gx_external_display_wanted_resolution(int32_t *width, int32_t *height);

// At start-up: the game's resolution for the display the picture is on now. False when the
// picture is on the phone, or the display is too small for the game's interface.
bool gx_external_display_start_resolution(int32_t *width, int32_t *height);

#ifdef __cplusplus
}
#endif

#endif /* GX_EXTERNAL_DISPLAY_H */
