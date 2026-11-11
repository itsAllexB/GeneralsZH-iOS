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

// GeneralsX @feature iOS port 11/11/2026 External display harness for the iOS Simulator.
//
// The game cannot render in the Simulator (its GPU lacks a Vulkan 1.2 feature DXVK needs), so this
// stands in for the engine around the same production pieces: the patched SDL3 of the game's build,
// the launcher library with ExternalDisplay.swift, and the same calls SDL3Main.cpp and
// SDL3GameEngine.cpp make (gx_external_display_start / _update / _wanted_resolution, the pad's
// events pushed as SDL events). SDL's Metal renderer takes DXVK's place: it draws into the same kind
// of Metal view SDL makes for DXVK's surface.
//
// The test card: a 1-pixel white border at the drawable's edge, a circle that must stay round, a grid
// every 10 % of the width, and text with the window's points, SDL's pixel size, the renderer's output
// size (the Metal drawable), the resolution the game would want and where the picture is. The
// pointer (a cross) moves like the game's touchpad pointer: by the pad's finger deltas times the
// engine's 1.6; a quick tap counts as a click, a two-finger tap as a right click. Every change is
// logged to stderr as "HARNESS ...". See README.md for the switches.

#include <SDL3/SDL.h>
#include <SDL3/SDL_main.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

#include "gx_external_display.h"
#include "gx_hardware_input.h"
#include "gx_launcher.h"

#define PAD_TOUCH_ID 0x4758504144ull
#define PAD_MOUSE_ID 0xFFFFFFFCu

static SDL_Window *s_window;

static void padInput(int32_t kind, uint64_t id, float x, float y)
{
	SDL_Event e;
	SDL_zero(e);
	switch (kind) {
	case GX_PAD_FINGER_DOWN: e.type = SDL_EVENT_FINGER_DOWN; break;
	case GX_PAD_FINGER_MOVE: e.type = SDL_EVENT_FINGER_MOTION; break;
	case GX_PAD_FINGER_UP: e.type = SDL_EVENT_FINGER_UP; break;
	case GX_PAD_FINGER_CANCEL: e.type = SDL_EVENT_FINGER_CANCELED; break;
	case GX_PAD_HOVER: {
		int w = 0, h = 0;
		SDL_GetWindowSize(s_window, &w, &h);
		e.type = SDL_EVENT_MOUSE_MOTION;
		e.motion.which = PAD_MOUSE_ID;
		e.motion.x = x * w;
		e.motion.y = y * h;
		SDL_PushEvent(&e);
		return;
	}
	case GX_PAD_BUTTON_DOWN:
	case GX_PAD_BUTTON_UP:
		e.type = kind == GX_PAD_BUTTON_DOWN ? SDL_EVENT_MOUSE_BUTTON_DOWN : SDL_EVENT_MOUSE_BUTTON_UP;
		e.button.which = PAD_MOUSE_ID;
		e.button.button = (Uint8)id;
		e.button.down = kind == GX_PAD_BUTTON_DOWN;
		SDL_PushEvent(&e);
		return;
	default:
		return;
	}
	e.tfinger.touchID = PAD_TOUCH_ID;
	e.tfinger.fingerID = id;
	e.tfinger.x = x;
	e.tfinger.y = y;
	e.tfinger.windowID = SDL_GetWindowID(s_window);
	SDL_PushEvent(&e);
}

// The hardware mouse and keyboard callbacks (HardwareInput.swift): logged, and the mouse moves the cross.
static float s_hwDx, s_hwDy;
static void hardwareMouse(int32_t kind, uint64_t id, float x, float y)
{
	if (kind == GX_HARDWARE_MOUSE_MOVE) { s_hwDx += x; s_hwDy += y; return; }
	fprintf(stderr, "HARNESS hardware mouse kind %d id %llu %.2f,%.2f\n", kind, (unsigned long long)id, x, y);
}
static void hardwareText(const char *utf8)
{
	fprintf(stderr, "HARNESS hardware text \"%s\"\n", utf8 ? utf8 : "");
}

static void drawCircle(SDL_Renderer *r, float cx, float cy, float radius)
{
	SDL_FPoint pts[361];
	for (int i = 0; i <= 360; ++i) {
		pts[i].x = cx + radius * cosf(i * 3.14159265f / 180.0f);
		pts[i].y = cy + radius * sinf(i * 3.14159265f / 180.0f);
	}
	SDL_RenderLines(r, pts, 361);
}

int main(int argc, char *argv[])
{
	(void)argc;
	(void)argv;
	gx_launcher_run();	// GX_LAUNCHER_SKIP=1: no UI; prepares the external display support as the game's start does

	if (!SDL_Init(SDL_INIT_VIDEO)) {
		fprintf(stderr, "HARNESS SDL_Init failed: %s\n", SDL_GetError());
		return 1;
	}
	SDL_SetHint(SDL_HINT_TOUCH_MOUSE_EVENTS, "0");
	// HARNESS_LAUNCHER_SECONDS=n: n seconds as if the player were in the launcher, so a display
	// connected before the game's window exists shows the title card and the game starts on it.
	const char *wait = SDL_getenv("HARNESS_LAUNCHER_SECONDS");
	if (wait != NULL && SDL_atoi(wait) > 0) {
		const Uint64 until = SDL_GetTicks() + (Uint64)SDL_atoi(wait) * 1000;
		while (SDL_GetTicks() < until) {
			SDL_PumpEvents();
			SDL_Delay(10);
		}
	}
	s_window = SDL_CreateWindow("harness", 1024, 768, SDL_WINDOW_RESIZABLE | SDL_WINDOW_HIGH_PIXEL_DENSITY | SDL_WINDOW_HIDDEN);
	int pw = 0, ph = 0;
	SDL_GetWindowSizeInPixels(s_window, &pw, &ph);
	if (pw < ph) { int t = pw; pw = ph; ph = t; }
	gx_external_display_set_phone_resolution(pw & ~1, ph);
	gx_external_display_start(SDL_GetPointerProperty(SDL_GetWindowProperties(s_window), SDL_PROP_WINDOW_UIKIT_WINDOW_POINTER, NULL), padInput);
	gx_external_display_update();
	gx_hardware_input_start(hardwareMouse, hardwareText);
	fprintf(stderr, "HARNESS hardware: mouse %d keyboard %d\n", gx_hardware_mouse_connected(), gx_hardware_keyboard_connected());
	// HARNESS_TEXT=1: as if a game text field had focus all along (SDL3GameEngine.cpp updateTextInputState).
	const bool wantText = SDL_getenv("HARNESS_TEXT") != NULL;
	int32_t sw = 0, sh = 0;
	if (gx_external_display_start_resolution(&sw, &sh))
		fprintf(stderr, "HARNESS start resolution %dx%d (display connected at start; phone %dx%d)\n", sw, sh, pw & ~1, ph);
	else
		fprintf(stderr, "HARNESS start resolution %dx%d (the phone's)\n", pw & ~1, ph);

	SDL_Renderer *renderer = SDL_CreateRenderer(s_window, "metal");
	if (renderer == NULL) {
		fprintf(stderr, "HARNESS no Metal renderer: %s\n", SDL_GetError());
		return 1;
	}
	SDL_ShowWindow(s_window);

	// HARNESS_SCRIPTED_PAD=1: the pad's own C callback is driven with a fixed gesture sequence (the
	// Simulator gives no scripted touches here): a drag, a tap, a two-finger tap, a hover.
	const bool scripted = SDL_getenv("HARNESS_SCRIPTED_PAD") != NULL;
	int script = 0;
	float px = -1, py = -1;
	int clicks = 0, rightClicks = 0, fingers = 0, maxFingers = 0;
	Uint64 downAt = 0;
	float travel = 0, lastFx[8] = {0}, lastFy[8] = {0};
	char last[512] = "";
	bool running = true;
	while (running) {
		gx_external_display_update();
		gx_hardware_text_input(wantText);
		gx_hardware_input_update();
		int ww = 0, wh = 0, pxw = 0, pxh = 0, ow = 0, oh = 0;
		SDL_GetWindowSize(s_window, &ww, &wh);
		SDL_GetWindowSizeInPixels(s_window, &pxw, &pxh);
		SDL_GetCurrentRenderOutputSize(renderer, &ow, &oh);
		if (px < 0 || px > ww || py > wh) { px = ww * 0.5f; py = wh * 0.5f; }

		if (scripted && gx_external_display_picture_away() && script < 400) {
			++script;
			if (script == 60) { fprintf(stderr, "HARNESS script: drag right/down by 0.1 x 0.1 of the window\n"); padInput(GX_PAD_FINGER_DOWN, 1, 0.2f, 0.2f); }
			if (script > 60 && script <= 70) padInput(GX_PAD_FINGER_MOVE, 1, 0.2f + 0.01f * (script - 60), 0.2f + 0.01f * (script - 60));
			if (script == 71) padInput(GX_PAD_FINGER_UP, 1, 0.3f, 0.3f);
			if (script == 120) { fprintf(stderr, "HARNESS script: tap\n"); padInput(GX_PAD_FINGER_DOWN, 2, 0.5f, 0.5f); }
			if (script == 122) padInput(GX_PAD_FINGER_UP, 2, 0.5f, 0.5f);
			if (script == 180) { fprintf(stderr, "HARNESS script: two-finger tap\n"); padInput(GX_PAD_FINGER_DOWN, 3, 0.4f, 0.5f); padInput(GX_PAD_FINGER_DOWN, 4, 0.6f, 0.5f); }
			if (script == 182) { padInput(GX_PAD_FINGER_UP, 3, 0.4f, 0.5f); padInput(GX_PAD_FINGER_UP, 4, 0.6f, 0.5f); }
			if (script == 240) { fprintf(stderr, "HARNESS script: hover to 0.75,0.25 and click\n"); padInput(GX_PAD_HOVER, 0, 0.75f, 0.25f); padInput(GX_PAD_BUTTON_DOWN, 1, 0, 0); padInput(GX_PAD_BUTTON_UP, 1, 0, 0); }
			if (script == 300) fprintf(stderr, "HARNESS script done: pointer %.0f,%.0f clicks %d right %d\n", px, py, clicks, rightClicks);
		}

		if (s_hwDx != 0 || s_hwDy != 0) {
			px = SDL_clamp(px + s_hwDx, 0, ww - 1);
			py = SDL_clamp(py + s_hwDy, 0, wh - 1);
			s_hwDx = s_hwDy = 0;
		}
		SDL_Event e;
		while (SDL_PollEvent(&e)) {
			switch (e.type) {
			case SDL_EVENT_KEY_DOWN:
				fprintf(stderr, "HARNESS key down %s mod 0x%x window %u\n", SDL_GetScancodeName(e.key.scancode), e.key.mod, e.key.windowID);
				break;
			case SDL_EVENT_QUIT: running = false; break;
			case SDL_EVENT_WINDOW_FOCUS_LOST: fprintf(stderr, "HARNESS focus lost (away %d)\n", gx_external_display_picture_away()); break;
			case SDL_EVENT_WINDOW_FOCUS_GAINED: fprintf(stderr, "HARNESS focus gained (away %d)\n", gx_external_display_picture_away()); break;
			case SDL_EVENT_WILL_ENTER_BACKGROUND: fprintf(stderr, "HARNESS will enter background\n"); break;
			case SDL_EVENT_DID_ENTER_FOREGROUND: fprintf(stderr, "HARNESS did enter foreground\n"); break;
			case SDL_EVENT_MOUSE_MOTION:
				if (e.motion.which == PAD_MOUSE_ID) { px = e.motion.x; py = e.motion.y; }
				break;
			case SDL_EVENT_MOUSE_BUTTON_DOWN:
				if (e.button.which == PAD_MOUSE_ID) fprintf(stderr, "HARNESS mouse button %d down at %.0f,%.0f\n", e.button.button, px, py);
				break;
			case SDL_EVENT_FINGER_DOWN:
			case SDL_EVENT_FINGER_MOTION:
			case SDL_EVENT_FINGER_UP:
			case SDL_EVENT_FINGER_CANCELED: {
				if (e.tfinger.touchID != PAD_TOUCH_ID) {
					fprintf(stderr, "HARNESS finger on the game's own view (type %u)\n", e.type);
					break;
				}
				const int i = (int)(e.tfinger.fingerID % 8);
				const float fx = e.tfinger.x * ww, fy = e.tfinger.y * wh;
				if (e.type == SDL_EVENT_FINGER_DOWN) {
					if (fingers++ == 0) { downAt = SDL_GetTicks(); travel = 0; maxFingers = 0; }
					if (fingers > maxFingers) maxFingers = fingers;
				} else if (e.type == SDL_EVENT_FINGER_MOTION) {
					const float dx = fx - lastFx[i], dy = fy - lastFy[i];
					travel += fabsf(dx) + fabsf(dy);
					if (fingers == 1) {
						px = SDL_clamp(px + dx * 1.6f, 0, ww - 1);
						py = SDL_clamp(py + dy * 1.6f, 0, wh - 1);
					}
				} else if (--fingers <= 0) {
					fingers = 0;
					if (e.type == SDL_EVENT_FINGER_UP && SDL_GetTicks() - downAt < 250 && travel < wh * 0.024f) {
						if (maxFingers >= 2) ++rightClicks; else ++clicks;
						fprintf(stderr, "HARNESS %s at %.0f,%.0f\n", maxFingers >= 2 ? "right click" : "click", px, py);
					}
				}
				lastFx[i] = fx;
				lastFy[i] = fy;
				break;
			}
			default:
				break;
			}
		}

		int32_t wantW = 0, wantH = 0;
		const bool want = gx_external_display_wanted_resolution(&wantW, &wantH);
		char line[512];
		snprintf(line, sizeof line, "%s | window %dx%d pt | SDL pixels %dx%d | drawable %dx%d | game wants %s%dx%d",
		         gx_external_display_picture_away() ? "ON THE DISPLAY" : "on the phone", ww, wh, pxw, pxh, ow, oh,
		         want ? "" : "(nothing) ", wantW, wantH);
		if (strcmp(line, last) != 0) {
			strcpy(last, line);
			fprintf(stderr, "HARNESS %s%s\n", line, (pxw == ow && pxh == oh) ? "" : "  <-- SDL PIXELS != DRAWABLE");
		}

		SDL_SetRenderDrawColor(renderer, 20, 40, 80, 255);
		SDL_RenderClear(renderer);
		SDL_SetRenderScale(renderer, 1, 1);
		SDL_SetRenderDrawColor(renderer, 70, 90, 130, 255);
		for (int g = 1; g < 10; ++g) {
			SDL_RenderLine(renderer, ow * g / 10.0f, 0, ow * g / 10.0f, (float)oh);
		}
		SDL_SetRenderDrawColor(renderer, 255, 255, 255, 255);
		SDL_FRect border = {0.5f, 0.5f, (float)ow - 1, (float)oh - 1};
		SDL_RenderRect(renderer, &border);
		drawCircle(renderer, ow * 0.5f, oh * 0.5f, oh * 0.4f);
		const float sx = ww > 0 ? (float)ow / ww : 1;
		SDL_SetRenderDrawColor(renderer, 255, 220, 0, 255);
		SDL_RenderLine(renderer, px * sx - 20 * sx, py * sx, px * sx + 20 * sx, py * sx);
		SDL_RenderLine(renderer, px * sx, py * sx - 20 * sx, px * sx, py * sx + 20 * sx);
		const float textScale = SDL_max(1.0f, oh / 360.0f);
		SDL_SetRenderScale(renderer, textScale, textScale);
		SDL_SetRenderDrawColor(renderer, 255, 255, 255, 255);
		char text[160];
		snprintf(text, sizeof text, "%s", gx_external_display_picture_away() ? "ON THE EXTERNAL DISPLAY" : "ON THE PHONE");
		SDL_RenderDebugText(renderer, 8, 8, text);
		snprintf(text, sizeof text, "window %dx%d pt, SDL %dx%d px, drawable %dx%d", ww, wh, pxw, pxh, ow, oh);
		SDL_RenderDebugText(renderer, 8, 20, text);
		snprintf(text, sizeof text, "game resolution wanted: %dx%d", wantW, wantH);
		SDL_RenderDebugText(renderer, 8, 32, text);
		snprintf(text, sizeof text, "pointer %.0f,%.0f  clicks %d  right %d", px, py, clicks, rightClicks);
		SDL_RenderDebugText(renderer, 8, 44, text);
		SDL_RenderPresent(renderer);
	}
	SDL_Quit();
	return 0;
}
