import SwiftUI

struct ControlsView: View {
    @EnvironmentObject var ble: BLEManager

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)

    @State private var red: Double = 255
    @State private var green: Double = 255
    @State private var blue: Double = 255

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            powerSection
            Divider()
            colorSection
            Divider()
            brightnessSection
            Divider()
            quickColorsSection
            Divider()
            effectsSection
            Divider()
            speedSection
            Divider()
            breatheSection
        }
    }

    // MARK: - Power

    private var powerSection: some View {
        HStack(spacing: 8) {
            Text("Power")
                .font(.headline)
            Spacer()
            Button("On") { ble.sendPowerOn() }
                .buttonStyle(.borderedProminent)
                .tint(ble.isPoweredOn ? .green : .secondary)
                .controlSize(.small)

            Button("Off") { ble.sendPowerOff() }
                .buttonStyle(.borderedProminent)
                .tint(!ble.isPoweredOn ? .red : .secondary)
                .controlSize(.small)
        }
    }

    // MARK: - Color

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Color")
                    .font(.headline)
                Spacer()
                RoundedRectangle(cornerRadius: 4)
                    .fill(ble.currentColor)
                    .frame(width: 44, height: 22)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.primary.opacity(0.2), lineWidth: 1))
            }
            colorSliderRow(label: "R", value: $red, tint: .red)
            colorSliderRow(label: "G", value: $green, tint: .green)
            colorSliderRow(label: "B", value: $blue, tint: .blue)
        }
        .onAppear { syncSlidersFromColor(ble.currentColor) }
        .onChange(of: ble.currentColor) { syncSlidersFromColor($0) }
        .onChange(of: red) { _ in sendCurrentColor() }
        .onChange(of: green) { _ in sendCurrentColor() }
        .onChange(of: blue) { _ in sendCurrentColor() }
    }

    private func colorSliderRow(label: String, value: Binding<Double>, tint: Color) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 12)
            Slider(value: value, in: 0...255, step: 1)
                .tint(tint)
            Text("\(Int(value.wrappedValue))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 28, alignment: .trailing)
        }
    }

    private func syncSlidersFromColor(_ color: Color) {
        let (r, g, b) = color.rgbComponents
        red = Double(r); green = Double(g); blue = Double(b)
    }

    private func sendCurrentColor() {
        ble.sendColor(Color(red: red / 255, green: green / 255, blue: blue / 255))
    }

    // MARK: - Brightness

    private var brightnessSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Brightness")
                    .font(.headline)
                Spacer()
                Text("\(Int(ble.brightness))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 36, alignment: .trailing)
            }
            Slider(value: Binding(
                get: { ble.brightness },
                set: { ble.sendBrightness($0) }
            ), in: 1...100, step: 1)
        }
    }

    // MARK: - Quick Colors

    private var quickColorsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick Colors")
                .font(.headline)
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(PresetColor.all) { preset in
                    Button(action: {
                        ble.sendColor(preset.color)
                    }) {
                        VStack(spacing: 2) {
                            Circle()
                                .fill(preset.color)
                                .frame(width: 24, height: 24)
                                .overlay(
                                    Circle().stroke(Color.white.opacity(0.3), lineWidth: 1)
                                )
                            Text(preset.name)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Effects

    private var effectsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Effects")
                .font(.headline)
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(EffectMode.builtIn) { mode in
                    Button(action: { ble.sendEffect(mode.id) }) {
                        VStack(spacing: 2) {
                            Text("\(mode.id)")
                                .font(.system(size: 11, weight: .semibold))
                                .monospacedDigit()
                            Text(mode.name)
                                .font(.system(size: 9))
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(ble.activeEffectID == mode.id
                            ? Color.accentColor.opacity(0.25)
                            : Color(nsColor: .controlBackgroundColor).opacity(0.5))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(ble.activeEffectID == mode.id ? Color.accentColor : Color.clear,
                                        lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Breathe

    private var breatheSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Breathe")
                    .font(.headline)
                Spacer()
                Button(ble.isBreathing ? "Stop" : "Start") {
                    if ble.isBreathing {
                        ble.stopBreathing()
                    } else {
                        ble.startBreathing()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(ble.isBreathing ? .orange : .accentColor)
                .controlSize(.small)
            }
            if !ble.isBreathing {
                HStack {
                    Text("Color")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if ble.breatheColor != nil {
                        Button("None") { ble.breatheColor = nil }
                            .font(.caption)
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                    }
                    ColorPicker("", selection: Binding(
                        get: { ble.breatheColor ?? .white },
                        set: { ble.breatheColor = $0 }
                    ), supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 44, height: 22)
                    .opacity(ble.breatheColor == nil ? 0.4 : 1)
                }
                HStack {
                    Text("Cycle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $ble.breatheCycleDuration, in: 1...10, step: 0.5)
                    Text("\(ble.breatheCycleDuration, specifier: "%.1f")s")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 36, alignment: .trailing)
                }
            }
        }
    }

    // MARK: - Speed

    private var speedSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Effect Speed")
                    .font(.headline)
                Spacer()
                Text("\(Int(ble.effectSpeed))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 28, alignment: .trailing)
            }
            Slider(value: Binding(
                get: { ble.effectSpeed },
                set: { ble.sendEffectSpeed($0) }
            ), in: 1...100, step: 1)
        }
    }
}
