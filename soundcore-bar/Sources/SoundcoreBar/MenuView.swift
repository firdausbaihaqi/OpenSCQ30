import ServiceManagement
import SwiftUI

struct MenuView: View {
    let model: EarbudsModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(MenuBarIcon.storageKey) private var menuBarIcon = MenuBarIcon.currentMode
    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginItemError: String?
    @State private var showsEqualizerEditor = false

    struct Option {
        let value: String
        let title: String
        let symbol: String
    }

    static let modes = [
        Option(value: "NoiseCanceling", title: "Noise Cancelling", symbol: "waveform.badge.minus"),
        Option(value: "Transparency", title: "Transparency", symbol: "ear.and.waveform"),
        Option(value: "Normal", title: "Off", symbol: "ear"),
    ]
    private static let ancModes = [
        Option(value: "Adaptive", title: "Adaptive", symbol: "sparkles"),
        Option(value: "Manual", title: "Manual", symbol: "dial.medium"),
        Option(value: "MultiScene", title: "Scene", symbol: "dot.radiowaves.left.and.right"),
    ]
    private static let scenes = [
        Option(value: "Transport", title: "Transport", symbol: "tram.fill"),
        Option(value: "Outdoor", title: "Outdoor", symbol: "tree.fill"),
        Option(value: "Indoor", title: "Indoor", symbol: "house.fill"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if model.isConnected == false {
                disconnectedModule
            } else {
                Group {
                    modeModule
                    if model.ambientSoundMode == "NoiseCanceling" || !model.isLoaded {
                        ancModule.transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    eqModule
                }
                .redacted(reason: model.isLoaded ? [] : .placeholder)
                .disabled(!model.isLoaded)
            }
            if let error = model.error, model.isConnected != false {
                errorBanner(error) { Task { await model.refresh() } }
            }
            if let loginItemError {
                errorBanner(loginItemError, action: ("Open Settings", SMAppService.openSystemSettingsLoginItems))
            }
        }
        .padding(12)
        .frame(width: 300)
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: model.ambientSoundMode)
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: model.noiseCancelingMode)
        .task {
            // Login Items can be changed in System Settings while the app runs.
            opensAtLogin = SMAppService.mainApp.status == .enabled
            await model.refresh()
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: 10) {
            EarbudsArt(appeared: true, animates: false, budHeight: 33)
                .frame(width: 44, height: 44)
                .saturation(model.isConnected == false ? 0 : 1)
                .opacity(model.isConnected == false ? 0.45 : 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("R50i NC").font(.headline).fixedSize()
                    if model.isBusy { ProgressView().controlSize(.mini) }
                }
                if model.isConnected != false, model.batteryLeft != nil || model.batteryRight != nil {
                    HStack(spacing: 10) {
                        if let left = model.batteryLeft { batteryLabel("L", left) }
                        if let right = model.batteryRight { batteryLabel("R", right) }
                    }
                }
            }
            Spacer()
            Menu {
                Button("Refresh") { Task { await model.refresh() } }
                Divider()
                Toggle("Open at Login", isOn: Binding(get: { opensAtLogin }, set: { setOpensAtLogin($0) }))
                Picker("Menu Bar Icon", selection: $menuBarIcon) {
                    ForEach(MenuBarIcon.allCases, id: \.self) { icon in
                        Label(icon.title, systemImage: icon.symbol(for: model.ambientSoundMode))
                    }
                }
                Divider()
                Button("Quit SoundcoreBar") { NSApplication.shared.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 4)
    }

    private var modeModule: some View {
        HStack(spacing: 0) {
            ForEach(Self.modes, id: \.value) { mode in
                ModeButton(option: mode, isSelected: model.ambientSoundMode == mode.value) {
                    model.set("ambientSoundMode", .string(mode.value))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 12)
        .module()
    }

    private var ancModule: some View {
        VStack(alignment: .leading, spacing: 10) {
            ChipRow(options: Self.ancModes, selected: model.noiseCancelingMode) {
                model.set("noiseCancelingMode", .string($0))
            }
            switch model.noiseCancelingMode {
            case "Manual":
                LevelPicker(level: model.manualLevel) { model.set("manualNoiseCanceling", .int($0)) }
            case "MultiScene":
                ChipRow(options: Self.scenes, selected: model.multiScene) {
                    model.set("multiSceneNoiseCanceling", .string($0))
                }
            default:
                Text("Adjusts to your surroundings automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 2)
            }
        }
        .padding(10)
        .module()
    }

    private var eqModule: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Button {
                    showsEqualizerEditor.toggle()
                } label: {
                    Image(systemName: "slider.vertical.3")
                        .frame(width: 28, height: 28)
                        .foregroundStyle(showsEqualizerEditor ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                        .background(Circle().fill(showsEqualizerEditor ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary)))
                }
                .buttonStyle(PressStyle())
                .help("Customize EQ")
                .accessibilityLabel("Customize EQ")
                // Title over the active EQ, like a Control Center module, so a long name never squeezes the title.
                VStack(alignment: .leading, spacing: 1) {
                    Text("Equalizer")
                    Text(model.eqPreset.map(Self.presetTitle) ?? model.customProfile ?? "Custom")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 8)
                Menu {
                    ForEach(EarbudsModel.eqPresets, id: \.self) { preset in
                        checkmarkButton(Self.presetTitle(preset), isSelected: preset == model.eqPreset) {
                            model.set("presetEqualizerProfile", .string(preset))
                        }
                    }
                    if !model.customProfiles.isEmpty {
                        Section("My EQs") {
                            ForEach(model.customProfiles, id: \.self) { name in
                                checkmarkButton(name, isSelected: name == model.customProfile) {
                                    model.applyCustomProfile(name)
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "chevron.up.chevron.down")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Choose EQ preset")
                .accessibilityLabel("EQ preset")
            }
            if showsEqualizerEditor {
                EqualizerEditor(
                    bands: model.eqBands,
                    customProfile: model.customProfile,
                    isBusy: model.isBusy,
                    onCommit: { model.set("volumeAdjustments", .ints($0)) },
                    onSave: { name in Task { await model.saveCustomProfile(name) } },
                    onDelete: { name in Task { await model.deleteCustomProfile(name) } }
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(10)
        .module()
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: showsEqualizerEditor)
    }

    private var disconnectedModule: some View {
        VStack(spacing: 10) {
            Image(systemName: "earbuds")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
                .frame(width: 48, height: 48)
                .background(Circle().fill(.quaternary))
            Text("Not connected").font(.subheadline.weight(.medium))
            Text("Take the earbuds out of the case, or connect them in Bluetooth settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Bluetooth Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!)
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .module()
    }

    private func checkmarkButton(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if isSelected { Label(title, systemImage: "checkmark") } else { Text(title) }
        }
    }

    private func errorBanner(_ message: String, retry: @escaping () -> Void) -> some View {
        errorBanner(message, action: ("Retry", retry)).disabled(model.isBusy)
    }

    private func errorBanner(_ message: String, action: (title: String, run: () -> Void)) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).font(.caption).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action.title, action: action.run).controlSize(.small)
        }
        .padding(10)
        .module()
    }

    private func setOpensAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginItemError = SMAppService.mainApp.status == .requiresApproval
                ? "Allow SoundcoreBar in Login Items to open it at login."
                : nil
        } catch {
            loginItemError = "Couldn't update Open at Login: \(error.localizedDescription)"
        }
        opensAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func batteryLabel(_ side: String, _ battery: EarbudsModel.Battery) -> some View {
        Label {
            Text("\(side) \(Int(battery.level * 100))%").monospacedDigit()
        } icon: {
            Image(systemName: battery.isCharging ? "battery.100.bolt" : "battery.\(Int((battery.level * 4).rounded()) * 25)")
        }
        .labelStyle(.titleAndIcon)
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize()
    }

    // "BassBooster" -> "Bass Booster"; "RnB" is the one ID that isn't camel case.
    private static func presetTitle(_ id: String) -> String {
        if id == "RnB" { return "R&B" }
        var title = ""
        for (i, char) in id.enumerated() {
            if i > 0, char.isUppercase, id[id.index(id.startIndex, offsetBy: i - 1)].isLowercase { title.append(" ") }
            title.append(char)
        }
        return title
    }

    // MARK: Controls

    private struct ModeButton: View {
        let option: Option
        let isSelected: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                VStack(spacing: 6) {
                    Image(systemName: option.symbol)
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 42, height: 42)
                        .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                        .background(Circle().fill(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary)))
                    Text(option.title)
                        .font(.caption)
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }

    private struct ChipRow: View {
        let options: [Option]
        let selected: String?
        let onSelect: (String) -> Void

        var body: some View {
            HStack(spacing: 6) {
                ForEach(options, id: \.value) { option in
                    let isSelected = option.value == selected
                    Button { onSelect(option.value) } label: {
                        Label(option.title, systemImage: option.symbol)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary))
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
    }

    /// Five bars of rising height; bars up to the current level are filled.
    private struct LevelPicker: View {
        let level: Int?
        let onSelect: (Int) -> Void

        var body: some View {
            HStack(alignment: .bottom, spacing: 6) {
                Text("Strength").font(.caption).foregroundStyle(.secondary)
                Spacer()
                ForEach(1...5, id: \.self) { step in
                    Button { onSelect(step) } label: {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(step <= (level ?? 0) ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary))
                            .frame(width: 22, height: 8 + CGFloat(step) * 4)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("Strength \(step)")
                    .accessibilityAddTraits(step == level ? .isSelected : [])
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private struct PressStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.94 : 1)
                .animation(.snappy(duration: 0.15), value: configuration.isPressed)
        }
    }
}

private extension View {
    /// Control Center style module: one radius for every card in the panel.
    func module() -> some View {
        background(.fill.quinary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
