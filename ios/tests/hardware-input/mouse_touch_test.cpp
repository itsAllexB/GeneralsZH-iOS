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

// GeneralsX @feature iOS port 11/11/2026 Unit tests of GXMouseTouch.h (which touches are a mouse's
// buttons). Plain C++, run on the Mac: ./run.sh

#include "SDL3Device/GameClient/GXMouseTouch.h"

#include <cstdio>
#include <string>
#include <vector>

using namespace GXMouseTouch;

struct Ev { int id; Phase phase; };

struct Recorder : Sink<Ev>
{
	std::vector<std::string> log;
	virtual void forward(const Ev &e) override
	{
		static const char *names[] = {"down", "move", "up", "cancel"};
		log.push_back("finger " + std::to_string(e.id) + " " + names[e.phase]);
	}
	virtual void button(int b, bool down, Source s) override
	{
		log.push_back(std::string(down ? "press " : "release ") + std::to_string(b) + (s == SOURCE_TOUCH ? " (touch)" : " (gc)"));
	}
	virtual void pointerMove(float dx, float dy) override
	{
		log.push_back("move " + std::to_string((int)dx) + "," + std::to_string((int)dy));
	}
};

static int s_failures = 0;
static void expect(const char *name, const std::vector<std::string> &got, const std::vector<std::string> &want)
{
	if (got == want) {
		printf("ok   %s\n", name);
		return;
	}
	++s_failures;
	printf("FAIL %s\n  got: ", name);
	for (size_t i = 0; i < got.size(); ++i) printf("[%s] ", got[i].c_str());
	printf("\n  want:");
	for (size_t i = 0; i < want.size(); ++i) printf(" [%s]", want[i].c_str());
	printf("\n");
}

static void touch(Classifier<Ev> &c, uint64_t t, int id, Phase p, float x, float y, bool secondary = false)
{
	Ev e = {id, p};
	c.touch(t, (uint64_t)id, p, x, y, secondary, e);
}

int main()
{
	{	// No mouse motion yet: a finger is a finger, at once.
		Recorder r; Classifier<Ev> c(r);
		touch(c, 1000, 1, DOWN, 100, 100);
		touch(c, 1010, 1, MOVE, 150, 100);
		touch(c, 1020, 1, UP, 150, 100);
		expect("finger without a mouse in use", r.log, {"finger 1 down", "finger 1 move", "finger 1 up"});
	}
	{	// AssistiveTouch: a left drag is a touch that moves together with the mouse's motion.
		Recorder r; Classifier<Ev> c(r);
		c.mouseMoved(1000);
		touch(c, 1500, 1, DOWN, 100, 100);
		c.mouseMoved(1520);
		touch(c, 1525, 1, MOVE, 104, 100);
		c.mouseMoved(1540);
		touch(c, 1545, 1, MOVE, 140, 100);
		touch(c, 1900, 1, UP, 200, 100);
		expect("held left button drags (selection box)", r.log, {"press 1 (touch)", "release 1 (touch)"});
	}
	{	// The touch's button mask says secondary: a right drag holds the right button.
		Recorder r; Classifier<Ev> c(r);
		c.mouseMoved(1000);
		touch(c, 1500, 1, DOWN, 100, 100, true);
		c.mouseMoved(1530);
		touch(c, 1800, 1, UP, 150, 100, true);
		expect("held right button drags (map scroll)", r.log, {"press 3 (touch)", "release 3 (touch)"});
	}
	{	// Held still into a press, then dragged with no GameController motion: the touch moves the pointer.
		Recorder r; Classifier<Ev> c(r);
		c.mouseMoved(1000);
		touch(c, 1500, 1, DOWN, 100, 100);
		c.tick(1810);
		touch(c, 1850, 1, MOVE, 120, 110);
		touch(c, 1900, 1, MOVE, 150, 130);
		touch(c, 2000, 1, UP, 150, 130);
		expect("drag without GameController motion", r.log,
			{"press 1 (touch)", "move 20,10", "move 30,20", "release 1 (touch)"});
	}
	{	// A click: down and up quickly, the pointer still.
		Recorder r; Classifier<Ev> c(r);
		c.mouseMoved(1000);
		touch(c, 1500, 1, DOWN, 100, 100);
		touch(c, 1600, 1, UP, 100, 100);
		expect("click by touch", r.log, {"press 1 (touch)", "release 1 (touch)"});
	}
	{	// Pressed and held still, then the mouse moves: the press happens at HOLD_MS, once.
		Recorder r; Classifier<Ev> c(r);
		c.mouseMoved(1000);
		touch(c, 1500, 1, DOWN, 100, 100);
		c.tick(1700);
		expect("not yet held", r.log, {});
		c.tick(1800);
		c.mouseMoved(2000);
		touch(c, 2500, 1, UP, 100, 100);
		expect("held still, then dragged", r.log, {"press 1 (touch)", "release 1 (touch)"});
	}
	{	// GameController reports the button too, before the touch: one press, from GameController.
		Recorder r; Classifier<Ev> c(r);
		c.mouseMoved(1000);
		c.gameControllerButton(1490, 3, true);
		touch(c, 1500, 1, DOWN, 100, 100);
		c.mouseMoved(1530);
		touch(c, 1800, 1, UP, 150, 100);
		c.gameControllerButton(1805, 3, false);
		expect("GameController first: right drag once", r.log, {"press 3 (gc)", "release 3 (gc)"});
	}
	{	// ... or after the touch began, while it waits.
		Recorder r; Classifier<Ev> c(r);
		c.mouseMoved(1000);
		touch(c, 1500, 1, DOWN, 100, 100);
		c.gameControllerButton(1510, 1, true);
		c.mouseMoved(1530);
		touch(c, 1800, 1, UP, 150, 100);
		c.gameControllerButton(1802, 1, false);
		expect("GameController during the touch: one press", r.log, {"press 1 (gc)", "release 1 (gc)"});
	}
	{	// ... or only after a quick touch already clicked: dropped, no double click.
		Recorder r; Classifier<Ev> c(r);
		c.mouseMoved(1000);
		touch(c, 1500, 1, DOWN, 100, 100);
		touch(c, 1550, 1, UP, 100, 100);
		c.gameControllerButton(1560, 1, true);
		c.gameControllerButton(1570, 1, false);
		expect("late GameController press after a touch click", r.log, {"press 1 (touch)", "release 1 (touch)"});
	}
	{	// GameController alone (no AssistiveTouch touches, e.g. an iPad): its presses go through.
		Recorder r; Classifier<Ev> c(r);
		c.mouseMoved(1000);
		c.gameControllerButton(1100, 1, true);
		c.mouseMoved(1150);
		c.gameControllerButton(1400, 1, false);
		c.gameControllerButton(2000, 2, true);
		c.gameControllerButton(2100, 2, false);
		expect("GameController only, with the middle button", r.log,
			{"press 1 (gc)", "release 1 (gc)", "press 2 (gc)", "release 2 (gc)"});
	}
	{	// A real finger on the trackpad right after using the mouse: it moves on its own, so it is a
		// finger, replayed from its start.
		Recorder r; Classifier<Ev> c(r);
		c.mouseMoved(1000);
		touch(c, 1500, 1, DOWN, 100, 100);
		touch(c, 1540, 1, MOVE, 110, 100);	// too early to decide
		touch(c, 1600, 1, MOVE, 130, 100);
		touch(c, 1650, 1, MOVE, 160, 100);
		touch(c, 1700, 1, UP, 160, 100);
		expect("finger after the mouse", r.log,
			{"finger 1 down", "finger 1 move", "finger 1 move", "finger 1 move", "finger 1 up"});
	}
	{	// A quick finger swipe that ends before DECIDE_MS is still a finger.
		Recorder r; Classifier<Ev> c(r);
		c.mouseMoved(1000);
		touch(c, 1500, 1, DOWN, 100, 100);
		touch(c, 1530, 1, MOVE, 140, 100);
		touch(c, 1560, 1, UP, 180, 100);
		expect("quick finger swipe", r.log, {"finger 1 down", "finger 1 move", "finger 1 up"});
	}
	{	// A cancelled candidate does nothing.
		Recorder r; Classifier<Ev> c(r);
		c.mouseMoved(1000);
		touch(c, 1500, 1, DOWN, 100, 100);
		touch(c, 1520, 1, CANCEL, 100, 100);
		expect("cancelled candidate", r.log, {});
	}
	{	// The mouse goes away while its button is held: released; a waiting touch becomes a finger.
		Recorder r; Classifier<Ev> c(r);
		c.mouseMoved(1000);
		touch(c, 1500, 1, DOWN, 100, 100);
		c.mouseMoved(1520);
		touch(c, 1530, 2, DOWN, 300, 300);
		c.reset();
		expect("mouse gone", r.log, {"press 1 (touch)", "release 1 (touch)", "finger 2 down"});
	}
	{	// The mouse idle for longer than RECENT_MS: touches are fingers again.
		Recorder r; Classifier<Ev> c(r);
		c.mouseMoved(1000);
		touch(c, 1000 + RECENT_MS + 1, 1, DOWN, 100, 100);
		touch(c, 1000 + RECENT_MS + 50, 1, UP, 100, 100);
		expect("mouse idle", r.log, {"finger 1 down", "finger 1 up"});
	}
	printf("%s\n", s_failures == 0 ? "all passed" : "FAILURES");
	return s_failures == 0 ? 0 : 1;
}
