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

// GeneralsX @feature iOS port 11/11/2026 External display decisions (ExternalDisplayPlan.swift): the
// pixels the game renders on a display, when its resolution follows the display, and the pointer.

import XCTest
@testable import GXLauncherCore

final class ExternalDisplayPlanTests: XCTestCase {
    /// The drawable and the game resolution for a display of `points` at `scale`.
    private func plan(_ w: Double, _ h: Double, scale: Double, maxHeight: Int = 1080) -> (Double, PixelSize, PixelSize?) {
        let s = ExternalRenderSize.drawableScale(points: (w, h), screenScale: scale, maxHeight: maxHeight)
        let drawable = ExternalRenderSize.pixels(points: (w, h), scale: s)
        return (s, drawable, ExternalRenderSize.gameResolution(drawable: drawable))
    }

    func testA1080pDisplayRendersAtItsOwnPixels() {
        let (s, drawable, game) = plan(1920, 1080, scale: 1)
        XCTAssertEqual(s, 1)
        XCTAssertEqual(drawable, PixelSize(width: 1920, height: 1080))
        XCTAssertEqual(game, PixelSize(width: 1920, height: 1080))
    }

    func testA4KDisplayIsCappedAt1080pWhicheverWayItCountsPoints() {
        // 3840x2160 points at scale 1, and 1920x1080 points at scale 2: both 1920x1080 pixels.
        XCTAssertEqual(plan(3840, 2160, scale: 1).1, PixelSize(width: 1920, height: 1080))
        XCTAssertEqual(plan(3840, 2160, scale: 1).0, 0.5)
        XCTAssertEqual(plan(1920, 1080, scale: 2).1, PixelSize(width: 1920, height: 1080))
        XCTAssertEqual(plan(1920, 1080, scale: 2).0, 1)
    }

    func testTheCapCanBeRaisedTo4K() {
        XCTAssertEqual(plan(3840, 2160, scale: 1, maxHeight: 2160).1, PixelSize(width: 3840, height: 2160))
    }

    func testSmallDisplaysAreNeverRenderedAboveTheirOwnPixels() {
        XCTAssertEqual(plan(1280, 720, scale: 1).1, PixelSize(width: 1280, height: 720))
        XCTAssertEqual(plan(1024, 768, scale: 1).1, PixelSize(width: 1024, height: 768))
    }

    func testOtherShapesKeepTheirShape() {
        // 16:10, 4:3 and 21:9: the display's own shape, never more pixels than 1920x1080.
        let budget = 1920 * 1080
        for (w, h) in [(1920.0, 1200.0), (1600.0, 1200.0), (2560.0, 1080.0), (3440.0, 1440.0), (5120.0, 1440.0)] {
            let (_, d, game) = plan(w, h, scale: 1)
            XCTAssertLessThanOrEqual(d.width * d.height, budget, "\(w)x\(h)")
            XCTAssertLessThanOrEqual(d.height, 1080, "\(w)x\(h)")
            XCTAssertEqual(Double(d.width) / Double(d.height), w / h, accuracy: 0.01, "\(w)x\(h)")
            XCTAssertNotNil(game, "\(w)x\(h)")
        }
        XCTAssertEqual(plan(1920, 1200, scale: 1).1, PixelSize(width: 1728, height: 1080))
        XCTAssertEqual(plan(1600, 1200, scale: 1).1, PixelSize(width: 1440, height: 1080))
    }

    func testTheWidthIsAlwaysEven() {
        // 2560x1080 scaled to the pixel budget gives an odd width at the plain scale.
        for w in stride(from: 1000.0, through: 6000.0, by: 7.0) {
            let (_, d, _) = plan(w, 1080, scale: 1)
            XCTAssertEqual(d.width % 2, 0, "\(w)x1080 -> \(d)")
        }
    }

    func testTooShortForTheInterfaceKeepsTheCurrentResolution() {
        // The simulator's default TV-out (720x480) and an old 800x480 panel: fitted with bars.
        XCTAssertNil(plan(720, 480, scale: 1).2)
        XCTAssertNil(plan(800, 480, scale: 1).2)
        XCTAssertEqual(plan(800, 600, scale: 1).2, PixelSize(width: 800, height: 600))
    }

    func testMaxHeightSetting() {
        XCTAssertEqual(ExternalRenderSize.maxHeight(environment: [:]), 1080)
        XCTAssertEqual(ExternalRenderSize.maxHeight(environment: ["GX_EXTERNAL_MAX_HEIGHT": "1440"]), 1440)
        XCTAssertEqual(ExternalRenderSize.maxHeight(environment: ["GX_EXTERNAL_MAX_HEIGHT": " 720 "]), 720)
        XCTAssertEqual(ExternalRenderSize.maxHeight(environment: ["GX_EXTERNAL_MAX_HEIGHT": "100"]), 1080)
        XCTAssertEqual(ExternalRenderSize.maxHeight(environment: ["GX_EXTERNAL_MAX_HEIGHT": "4320"]), 1080)
        XCTAssertEqual(ExternalRenderSize.maxHeight(environment: ["GX_EXTERNAL_MAX_HEIGHT": "big"]), 1080)
    }

    // MARK: - Resolution plan

    private let phone = PixelSize(width: 2868, height: 1320)
    private let tv = PixelSize(width: 1920, height: 1080)

    func testNoDisplayKeepsThePhoneResolution() {
        var p = ResolutionPlan(phone: phone)
        XCTAssertEqual(p.wanted, phone)
        XCTAssertFalse(p.tick(now: 100))
        XCTAssertEqual(p.wanted, phone)
    }

    func testConnectWantsTheDisplayResolution() {
        var p = ResolutionPlan(phone: phone)
        p.displayConnected(resolution: tv)
        XCTAssertEqual(p.wanted, tv)
    }

    func testUnplugGivesThePhoneResolutionBackAfterTheGrace() {
        var p = ResolutionPlan(phone: phone)
        p.displayConnected(resolution: tv)
        p.displayDisconnected(now: 10)
        XCTAssertFalse(p.tick(now: 11.9))
        XCTAssertEqual(p.wanted, tv)
        XCTAssertTrue(p.tick(now: 12.0))
        XCTAssertEqual(p.wanted, phone)
        XCTAssertFalse(p.tick(now: 13), "comes back once")
    }

    func testAnAppSwitchChangesNothing() {
        // The app leaves the foreground: iOS takes the display's scene away, and gives it back on
        // return. The resolution never changes.
        var p = ResolutionPlan(phone: phone)
        p.displayConnected(resolution: tv)
        p.appActivity(active: false, now: 10)
        p.displayDisconnected(now: 10.1)
        XCTAssertFalse(p.tick(now: 60), "away in the background for a minute")
        XCTAssertEqual(p.wanted, tv)
        p.appActivity(active: true, now: 70)
        XCTAssertFalse(p.tick(now: 70.5))
        p.displayConnected(resolution: tv)
        XCTAssertFalse(p.tick(now: 80))
        XCTAssertEqual(p.wanted, tv)
    }

    func testUnpluggedWhileInTheBackgroundComesBackOnlyAfterTheAppIsActive() {
        var p = ResolutionPlan(phone: phone)
        p.displayConnected(resolution: tv)
        p.appActivity(active: false, now: 10)
        p.displayDisconnected(now: 10)
        XCTAssertFalse(p.tick(now: 100))
        p.appActivity(active: true, now: 100)
        XCTAssertFalse(p.tick(now: 101.5))
        XCTAssertTrue(p.tick(now: 102))
        XCTAssertEqual(p.wanted, phone)
    }

    func testTheAppGoingInactiveDuringTheGraceRestartsIt() {
        var p = ResolutionPlan(phone: phone)
        p.displayConnected(resolution: tv)
        p.displayDisconnected(now: 10)
        p.appActivity(active: false, now: 11)
        XCTAssertFalse(p.tick(now: 15))
        p.appActivity(active: true, now: 15)
        XCTAssertFalse(p.tick(now: 16.9))
        XCTAssertTrue(p.tick(now: 17))
    }

    func testAModeChangeOnTheDisplayKeepsItDockedWithTheNewResolution() {
        var p = ResolutionPlan(phone: phone)
        p.displayConnected(resolution: tv)
        p.displayDisconnected(now: 10)
        p.displayConnected(resolution: PixelSize(width: 1280, height: 720))
        XCTAssertFalse(p.tick(now: 20))
        XCTAssertEqual(p.wanted, PixelSize(width: 1280, height: 720))
    }

    func testADisplayTooSmallForTheInterfaceWantsThePhoneResolution() {
        var p = ResolutionPlan(phone: phone)
        p.displayConnected(resolution: nil)
        XCTAssertEqual(p.wanted, phone)
    }

    func testUnknownPhoneResolutionStillFollowsTheDisplay() {
        var p = ResolutionPlan()
        XCTAssertNil(p.wanted)
        p.displayConnected(resolution: tv)
        XCTAssertEqual(p.wanted, tv)
        p.phone = phone
        p.displayDisconnected(now: 0)
        XCTAssertTrue(p.tick(now: 3))
        XCTAssertEqual(p.wanted, phone)
    }

    // MARK: - Pointer

    func testFingerGainCrossesThePictureInSixtyPercentOfThePad() {
        // An iPhone Duo inner display held landscape (~1000x700 points) driving a 1920x1080 picture.
        let gain = PointerMapping.fingerGain(pad: (1000, 700), picture: (1920, 1080))
        let swipe = 0.6 * 1000 * gain * PointerMapping.engineSpeed
        XCTAssertEqual(swipe, 1920, accuracy: 0.5)
        // A pad taller than the picture's shape: the height decides, so both axes reach the edge.
        let tall = PointerMapping.fingerGain(pad: (700, 1000), picture: (1920, 1080))
        XCTAssertGreaterThanOrEqual(0.6 * 700 * tall * PointerMapping.engineSpeed, 1920 - 0.5)
        XCTAssertGreaterThanOrEqual(0.6 * 1000 * tall * PointerMapping.engineSpeed, 1080 - 0.5)
    }

    func testFingerGainHasAFloor() {
        XCTAssertEqual(PointerMapping.fingerGain(pad: (2000, 2000), picture: (100, 100)), 0.25)
        XCTAssertEqual(PointerMapping.fingerGain(pad: (0, 0), picture: (1920, 1080)),
                       1920 / (0.6 * 1.6), accuracy: 0.001)
    }

    func testHoverCoversThePictureCornerToCorner() {
        let pad = (1000.0, 700.0), picture = (1920.0, 1080.0)
        let tl = PointerMapping.hoverPoint((0, 0), pad: pad, picture: picture)
        XCTAssertEqual(tl.x, 0); XCTAssertEqual(tl.y, 0)
        let mid = PointerMapping.hoverPoint((500, 350), pad: pad, picture: picture)
        XCTAssertEqual(mid.x, 960); XCTAssertEqual(mid.y, 540)
        let br = PointerMapping.hoverPoint((1000, 700), pad: pad, picture: picture)
        XCTAssertEqual(br.x, 1919); XCTAssertEqual(br.y, 1079)
        let out = PointerMapping.hoverPoint((-50, 900), pad: pad, picture: picture)
        XCTAssertEqual(out.x, 0); XCTAssertEqual(out.y, 1079)
    }
}
