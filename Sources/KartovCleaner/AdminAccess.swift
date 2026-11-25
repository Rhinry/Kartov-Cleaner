import Foundation
import KartovCore

/// Runs the administrator jobs. With no-password mode on they go through Kartov's helper and
/// macOS asks nothing; otherwise (or if the helper is gone) macOS shows its password dialog.
@MainActor
final class AdminAccess: ObservableObject {
    static let shared = AdminAccess()

    @Published private(set) var enabled = false
    @Published private(set) var busy = false
    @Published var message: String?

    private init() {}

    func refresh() {
        Task {
            let on = await Task.detached { Self.helperAnswers() }.value
            enabled = on
        }
    }

    /// Asks for the password once and installs the helper and its rule.
    func enable() {
        guard !busy, let script = AdminAccessFiles.installScript(user: NSUserName()) else {
            message = L("Bu hesapta açılamadı.")
            return
        }
        change(script, wanted: true)
    }

    /// Asks for the password once and removes them.
    func disable() {
        guard !busy else { return }
        change(AdminAccessFiles.removeScript(), wanted: false)
    }

    private func change(_ script: String, wanted: Bool) {
        busy = true
        message = nil
        Task {
            let r = await Task.detached { Self.withPassword(script) }.value
            let on = await Task.detached { Self.helperAnswers() }.value
            enabled = on
            busy = false
            if r.cancelled { return }
            if on != wanted {
                message = wanted ? L("Açılamadı. macOS izni kabul etmedi.") : L("Kapatılamadı. macOS izni kabul etmedi.")
            }
        }
    }

    // MARK: running jobs (any thread)

    /// Runs the jobs in order and stops at the first that fails.
    nonisolated static func run(_ tasks: [AdminTask]) -> (ok: Bool, cancelled: Bool, error: String) {
        guard !tasks.isEmpty else { return (true, false, "") }
        if helperAnswers() {
            for t in tasks {
                let r = exec("/usr/bin/sudo", ["-n", AdminAccessFiles.helperPath, t.rawValue])
                if r.status != 0 { return (false, false, r.error) }
            }
            return (true, false, "")
        }
        // Fixed commands only; nothing from scanned data is put into the script.
        let r = withPassword(tasks.map(\.shellCommand).joined(separator: "; "))
        return (r.status == 0, r.cancelled, r.error)
    }

    nonisolated static func helperAnswers() -> Bool {
        FileManager.default.fileExists(atPath: AdminAccessFiles.helperPath)
            && exec("/usr/bin/sudo", ["-n", AdminAccessFiles.helperPath, "check"]).status == 0
    }

    private nonisolated static func withPassword(_ script: String) -> (status: Int32, cancelled: Bool, error: String) {
        let r = exec("/usr/bin/osascript", ["-e", "do shell script \"\(script)\" with administrator privileges"])
        return (r.status, r.error.contains("-128"), r.error)
    }

    private nonisolated static func exec(_ tool: String, _ args: [String]) -> (status: Int32, error: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let err = Pipe()
        p.standardError = err
        p.standardOutput = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return (-1, error.localizedDescription) }
        let e = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: e, as: UTF8.self))
    }
}
