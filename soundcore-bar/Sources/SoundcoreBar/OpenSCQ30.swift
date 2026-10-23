import Foundation

/// Thin wrapper around the bundled `openscq30` CLI.
/// Calls run one at a time: two CLI processes opening RFCOMM to the same device at once fail.
final class OpenSCQ30: Sendable {
    struct CLIError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    enum Value: Decodable, Sendable {
        case string(String)
        case int(Int)
        case ints([Int])
        case none

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() { self = .none }
            else if let v = try? container.decode(Int.self) { self = .int(v) }
            else if let v = try? container.decode([Int].self) { self = .ints(v) }
            else { self = .string(try container.decode(String.self)) }
        }

        var string: String? { if case .string(let v) = self { v } else { nil } }
        var int: Int? { if case .int(let v) = self { v } else { nil } }

        /// Value as accepted by `--set id=value`; `.none` clears an optional select.
        var cliString: String {
            switch self {
            case .string(let v): v
            case .int(let v): String(v)
            case .ints(let v): v.map(String.init).joined(separator: ",")
            case .none: ""
            }
        }
    }

    private struct SettingEntry: Decodable {
        struct Wrapped: Decodable { let value: Value? }
        let settingId: String
        let value: Wrapped
    }

    private struct PairedDevice: Decodable {
        let macAddress: String
    }

    private struct SettingInfo: Decodable {
        struct Options: Decodable { let options: [String]? }
        let setting: Options?
    }

    /// A failed connection attempt takes ~15 s, so anything well past that is a hung CLI.
    private static let timeout: TimeInterval = 25

    private let binary: URL
    private let queue = DispatchQueue(label: "openscq30.cli")

    init(binary: URL) {
        self.binary = binary
    }

    func firstPairedMac() async throws -> String? {
        let data = try await run(["paired-devices", "list", "--json"])
        return try JSONDecoder().decode([PairedDevice].self, from: data).first?.macAddress
    }

    /// Names of the custom EQ profiles openscq30 has stored locally.
    func customEqualizerProfiles(mac: String) async throws -> [String] {
        let data = try await run(["device", "--mac-address", mac, "list-settings", "--json", "--no-categories"])
        let settings = try JSONDecoder().decode([String: SettingInfo].self, from: data)
        return settings["customEqualizerProfile"]?.setting?.options ?? []
    }

    /// Applies `sets` in order, then reads back `gets`.
    func settings(mac: String, set sets: [(String, String)] = [], get gets: [String]) async throws -> [String: Value] {
        var args = ["device", "--mac-address", mac, "setting", "--json"]
        for (id, value) in sets { args += ["--set", "\(id)=\(value)"] }
        for id in gets { args += ["--get", id] }
        let data = try await run(args)
        let entries = try JSONDecoder().decode([SettingEntry].self, from: data)
        return Dictionary(entries.map { ($0.settingId, $0.value.value ?? .none) }, uniquingKeysWith: { _, last in last })
    }

    private func run(_ args: [String]) async throws -> Data {
        let binary = binary
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                let process = Process()
                process.executableURL = binary
                process.arguments = args
                let stdout = Pipe(), stderr = Pipe()
                process.standardOutput = stdout
                process.standardError = stderr
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }
                let pid = process.processIdentifier
                let watchdog = DispatchWorkItem { kill(pid, SIGTERM) }
                DispatchQueue.global().asyncAfter(deadline: .now() + Self.timeout, execute: watchdog)
                let out = stdout.fileHandleForReading.readDataToEndOfFile()
                let err = stderr.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                watchdog.cancel()
                if process.terminationReason == .uncaughtSignal {
                    continuation.resume(throwing: CLIError(message: "openscq30 stopped responding"))
                    return
                }
                guard process.terminationStatus == 0 else {
                    let message = String(decoding: err, as: UTF8.self)
                        .split(separator: "\n").last.map(String.init) ?? "openscq30 exited with \(process.terminationStatus)"
                    continuation.resume(throwing: CLIError(message: message))
                    return
                }
                continuation.resume(returning: out)
            }
        }
    }
}
