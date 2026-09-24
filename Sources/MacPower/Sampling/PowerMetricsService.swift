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
    @ObservationIgnored private var output: FileHandle?
    @ObservationIgnored private var buffer = Data()
    @ObservationIgnored private var sawOutput = false

    /// The original rule lived at `/etc/sudoers.d/macpower` and allowed *any*
    /// powermetrics arguments. The narrower rule uses a new path so existing
    /// installs are prompted to replace it; installing removes the legacy file.
    private static let sudoersPath = "/etc/sudoers.d/macpower-powermetrics"
    private static let legacySudoersPath = "/etc/sudoers.d/macpower"
    nonisolated private static let powermetricsPath = "/usr/bin/powermetrics"

    var isActive: Bool { status == .running || status == .starting }

    /// powermetrics arguments for one sampling interval. Shared by `start` and the
    /// sudoers rule so the allowed command lines can't drift from the ones run.
    nonisolated static func arguments(intervalMs: Int) -> [String] {
        ["--samplers", "tasks", "-f", "plist", "-i", String(intervalMs)]
    }

    /// A NOPASSWD rule for exactly the command lines MacPower runs (one per
    /// interval). Never bare `powermetrics`: its `-o <file>` would let any process
    /// running as this user write a root-owned file anywhere.
    nonisolated static func sudoersRule(user: String, intervalsMs: [Int]) -> String {
        let commands = intervalsMs.map {
            ([powermetricsPath] + arguments(intervalMs: $0)).joined(separator: " ")
        }
        return "\(user) ALL=(root) NOPASSWD: " + commands.joined(separator: ", ")
    }

    // MARK: - Lifecycle

    func start(intervalMs: Int = 1000) {
        stop()
        status = .starting
        sawOutput = false
        buffer.removeAll(keepingCapacity: true)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        proc.arguments = ["-n", Self.powermetricsPath] + Self.arguments(intervalMs: intervalMs)
        let out = Pipe()
        let err = Pipe()
        proc.standardOutput = out
        proc.standardError = err

        let reader = out.fileHandleForReading
        reader.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            // Empty data is EOF. The handler must be cleared, or it keeps firing
            // (hundreds of thousands of times a second) and pins a CPU core.
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            Task { @MainActor in
                // Drop output still in flight from a process we've since stopped.
                guard let self, self.output === handle else { return }
                self.ingest(data)
            }
        }

        // A quick non-zero exit with no output means sudo refused (needs setup).
        proc.terminationHandler = { [weak self] p in
            let stderr =
                String(
                    data: err.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8) ?? ""
            Task { @MainActor in
                // Ignore a late notification from a process `start` already replaced.
                guard let self, self.process === p else { return }
                self.handleTermination(status: p.terminationStatus, stderr: stderr)
            }
        }

        do {
            try proc.run()
            process = proc
            output = reader
        } catch {
            reader.readabilityHandler = nil
            status = .failed(error.localizedDescription)
        }
    }

    func stop() {
        process?.terminationHandler = nil
        output?.readabilityHandler = nil
        output = nil
        if let p = process, p.isRunning { p.terminate() }
        process = nil
        energyByPID = [:]
        if status != .needsSetup { status = .off }
    }

    private func handleTermination(status code: Int32, stderr: String) {
        process = nil
        output = nil
        if !sawOutput {
            if stderr.localizedCaseInsensitiveContains("password")
                || stderr.localizedCaseInsensitiveContains("sudo:")
            {
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
            let tasks = dict["tasks"] as? [[String: Any]]
        else { return }

        var map: [Int32: Double] = [:]
        map.reserveCapacity(tasks.count)
        for task in tasks {
            guard let pid = (task["pid"] as? NSNumber)?.int32Value else { continue }
            let impact =
                (task["energy_impact_per_s"] as? NSNumber)?.doubleValue
                ?? (task["energy_impact"] as? NSNumber)?.doubleValue
                ?? 0
            map[pid] = impact
        }
        energyByPID = map
    }

    // MARK: - One-time passwordless-sudo setup

    var isSetUp: Bool { FileManager.default.fileExists(atPath: Self.sudoersPath) }

    /// Installs a `sudoers.d` rule allowing passwordless powermetrics for the
    /// current user, prompting once with the native admin dialog. Suspends (not
    /// blocks) while the dialog is up. Returns true on success.
    func installSudoersRule() async -> Bool {
        let rule = Self.sudoersRule(
            user: NSUserName(),
            intervalsMs: PowerMonitor.intervalChoices.map { Int($0 * 1000) })
        let shell = Self.installScript(rule: rule, path: Self.sudoersPath, legacyPath: Self.legacySudoersPath)

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", Self.adminAppleScript(running: shell)]
        let succeeded = await withCheckedContinuation { done in
            task.terminationHandler = { done.resume(returning: $0.terminationStatus == 0) }
            do {
                try task.run()
            } catch {
                task.terminationHandler = nil
                done.resume(returning: false)
            }
        }
        return succeeded && isSetUp
    }

    /// The `sh` script (run as root) that installs `rule` at `path`. The temp file
    /// comes from mktemp (exclusive create) rather than a fixed /tmp name, which a
    /// pre-planted symlink could redirect. `visudo -c` validates the rule before
    /// it's moved into place; the legacy unrestricted rule is then removed.
    nonisolated static func installScript(rule: String, path: String, legacyPath: String) -> String {
        """
        t=$(mktemp /tmp/macpower.XXXXXX) || exit 1
        if printf '%s\\n' '\(rule)' > "$t" && chmod 440 "$t" && chown root:wheel "$t" \
        && visudo -cf "$t"; then
        mv "$t" '\(path)' && rm -f '\(legacyPath)'
        else rm -f "$t"; exit 1; fi
        """
    }

    /// Wraps a shell script in an AppleScript that runs it with the native admin
    /// prompt. Backslashes and quotes are escaped for the AppleScript string.
    nonisolated static func adminAppleScript(running shell: String) -> String {
        let escaped = shell.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "do shell script \"\(escaped)\" with administrator privileges"
    }
}
