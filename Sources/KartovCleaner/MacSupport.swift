import AppKit
import ServiceManagement
import KartovCore

/// Bundle ids of every app that is running right now.
struct WorkspaceRunningApps: RunningAppsProviding {
    func runningBundleIDs() -> Set<String> {
        // NSWorkspace is safe to read from any thread for this property.
        Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }
}

/// Turns cache folder names (often bundle ids) into app names and icons.
/// Used only from SwiftUI views and the main-actor model, so it is not locked.
final class AppInfoResolver {
    static let shared = AppInfoResolver()

    private var names: [String: String] = [:]
    private var icons: [String: NSImage] = [:]
    private var appURLs: [String: URL?] = [:]

    private func appURL(_ key: String) -> URL? {
        if let cached = appURLs[key] { return cached }
        let url = key.contains(".") ? NSWorkspace.shared.urlForApplication(withBundleIdentifier: key) : nil
        appURLs[key] = url
        return url
    }

    func name(for key: String) -> String {
        if let n = names[key] { return n }
        var n = key
        if let url = appURL(key) {
            n = FileManager.default.displayName(atPath: url.path)
            if n.hasSuffix(".app") { n = String(n.dropLast(4)) }
        }
        names[key] = n
        return n
    }

    /// The app's own icon when it is installed; nil otherwise (the row shows a monogram).
    func icon(for key: String) -> NSImage? {
        if let i = icons[key] { return i }
        guard let url = appURL(key) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        icons[key] = image
        return image
    }

    func isInstalled(_ key: String) -> Bool { appURL(key) != nil }
}

enum Permissions {
    /// Full Disk Access cannot be requested by code, only detected: try to list a folder
    /// macOS protects (Safari's data). If it lists, access is granted.
    static func hasFullDiskAccess() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        // The privacy database always exists and can only be opened with Full Disk Access.
        let tcc = home.appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db").path
        if FileManager.default.fileExists(atPath: tcc) {
            if let h = FileHandle(forReadingAtPath: tcc) { try? h.close(); return true }
            return false
        }
        let probes = ["Library/Safari", "Library/Containers/com.apple.stocks", "Library/Mail"]
        for p in probes {
            let path = home.appendingPathComponent(p).path
            guard FileManager.default.fileExists(atPath: path) else { continue }
            return (try? FileManager.default.contentsOfDirectory(atPath: path)) != nil
        }
        return true
    }

    /// Quits and opens the app again: macOS applies a new Full Disk Access grant on relaunch.
    static func relaunch() {
        let path = Bundle.main.bundlePath
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", path]
        try? p.run()
        NSApp.terminate(nil)
    }

    static func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}

enum Finder {
    static func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}

/// Time Machine local snapshots and unfinished macOS update folders: the usual hidden
/// part of "System Data". Listing needs no rights; removing them asks for the
/// administrator password through macOS's own dialog.
enum SystemData {
    static let installDataPath = "/macOS Install Data"

    static func localSnapshots() -> [String] {
        let out = run("/usr/bin/tmutil", ["listlocalsnapshots", "/"]).output
        return out.split(separator: "\n").map(String.init).filter { $0.contains("com.apple.TimeMachine") }
    }

    static func installDataExists() -> Bool {
        FileManager.default.fileExists(atPath: installDataPath)
    }

    static func purge(snapshots: Bool, installData: Bool) -> (ok: Bool, message: String?) {
        var commands: [String] = []
        if snapshots { commands.append("/usr/bin/tmutil deletelocalsnapshots /") }
        if installData { commands.append("/bin/rm -rf '\(installDataPath)'") }
        guard !commands.isEmpty else { return (true, nil) }
        // Fixed commands only; nothing from scanned data is interpolated here.
        let script = "do shell script \"\(commands.joined(separator: "; "))\" with administrator privileges"
        let result = run("/usr/bin/osascript", ["-e", script])
        if result.status == 0 { return (true, nil) }
        if result.error.contains("-128") { return (false, L("Yönetici izni verilmedi; hiçbir şey silinmedi.")) }
        return (false, L("macOS işlemi reddetti: ") + result.error.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func run(_ tool: String, _ args: [String]) -> (status: Int32, output: String, error: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        do { try p.run() } catch { return (-1, "", error.localizedDescription) }
        let o = out.fileHandleForReading.readDataToEndOfFile()
        let e = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: o, as: UTF8.self), String(decoding: e, as: UTF8.self))
    }
}

/// The "emptied the trash" sound, played when a clean finishes.
enum CleanSound {
    static func play() {
        let finderSound = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/finder/empty trash.aif"
        if FileManager.default.fileExists(atPath: finderSound),
           let sound = NSSound(contentsOfFile: finderSound, byReference: true) {
            sound.play()
        } else {
            NSSound(named: NSSound.Name("Glass"))?.play()
        }
    }
}


/// "Open Kartov Cleaner at login", so automatic maintenance can run without opening it by hand.
enum LoginItem {
    static var isEnabled: Bool {
        if #available(macOS 13.0, *) { return SMAppService.mainApp.status == .enabled }
        return false
    }

    /// Returns the resulting state. Works only for the installed .app, not for `swift run`.
    static func set(_ on: Bool) -> Bool {
        guard Bundle.main.bundleIdentifier != nil else { return false }
        if #available(macOS 13.0, *) {
            do {
                if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                klog("giriş öğesi ayarlanamadı: \(error.localizedDescription)")
            }
        }
        return isEnabled
    }
}

enum Reveal {
    /// Shows the file selected in Finder.
    static func inFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    /// Opens the file in its default app (to check a photo or video before deleting it).
    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
