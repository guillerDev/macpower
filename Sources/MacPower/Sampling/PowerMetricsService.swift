import Foundation
import Observation

/// Optional exact per-process energy via Apple's `powermetrics` (needs root).
///
/// Runs `sudo -n powermetrics --samplers tasks -f plist` as a streaming child
/// process, parses each emitted plist sample, and publishes per-PID energy
/// impact. `sudo -n` never prompts: if a passwordless rule isn't installed the
/// service reports `.needsSetup` so the UI can offer to install one.
@MainActor
@Observable
final class PowerMetricsService {
    enum Status: Equatable {
        case off, starting, running, needsSetup
        case failed(String)
    }

    private(set) var status: Status = .off
    /// energy_impact_per_s keyed by PID, from the most recent sample.
    private(set) var energyByPID: [Int32: Double] = [:]

    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var buffer = Data()
    @ObservationIgnored private var sawOutput = false

    private static let sudoersPath = "/etc/sudoers.d/macpower"
    private static let powermetricsPath = "/usr/bin/powermetrics"

    var isActive: Bool { status == .running || status == .starting }

    // MARK: - Lifecycle

    func start(intervalMs: Int = 1000) {
        stop()
        status = .starting
        sawOutput = false
        buffer.removeAll(keepingCapacity: true)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        proc.arguments = ["-n", Self.powermetricsPath,
                          "--samplers", "tasks", "-f", "plist",
                          "-i", String(intervalMs)]
        let out = Pipe()
        let err = Pipe()
        proc.standardOutput = out
        proc.standardError = err

        out.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor in self?.ingest(data) }
        }

        // A quick non-zero exit with no output means sudo refused (needs setup).
        proc.terminationHandler = { [weak self] p in
            let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(),
                                encoding: .utf8) ?? ""
            Task { @MainActor in self?.handleTermination(status: p.terminationStatus, stderr: stderr) }
        }

        do {
            try proc.run()
            process = proc
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func stop() {
        process?.terminationHandler = nil
        if let p = process, p.isRunning { p.terminate() }
        process = nil
        energyByPID = [:]
        if status != .needsSetup { status = .off }
    }

    private func handleTermination(status code: Int32, stderr: String) {
        process = nil
        if !sawOutput {
            if stderr.localizedCaseInsensitiveContains("password")
                || stderr.localizedCaseInsensitiveContains("sudo:") {
                status = .needsSetup
            } else if status != .off {
                status = .failed(stderr.isEmpty ? "powermetrics exited (\(code))" : stderr)
            }
        } else if isActive {
            status = .off
        }
    }

    // MARK: - Streaming plist parsing

    /// powermetrics separates plist samples with a NUL byte.
    private func ingest(_ data: Data) {
        sawOutput = true
        if status == .starting { status = .running }
        buffer.append(data)

        while let nul = buffer.firstIndex(of: 0) {
            let chunk = buffer.subdata(in: buffer.startIndex..<nul)
            buffer.removeSubrange(buffer.startIndex...nul)
            parseSample(chunk)
        }
    }

    private func parseSample(_ data: Data) {
        guard !data.isEmpty,
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = plist as? [String: Any],
              let tasks = dict["tasks"] as? [[String: Any]] else { return }

        var map: [Int32: Double] = [:]
        map.reserveCapacity(tasks.count)
        for task in tasks {
            guard let pid = (task["pid"] as? NSNumber)?.int32Value else { continue }
            let impact = (task["energy_impact_per_s"] as? NSNumber)?.doubleValue
                ?? (task["energy_impact"] as? NSNumber)?.doubleValue
                ?? 0
            map[pid] = impact
        }
        energyByPID = map
    }

    // MARK: - One-time passwordless-sudo setup

    var isSetUp: Bool { FileManager.default.fileExists(atPath: Self.sudoersPath) }

    /// Installs a `sudoers.d` rule allowing passwordless powermetrics for the
    /// current user, prompting once with the native admin dialog. Returns true
    /// on success.
    func installSudoersRule() -> Bool {
        let user = NSUserName()
        // The rule is validated with `visudo -c` before being put in place.
        let rule = "\(user) ALL=(root) NOPASSWD: \(Self.powermetricsPath)"
        let tmp = "/tmp/macpower.sudoers"
        let shell = """
        printf '%s\\n' '\(rule)' > '\(tmp)' && \
        chmod 440 '\(tmp)' && chown root:wheel '\(tmp)' && \
        visudo -cf '\(tmp)' && mv '\(tmp)' '\(Self.sudoersPath)'
        """
        let apple = "do shell script \"\(shell.replacingOccurrences(of: "\"", with: "\\\""))\" with administrator privileges"

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", apple]
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0 && isSetUp
        } catch {
            return false
        }
    }
}
