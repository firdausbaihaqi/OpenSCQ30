import Foundation
import Observation

@MainActor
@Observable
final class EarbudsModel {
    // Setting IDs and values as exposed by openscq30 for the A3959 (R50i NC).
    static let eqPresets = [
        "SoundcoreSignature", "Acoustic", "BassBooster", "BassReducer", "Classical", "Podcast",
        "Dance", "Deep", "Electronic", "Flat", "HipHop", "Jazz", "Latin", "Lounge", "Piano", "Pop",
        "RnB", "Rock", "SmallSpeakers", "SpokenWord", "TrebleBooster", "TrebleReducer",
    ]
    static let eqBandHz = [100, 200, 400, 800, 1600, 3200, 6400, 12800]
    /// Band gain in tenths of a dB.
    static let eqRange = -120...134
    private static let readIds = [
        "ambientSoundMode", "noiseCancelingMode", "manualNoiseCanceling", "multiSceneNoiseCanceling",
        "presetEqualizerProfile", "customEqualizerProfile", "volumeAdjustments",
        "batteryLevelLeft", "batteryLevelRight", "isChargingLeft", "isChargingRight",
    ]

    struct Battery {
        let level: Double
        let isCharging: Bool
    }

    private(set) var values: [String: OpenSCQ30.Value] = [:]
    private(set) var customProfiles: [String] = []
    /// nil until the paired device is known.
    private(set) var isConnected: Bool?
    private(set) var isBusy = false
    private(set) var error: String?

    var isLoaded: Bool { values["ambientSoundMode"] != nil }
    var ambientSoundMode: String? { values["ambientSoundMode"]?.string }
    var noiseCancelingMode: String? { values["noiseCancelingMode"]?.string }
    var manualLevel: Int? { values["manualNoiseCanceling"]?.int }
    var multiScene: String? { values["multiSceneNoiseCanceling"]?.string }
    /// nil while a custom EQ (no preset) is active.
    var eqPreset: String? { values["presetEqualizerProfile"]?.string }
    /// Name of the saved custom profile matching the current bands, if any.
    var customProfile: String? { values["customEqualizerProfile"]?.string }
    var eqBands: [Int] {
        if case .ints(let bands) = values["volumeAdjustments"], bands.count == Self.eqBandHz.count { return bands }
        return Array(repeating: 0, count: Self.eqBandHz.count)
    }
    var batteryLeft: Battery? { battery("Left") }
    var batteryRight: Battery? { battery("Right") }

    private let cli: OpenSCQ30
    private let connection = ConnectionMonitor()
    private let connectedPopup = ConnectedPopup()
    private var mac: String?
    private var profilesLoaded = false

    init(cli: OpenSCQ30) {
        self.cli = cli
        Task { await startMonitoring() }
    }

    func refresh() async {
        await perform([])
    }

    /// Updates the UI immediately and rolls back if the earbuds reject the change.
    func set(_ id: String, _ value: OpenSCQ30.Value) {
        let previous = values
        values[id] = value
        Task {
            if await !perform([(id, value.cliString)]) { values = previous }
        }
    }

    func applyCustomProfile(_ name: String) {
        // A leading +, - or \ would be read as an add/remove command.
        let escaped = ["+", "-", "\\"].contains(where: name.hasPrefix) ? "\\" + name : name
        let previous = values
        values["customEqualizerProfile"] = .string(name)
        values["presetEqualizerProfile"] = OpenSCQ30.Value.none
        Task {
            if await !perform([("customEqualizerProfile", escaped)]) { values = previous }
        }
    }

    /// Saves the current bands under `name`.
    func saveCustomProfile(_ name: String) async {
        guard await perform([("customEqualizerProfile", "+" + name)]) else { return }
        if !customProfiles.contains(name) { customProfiles.append(name) }
    }

    func deleteCustomProfile(_ name: String) async {
        guard await perform([("customEqualizerProfile", "-" + name)]) else { return }
        customProfiles.removeAll { $0 == name }
    }

    private func startMonitoring() async {
        guard let mac = await loadMac() else { return }
        connection.watch(mac: mac) { [weak self] connected in
            guard let self else { return }
            // Only a real disconnected -> connected transition, not the state reported at launch.
            let reconnected = connected && isConnected == false
            isConnected = connected
            guard connected else { return }
            if reconnected { connectedPopup.show(model: self) }
            // RFCOMM isn't accepting connections the instant the link comes up.
            Task {
                try? await Task.sleep(for: .seconds(2))
                await self.refresh()
            }
        }
    }

    private func loadMac() async -> String? {
        if let mac { return mac }
        do {
            mac = try await cli.firstPairedMac()
            if mac == nil { error = "No device paired with openscq30. Run: openscq30 paired-devices add" }
        } catch {
            self.error = error.localizedDescription
        }
        return mac
    }

    @discardableResult
    private func perform(_ sets: [(String, String)]) async -> Bool {
        // Skip the CLI while disconnected: it would take ~15 s just to fail.
        guard isConnected != false, let mac = await loadMac() else { return false }
        isBusy = true
        defer { isBusy = false }
        do {
            values = try await cli.settings(mac: mac, set: sets, get: Self.readIds)
            if !profilesLoaded {
                customProfiles = try await cli.customEqualizerProfiles(mac: mac)
                profilesLoaded = true
            }
            error = nil
            return true
        } catch {
            // The buds stop acking us while the phone's Soundcore app holds its own control session.
            self.error = error.localizedDescription.contains("until ack received")
                ? "Earbuds didn't respond. Close the Soundcore app on your phone, then retry."
                : error.localizedDescription
            return false
        }
    }

    // openscq30 reports battery as "9/10" and charging as "Yes"/"No".
    private func battery(_ side: String) -> Battery? {
        guard let raw = values["batteryLevel\(side)"]?.string else { return nil }
        let parts = raw.split(separator: "/").compactMap { Double($0) }
        guard parts.count == 2, parts[1] > 0 else { return nil }
        return Battery(level: parts[0] / parts[1], isCharging: values["isCharging\(side)"]?.string == "Yes")
    }
}
