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

// GeneralsX @feature iOS launcher 25/10/2026 Interface: Interface Size (Options.ini GXUiScale),
// Menu Text Size (Options.ini ResolutionFontAdjustment), the control scheme (control_scheme:
// attack-move, army buttons and minimap camera; the higher camera, also stored there, is on
// Home > Options) and
// mouse/touchpad mode (mouse_mode). Defaults are the Android launcher's; Interface Size also goes
// down to 70% and Menu Text Size moves in steps of 10. Values are saved as they change -- no Apply
// button. Interface Size, the control scheme and mouse mode take effect when Play is tapped (the
// engine re-reads them when the launcher is shown over the running game); Menu Text Size is read
// when the app starts.

#if canImport(UIKit) && os(iOS)
import SwiftUI
import GXLauncherCore

struct InterfaceView: View {
    @ObservedObject var model: LauncherModel

    var body: some View {
        Form {
            interfaceSizeSection
            menuTextSection
            controlSchemeSection
            mouseSection
        }
        .navigationTitle(L("Interface"))
    }

    // MARK: Interface Size

    private var interfaceSizeSection: some View {
        Section {
            PercentSlider(title: L("Interface Size"),
                          value: model.interfaceScale,
                          range: InterfaceScale.range,
                          step: InterfaceScale.step,
                          onChange: model.setInterfaceScale)
            if model.interfaceScale != InterfaceScale.defaultPercent {
                Button(L("Reset to 100%")) { model.setInterfaceScale(InterfaceScale.defaultPercent) }
            }
        } header: {
            Text(L("Interface Size"))
        } footer: {
            Text(L("Above 100% the in-game interface grows: the control bar with the radar grows up from the bottom, and the generals' powers, chat, messages, menus and the main menu's buttons grow from where they sit, each only as far as the screen allows. Below 100% it shrinks, leaving more of the battlefield visible on large screens. Takes effect when you tap Play."))
        }
    }

    // MARK: Menu Text Size

    private var menuTextSection: some View {
        Section {
            PercentSlider(title: L("Menu Text Size"),
                          value: model.menuTextSize,
                          range: MenuTextSize.range,
                          step: MenuTextSize.step,
                          onChange: model.setMenuTextSize)
            if model.menuTextSize != MenuTextSize.defaultPercent {
                Button(L("Reset to the game's default (70%)")) { model.setMenuTextSize(MenuTextSize.defaultPercent) }
            }
        } header: {
            Text(L("Menu Text Size"))
        } footer: {
            Text(L("Scales most menu button and label text for the screen resolution. 70 is the game's own default; higher values make menu text bigger. Takes effect the next time the app starts."))
        }
    }

    // MARK: Control scheme

    private var schemeBinding: Binding<ControlScheme> {
        Binding(get: { model.controlScheme }, set: model.setControlScheme)
    }

    private var controlSchemeSection: some View {
        Section {
            Picker(L("Control scheme"), selection: Binding(
                get: { model.controlScheme.preset },
                set: { model.applyPreset($0) }
            )) {
                Text(L("Classic")).tag(ControlScheme.Preset.classic)
                Text(L("Tactical")).tag(ControlScheme.Preset.tactical)
                Text(L("Custom")).tag(ControlScheme.Preset.custom)
            }
            .pickerStyle(.segmented)
            .listRowSeparator(.hidden)

            Text(presetDescription(model.controlScheme.preset))
                .font(.footnote)
                .foregroundStyle(.secondary)

            Toggle(isOn: schemeBinding.attackMove) {
                SettingLabel(title: L("Attack on the move"),
                             detail: L("A move order for combat units is an attack-move: they fight what they meet on the way. Dozers and harvesters still just move."))
            }
            Toggle(isOn: schemeBinding.armyButtons) {
                SettingLabel(title: L("Army buttons"),
                             detail: L("The army column opens with the buttons that select every combat unit on screen or on the whole map, planes, helicopters or ground forces."))
            }
            Toggle(isOn: schemeBinding.minimapCamera) {
                SettingLabel(title: L("Minimap moves camera"),
                             detail: L("Tapping the minimap jumps the camera there even with units selected, and dragging on the minimap moves the camera with your finger. An armed ability or attack-move still targets through the minimap."))
            }
        } header: {
            Text(L("Control scheme"))
        } footer: {
            Text(L("Takes effect when you tap Play. Works in skirmish, the campaign and LAN games alike: only how your orders are given changes, not the game's rules."))
        }
    }

    private func presetDescription(_ preset: ControlScheme.Preset) -> String {
        switch preset {
        case .classic:
            return L("As in the original game: a move order just moves, the army column opens with the control groups only, and tapping the minimap with units selected sends them there.")
        case .tactical:
            return L("Combat units attack on the move, the army column opens with the army buttons too, and the minimap moves the camera.")
        case .custom:
            return L("Your own mix of the switches below.")
        }
    }

    // MARK: Mouse and touchpad

    private var mouseSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { model.mouseMode.enabled },
                set: { model.setMouseMode(MouseMode(enabled: $0, cursorPercent: model.mouseMode.cursorPercent)) }
            )) {
                SettingLabel(title: L("Mouse and touchpad"),
                             detail: L("A pointer instead of tapping where you want: a connected mouse works as on a PC, and without one your finger moves the cursor like a laptop touchpad."))
            }
            if model.mouseMode.enabled {
                PercentSlider(title: L("Cursor size"),
                              value: model.mouseMode.cursorPercent,
                              range: MouseMode.cursorRange,
                              step: MouseMode.cursorStep) {
                    model.setMouseMode(MouseMode(enabled: true, cursorPercent: $0))
                }
            }
        } footer: {
            Text(L("Touchpad: move a finger to move the cursor. Tap = left click, two taps = double click, two-finger tap = right click, two fingers = scroll the map, pinch = zoom. Takes effect when you tap Play."))
        }
    }
}

/// A titled percentage slider with the value read out on the right.
struct PercentSlider: View {
    let title: String
    let value: Int
    let range: ClosedRange<Int>
    let step: Int
    let onChange: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text((Double(value) / 100).formatted(.percent.precision(.fractionLength(0))))
                    .monospacedDigit()
                    .foregroundStyle(.tint)
            }
            slider
        }
        .accessibilityElement(children: .contain)
    }

    /// Stepped (with tick marks) for coarse ranges like Android's 10 % steps; continuous and
    /// rounded for fine ones, where 150 tick marks would just draw a grey bar.
    @ViewBuilder
    private var slider: some View {
        let binding = Binding(get: { Double(value) },
                              set: { onChange(Int(($0 / Double(step)).rounded()) * step) })
        let bounds = Double(range.lowerBound)...Double(range.upperBound)
        if (range.upperBound - range.lowerBound) / step <= 20 {
            Slider(value: binding, in: bounds, step: Double(step)) { Text(title) }
                minimumValueLabel: { bound(range.lowerBound) } maximumValueLabel: { bound(range.upperBound) }
        } else {
            Slider(value: binding, in: bounds) { Text(title) }
                minimumValueLabel: { bound(range.lowerBound) } maximumValueLabel: { bound(range.upperBound) }
        }
    }

    private func bound(_ number: Int) -> some View {
        Text("\(number)").font(.caption2).foregroundStyle(.secondary)
    }
}
#endif
