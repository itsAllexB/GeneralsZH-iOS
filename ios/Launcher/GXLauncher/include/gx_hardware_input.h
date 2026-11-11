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

// GeneralsX @feature iOS port 11/11/2026 C interface of the hardware mouse and keyboard support
// (Sources/GXLauncher/HardwareInput.swift). The engine includes it through
// Core/GameEngine/Include/Common/GXHardwareInput.h.
//
// All functions: main thread only, except gx_hardware_mouse_connected (any thread). Callbacks are
// called on the main thread.

#ifndef GX_HARDWARE_INPUT_H
#define GX_HARDWARE_INPUT_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// A mouse (every GCMouse connected, Bluetooth or USB):
//   move:        x/y = the pointer's motion in the game window's points (y down)
//   button down/up: id = SDL's button number (1 left, 2 middle, 3 right)
//   wheel:       x = horizontal, y = vertical notches (positive y is away from the user)
enum GXHardwareMouseKind
{
	GX_HARDWARE_MOUSE_MOVE = 0,
	GX_HARDWARE_MOUSE_BUTTON_DOWN = 1,
	GX_HARDWARE_MOUSE_BUTTON_UP = 2,
	GX_HARDWARE_MOUSE_WHEEL = 3,
};

typedef void (*GXHardwareMouseCallback)(int32_t kind, uint64_t id, float x, float y);
// Text typed on a hardware keyboard while gx_hardware_text_input(true): UTF-8, valid during the call.
typedef void (*GXHardwareTextCallback)(const char *utf8);

// Once the game's window exists and gx_external_display_start has been called.
void gx_hardware_input_start(GXHardwareMouseCallback mouse, GXHardwareTextCallback text);

// Once per frame: takes mice back from SDL's GameController handlers, keeps the text responder placed.
void gx_hardware_input_update(void);

// Whether a mouse is connected (GameController knows one).
bool gx_hardware_mouse_connected(void);

// Whether a hardware keyboard is connected.
bool gx_hardware_keyboard_connected(void);

// The game wants text (a text field has focus): with a hardware keyboard, its typed characters go to
// the text callback, wherever the picture is, and no on-screen keyboard shows.
void gx_hardware_text_input(bool wanted);

#ifdef __cplusplus
}
#endif

#endif /* GX_HARDWARE_INPUT_H */
