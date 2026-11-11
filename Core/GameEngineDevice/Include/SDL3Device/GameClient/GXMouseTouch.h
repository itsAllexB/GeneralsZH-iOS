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

// GeneralsX @feature iOS port 11/11/2026 Which touches are a mouse's buttons.
//
// An iPhone gives apps a mouse only through AssistiveTouch (Settings > Accessibility > Touch). Then
// GameController still reports the mouse's motion (GCMouse, HardwareInput.swift), but a button press
// reaches the app as a TOUCH where the AssistiveTouch pointer is -- an ordinary direct touch, held for
// as long as the button and moving with the pointer. Taken as a finger, a click still worked (a tap
// on the trackpad is a click) but a held button did not: the trackpad reads a finger that moves as
// "move the pointer" (handleTouchpadEvent), so a left drag never held the left button for a selection
// box, and a held right button never held anything. GameController's own button reports may or may
// not come as well (iPadOS sends them; whether an iPhone does with AssistiveTouch is not documented).
//
// So, while a mouse is connected, a touch that starts within a moment of the mouse moving waits to be
// told what it is:
//   - the mouse moves while it is down: the mouse's button, held until the touch ends;
//   - held still for HOLD_MS: the mouse's button, held (a press before a drag);
//   - it ends within CLICK_MAX_MS: a click, wherever the game's pointer is;
//   - it moves on its own (no mouse motion) after DECIDE_MS: a finger, replayed as it happened;
//   - GameController reports a button press around it (any button: a touch cannot tell which one):
//     that press is the press, the touch adds nothing.
// A touch that starts with the mouse idle for RECENT_MS is a finger at once. Buttons are merged over
// both sources, so a press that comes both ways is pressed once; and a GameController press that
// arrives right after a touch already clicked is dropped. Without a mouse nothing here runs.
//
// No SDL here: the engine (SDL3GameEngine.cpp) feeds it times, positions and its own events, and gets
// back the events to replay and the button changes to make. Unit tested on the Mac
// (ios/tests/hardware-input).
#pragma once

#include <cstdint>
#include <cmath>
#include <map>
#include <vector>

namespace GXMouseTouch
{
	const uint64_t RECENT_MS = 2000;	// mouse motion this recent makes a new touch a candidate
	const uint64_t DECIDE_MS = 80;		// a touch moving on its own is a finger only after this
	const uint64_t CLICK_MAX_MS = 350;	// a candidate that ends sooner is a click
	const uint64_t HOLD_MS = 300;		// a candidate held still this long is a held button
	const uint64_t DEDUPE_MS = 200;		// a GameController press this close to a touch is the same press
	const float SLOP = 6.0f;			// window points a finger moves before it counts as moving

	enum Phase { DOWN, MOVE, UP, CANCEL };
	enum Source { SOURCE_TOUCH, SOURCE_GAMECONTROLLER };

	template <typename Event>
	class Sink
	{
	public:
		virtual ~Sink() {}
		virtual void forward(const Event &event) = 0;					// a finger after all: replay it
		virtual void button(int button, bool down, Source source) = 0;	// SDL button numbers
		virtual void pointerMove(float dx, float dy) = 0;				// window points
	};

	template <typename Event>
	class Classifier
	{
	public:
		explicit Classifier(Sink<Event> &sink)
			: m_sink(sink), m_lastGameControllerDownMs(0), m_lastTouchClickMs(0), m_lastMotionMs(0),
			  m_haveGameControllerDown(false), m_haveTouchClick(false), m_haveMotion(false) {}

		void mouseMoved(uint64_t nowMs)
		{
			m_lastMotionMs = nowMs;
			m_haveMotion = true;
			for (typename std::map<uint64_t, Touch>::iterator it = m_touches.begin(); it != m_touches.end(); ++it) {
				Touch &t = it->second;
				t.motionSinceDown = true;
				if (t.state == PENDING) {
					becomeMouse(t, nowMs);
				}
			}
		}

		void gameControllerButton(uint64_t nowMs, int button, bool down)
		{
			if (down) {
				if (m_haveTouchClick && nowMs - m_lastTouchClickMs <= DEDUPE_MS) {
					m_droppedGameController[button] = true;	// the touch already clicked
					return;
				}
				m_lastGameControllerDownMs = nowMs;
				m_haveGameControllerDown = true;
				// A touch waiting for this press is this press (whatever button the touch guessed:
				// GameController knows which one it is), and adds nothing.
				for (typename std::map<uint64_t, Touch>::iterator it = m_touches.begin(); it != m_touches.end(); ++it) {
					Touch &t = it->second;
					if (t.state == PENDING) {
						t.state = SWALLOWED;
					}
				}
			} else if (m_droppedGameController[button]) {
				m_droppedGameController[button] = false;
				return;
			}
			hold(button, SOURCE_GAMECONTROLLER, down);
		}

		// x, y in window points. `secondary`: the touch's button mask says the secondary button.
		void touch(uint64_t nowMs, uint64_t id, Phase phase, float x, float y, bool secondary, const Event &event)
		{
			if (phase == DOWN) {
				Touch t;
				t.downMs = nowMs;
				t.x0 = x;
				t.y0 = y;
				t.lastX = x;
				t.lastY = y;
				t.button = secondary ? 3 : 1;
				const bool recent = m_haveMotion && nowMs - m_lastMotionMs <= RECENT_MS;
				if (!recent) {
					t.state = FINGER;
					m_touches[id] = t;
					m_sink.forward(event);
					return;
				}
				if (gameControllerPressedSince(nowMs > DEDUPE_MS ? nowMs - DEDUPE_MS : 0)) {
					t.state = SWALLOWED;
				} else {
					t.state = PENDING;
					t.events.push_back(event);
				}
				m_touches[id] = t;
				return;
			}
			typename std::map<uint64_t, Touch>::iterator it = m_touches.find(id);
			if (it == m_touches.end()) {
				m_sink.forward(event);	// began before a mouse came: still a finger
				return;
			}
			Touch &t = it->second;
			const float dist = std::sqrt((x - t.x0) * (x - t.x0) + (y - t.y0) * (y - t.y0));
			const float lastX = t.lastX, lastY = t.lastY;
			t.lastX = x;
			t.lastY = y;
			if (phase == MOVE) {
				if (t.state == FINGER) {
					m_sink.forward(event);
				} else if (t.state == MOUSE && !t.motionSinceDown) {
					// A held button whose drag GameController does not report as motion: the touch,
					// which moves with the system's pointer, moves the game's.
					m_sink.pointerMove(x - lastX, y - lastY);
				} else if (t.state == PENDING) {
					t.events.push_back(event);
					if (dist > SLOP && !t.motionSinceDown && nowMs - t.downMs >= DECIDE_MS) {
						becomeFinger(t);
					}
				}
				return;
			}
			// UP or CANCEL
			switch (t.state) {
			case FINGER:
				m_sink.forward(event);
				break;
			case MOUSE:
				hold(t.button, SOURCE_TOUCH, false);
				break;
			case PENDING:
				if (phase == UP) {
					if (dist > SLOP && !t.motionSinceDown) {
						t.events.push_back(event);
						becomeFinger(t);	// a quick swipe of a finger
					} else {
						hold(t.button, SOURCE_TOUCH, true);
						hold(t.button, SOURCE_TOUCH, false);
						m_lastTouchClickMs = nowMs;
						m_haveTouchClick = true;
					}
				}
				break;
			case SWALLOWED:
				break;
			}
			m_touches.erase(it);
		}

		void tick(uint64_t nowMs)
		{
			for (typename std::map<uint64_t, Touch>::iterator it = m_touches.begin(); it != m_touches.end(); ++it) {
				Touch &t = it->second;
				if (t.state == PENDING && nowMs - t.downMs >= HOLD_MS) {
					becomeMouse(t, nowMs);
				}
			}
		}

		// The mouse went away: every touch it held lets go, and touches still waiting are fingers.
		void reset()
		{
			for (typename std::map<uint64_t, Touch>::iterator it = m_touches.begin(); it != m_touches.end(); ++it) {
				Touch &t = it->second;
				if (t.state == PENDING) {
					becomeFinger(t);
				} else if (t.state == MOUSE) {
					hold(t.button, SOURCE_TOUCH, false);
					t.state = SWALLOWED;
				}
			}
			for (int button = 1; button <= 3; ++button) {
				if (m_held[button][SOURCE_GAMECONTROLLER]) {
					hold(button, SOURCE_GAMECONTROLLER, false);
				}
			}
			m_haveMotion = false;
		}

		bool isDown(int button) const
		{
			std::map<int, std::map<int, bool> >::const_iterator it = m_held.find(button);
			if (it == m_held.end()) return false;
			for (std::map<int, bool>::const_iterator s = it->second.begin(); s != it->second.end(); ++s) {
				if (s->second) return true;
			}
			return false;
		}

	private:
		enum State { PENDING, FINGER, MOUSE, SWALLOWED };
		struct Touch
		{
			Touch() : state(PENDING), downMs(0), x0(0), y0(0), lastX(0), lastY(0), button(1), motionSinceDown(false) {}
			State state;
			uint64_t downMs;
			float x0, y0;
			float lastX, lastY;
			int button;
			bool motionSinceDown;
			std::vector<Event> events;
		};

		void becomeMouse(Touch &t, uint64_t nowMs)
		{
			t.events.clear();
			if (gameControllerPressedSince(t.downMs > DEDUPE_MS ? t.downMs - DEDUPE_MS : 0)) {
				t.state = SWALLOWED;
				return;
			}
			(void)nowMs;
			t.state = MOUSE;
			hold(t.button, SOURCE_TOUCH, true);
		}

		void becomeFinger(Touch &t)
		{
			t.state = FINGER;
			for (size_t i = 0; i < t.events.size(); ++i) {
				m_sink.forward(t.events[i]);
			}
			t.events.clear();
		}

		bool gameControllerPressedSince(uint64_t sinceMs) const
		{
			return m_haveGameControllerDown && m_lastGameControllerDownMs >= sinceMs;
		}

		// A button is down while either source holds it; only the changes reach the game.
		void hold(int button, Source source, bool down)
		{
			const bool before = isDown(button);
			m_held[button][source] = down;
			const bool after = isDown(button);
			if (before != after) {
				m_sink.button(button, after, source);
			}
		}

		Sink<Event> &m_sink;
		std::map<uint64_t, Touch> m_touches;
		std::map<int, std::map<int, bool> > m_held;
		std::map<int, bool> m_droppedGameController;
		uint64_t m_lastGameControllerDownMs;
		uint64_t m_lastTouchClickMs;
		uint64_t m_lastMotionMs;
		bool m_haveGameControllerDown;
		bool m_haveTouchClick;
		bool m_haveMotion;
	};
}
