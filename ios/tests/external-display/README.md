# External display harness (iOS Simulator)

The game cannot render in the Simulator (DXVK needs a Vulkan 1.2 feature its GPU lacks), so this
small SDL3 app stands in for the engine around the production pieces of the external display
support: the game build's patched SDL3, the launcher library with `ExternalDisplay.swift` and
`ExternalDisplayPad.swift`, and the same calls `SDL3Main.cpp` and `SDL3GameEngine.cpp` make. SDL's
Metal renderer draws a test card into the same kind of Metal view DXVK renders into: a 1-pixel
border at the drawable's edge, a circle that must stay round, and text with the window's points,
SDL's pixel size, the drawable and the resolution the game would want. Every change is logged as
`HARNESS ...`; the support itself logs as `[GX-Launcher] external display: ...`.

Build the simulator tree first (`ios-vulkan-sim` preset in a `CMakeUserPresets.json`, as in the
earlier simulator builds), then:

```sh
ios/tests/external-display/build-harness.sh            # -> build/ext-harness/GXExternalDisplayHarness.app
xcrun simctl install <udid> build/ext-harness/GXExternalDisplayHarness.app
xcrun simctl io <udid> screenConfig --display=2 geometry 1920x1080@1    # or 3840x2160@1, 1920x1080@2, 1024x768@1, 720x480@1
SIMCTL_CHILD_GX_LAUNCHER_SKIP=1 xcrun simctl launch --console-pty <udid> org.generalsx.externaldisplayharness
xcrun simctl io <udid> screenConfig --display=2 power on               # plug in; "power off" unplugs
xcrun simctl io <udid> screenshot --display=2 display.png               # display 1 is the phone
```

Switches (prefix with `SIMCTL_CHILD_` for `simctl launch`):

- `HARNESS_LAUNCHER_SECONDS=n` waits n seconds before making the window, as a player in the
  launcher would: a display already on shows the title card, and the "game" starts at its resolution.
- `HARNESS_SCRIPTED_PAD=1` drives the pad's C callback with a drag, a tap, a two-finger tap and a
  mouse hover and click (the Simulator offers no scripted touches to a non-interactive test).

Simulator quirks: some mode changes leave the display with no scene until the next change; the
Simulator only offers some modes (1920x1080, 1280x720, 3840x2160, 1024x768, 720x480 at scale 1).
