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

// GeneralsX @feature iOS port 11/11/2026 External display: the decisions, without UIKit.
//
// With a monitor or TV attached (USB-C, or AirPlay), iOS gives the app a scene of its own on it.
// The game's window moves there (ExternalDisplay.swift) and the phone becomes the trackpad. What
// this file decides, so it can be tested on the Mac (`swift test`):
//
//   - the pixels the game renders on the display: the display's own shape, at most as many pixels
//     as 1920x1080 and at most 1080 high by default (a 4K drawable costs four times the GPU time
//     and has shown black over AirPlay); Options.ini's GXExternalMaxHeight (passed on by the
//     launcher as GX_EXTERNAL_MAX_HEIGHT, LaunchPlan) moves that cap between 720 and 2160 lines;
//   - the scale of the game's Metal view that gives those pixels (SDL reports the same size,
//     Patches/sdl3-ios-metal-view-pixel-size.patch);
//   - when the game's resolution follows the display, and when it goes back to the phone's:
//     iOS takes the display's scene away whenever the app leaves the foreground and gives it back
//     on return, and a display that changes its mode disconnects and connects again, so the
//     phone's resolution comes back only once the app is active and the display has stayed away
//     for two seconds (ResolutionPlan);
//   - how far the game's pointer moves for a finger on the phone, and where a mouse hovering
//     over the phone puts it (PointerMapping).

import Foundation

/// A size in whole pixels.
public struct PixelSize: Equatable, CustomStringConvertible, Sendable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public var description: String { "\(width)x\(height)" }
}

/// How the game's picture is sized for an external display.
public enum ExternalRenderSize {
    /// About 1080p: the default cap of the drawable.
    public static let defaultMaxHeight = 1080
    /// The setting's range.
    public static let maxHeightRange = 720...2160
    /// The setting: Options.ini's key, which the launcher passes on in this variable (LaunchPlan).
    public static let maxHeightKey = "GXExternalMaxHeight"
    public static let maxHeightVariable = "GX_EXTERNAL_MAX_HEIGHT"
    /// The engine's interface is laid out for 600 lines and more (SDL3Main.cpp, OptionsMenu).
    public static let minimumGameHeight = 600

    /// GX_EXTERNAL_MAX_HEIGHT when it is a number in maxHeightRange, else the default.
    public static func maxHeight(environment: [String: String]) -> Int {
        guard let text = environment[maxHeightVariable]?.trimmingCharacters(in: .whitespaces),
              let value = Int(text), maxHeightRange.contains(value) else {
            return defaultMaxHeight
        }
        return value
    }

    /// The Metal view's pixels per point on a display whose window is `points` large and whose
    /// screen has `screenScale` pixels per point: the screen's own, lowered so that the drawable
    /// has at most as many pixels as a 16:9 picture `maxHeight` lines high and is at most
    /// `maxHeight` high. Never above the screen's scale (no rendering finer than the display).
    ///
    /// The width it gives (the points times the scale, truncated as SDL and the layer do) is even,
    /// like every resolution the engine picks: when the plain scale would give an odd width, the
    /// scale is taken a quarter pixel above the next even width down.
    public static func drawableScale(points: (width: Double, height: Double), screenScale: Double,
                                     maxHeight: Int) -> Double {
        let w = max(points.width, 1), h = max(points.height, 1)
        let screen = max(screenScale, 0.01)
        let budget = Double(maxHeight) * Double(maxHeight) * 16.0 / 9.0
        var scale = min(screen, Double(maxHeight) / h, (budget / (w * h)).squareRoot())
        let width = Int(w * scale)
        if width % 2 != 0, width > 1 {
            scale = (Double(width - 1) + 0.25) / w
        }
        return scale
    }

    /// The drawable a scale gives, truncated the way SDL_uikitwindow.m and SDL_uikitmetalview.m do.
    public static func pixels(points: (width: Double, height: Double), scale: Double) -> PixelSize {
        PixelSize(width: Int(points.width * scale), height: Int(points.height * scale))
    }

    /// The game's resolution for a drawable: the drawable itself (the game renders 1:1 into it),
    /// the width made even. nil when it is too short for the game's interface: then the game keeps
    /// the resolution it has and the picture is fitted into the display with bars.
    public static func gameResolution(drawable: PixelSize) -> PixelSize? {
        let width = drawable.width & ~1
        guard width > 0, drawable.height >= minimumGameHeight else { return nil }
        return PixelSize(width: width, height: drawable.height)
    }
}

/// Which resolution the game should have: the phone's, or the display's while the picture is
/// there. The engine applies it when it can (at the menus, OptionsMenu's own path); this only
/// says what it should be, and when the phone's comes back.
public struct ResolutionPlan: Equatable, Sendable {
    /// How long the display must stay away, with the app active, before the phone's resolution
    /// comes back.
    public static let graceSeconds: Double = 2.0

    /// The resolution the game would have on the phone (SDL3Main.cpp, at start).
    public var phone: PixelSize?
    /// The resolution for the display the picture is on, or was on last.
    public private(set) var external: PixelSize?
    /// Whether the game should have the display's resolution.
    public private(set) var docked = false
    /// Whether a display scene is connected now.
    public private(set) var connected = false
    /// Whether the phone's scene is foreground-active.
    public private(set) var appActive = true
    /// Since when the display has been away while the app was active (nil: not both).
    public private(set) var awayActiveSince: Double?

    public init(phone: PixelSize? = nil) {
        self.phone = phone
    }

    /// The resolution the game should have now; nil when nothing is known.
    public var wanted: PixelSize? {
        docked ? (external ?? phone) : phone
    }

    /// The picture went to a display. `resolution` nil: the display is too small for the game's
    /// interface, the game keeps its resolution and the picture is fitted with bars.
    public mutating func displayConnected(resolution: PixelSize?) {
        connected = true
        awayActiveSince = nil
        if let resolution {
            external = resolution
            docked = true
        } else {
            docked = false
        }
    }

    /// The display's scene went away (unplugged, the app left the foreground, a mode change).
    public mutating func displayDisconnected(now: Double) {
        connected = false
        awayActiveSince = appActive ? now : nil
    }

    /// The phone's scene became active, or stopped being active.
    public mutating func appActivity(active: Bool, now: Double) {
        appActive = active
        if connected { return }
        awayActiveSince = active ? (awayActiveSince ?? now) : nil
    }

    /// Call from time to time (each frame is fine). Returns true when the phone's resolution has
    /// just come back.
    @discardableResult
    public mutating func tick(now: Double) -> Bool {
        guard docked, !connected, let since = awayActiveSince, appActive else { return false }
        guard now - since >= Self.graceSeconds else { return false }
        docked = false
        return true
    }
}

/// From the phone's surface to the game's pointer on the display.
public enum PointerMapping {
    /// The engine's own pointer speed for a finger (SDL3GameEngine.cpp, PAD_SPEED).
    public static let engineSpeed = 1.6
    /// A swipe across this share of the pad crosses the whole picture.
    public static let padShareForPicture = 0.6

    /// Display points per pad point for finger motion: with the engine's speed applied on top, a
    /// swipe across `padShareForPicture` of the pad crosses the whole picture on its longer
    /// relative axis. At least 0.25 so a small display does not make the pointer crawl.
    public static func fingerGain(pad: (width: Double, height: Double),
                                  picture: (width: Double, height: Double)) -> Double {
        let padW = max(pad.width, 1), padH = max(pad.height, 1)
        let ratio = max(picture.width / padW, picture.height / padH)
        return max(ratio / (padShareForPicture * engineSpeed), 0.25)
    }

    /// A mouse hovering over the phone: the pad stands for the whole picture, each axis on its own,
    /// so every corner of the picture can be reached without the phone's own pointer leaving the
    /// pad. The result is clamped to the picture.
    public static func hoverPoint(_ point: (x: Double, y: Double), pad: (width: Double, height: Double),
                                  picture: (width: Double, height: Double)) -> (x: Double, y: Double) {
        let padW = max(pad.width, 1), padH = max(pad.height, 1)
        let x = min(max(point.x / padW, 0), 1) * picture.width
        let y = min(max(point.y / padH, 0), 1) * picture.height
        return (min(x, max(picture.width - 1, 0)), min(y, max(picture.height - 1, 0)))
    }
}
