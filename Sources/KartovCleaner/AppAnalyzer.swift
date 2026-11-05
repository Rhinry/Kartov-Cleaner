import AppKit
import CoreServices
import Darwin
import KartovCore

/// One open program, measured: memory, processor, disk activity.
struct RunningAppInfo: Identifiable {
    let id: pid_t
    let name: String
    let bundleID: String?
    let url: URL?
    let icon: NSImage?
    let launched: Date?
    let memory: UInt64
    /// Share of one processor core (1.0 = one core fully busy).
    var cpu: Double
    /// Bytes read + written per second since the last sample.
    var diskRate: Double
    /// Bytes read + written since the program started.
    let diskTotal: UInt64
}

/// One installed program: how big it is and how often it is used.
struct InstalledAppInfo: Identifiable {
    var id: String { url.path }
    let url: URL
    let name: String
    let bundleID: String?
    let icon: NSImage
    var size: Int64?
    /// How many times macOS has seen it opened (Spotlight's count), if known.
    let useCount: Int?
    let lastUsed: Date?
    let protected: Bool
}

@MainActor
enum AppAnalyzer {
    private struct Sample { let cpuNanos: UInt64; let disk: UInt64; let at: Date }
    private static var previous: [pid_t: Sample] = [:]

    nonisolated private static let timebase: (numer: UInt64, denom: UInt64) = {
        var t = mach_timebase_info_data_t()
        mach_timebase_info(&t)
        return (UInt64(t.numer), UInt64(max(t.denom, 1)))
    }()

    /// Open programs with memory, CPU and disk use. CPU and disk rates need two calls a few seconds apart.
    static func running() -> [RunningAppInfo] {
        let me = ProcessInfo.processInfo.processIdentifier
        let now = Date()
        var out: [RunningAppInfo] = []
        var next: [pid_t: Sample] = [:]
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && app.processIdentifier != me {
            let pid = app.processIdentifier
            var info = rusage_info_v4()
            let r = withUnsafeMutablePointer(to: &info) { ptr -> Int32 in
                ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
                }
            }
            guard r == 0 else { continue }
            let cpuNanos = (info.ri_user_time + info.ri_system_time) * timebase.numer / timebase.denom
            let disk = info.ri_diskio_bytesread + info.ri_diskio_byteswritten
            var cpu = 0.0, rate = 0.0
            if let p = previous[pid] {
                let dt = now.timeIntervalSince(p.at)
                if dt > 0.2 {
                    cpu = Double(cpuNanos &- p.cpuNanos) / 1e9 / dt
                    rate = Double(disk &- p.disk) / dt
                }
            }
            next[pid] = Sample(cpuNanos: cpuNanos, disk: disk, at: now)
            out.append(RunningAppInfo(id: pid, name: app.localizedName ?? L("Uygulama"), bundleID: app.bundleIdentifier,
                                      url: app.bundleURL, icon: app.icon, launched: app.launchDate,
                                      memory: info.ri_phys_footprint, cpu: max(0, cpu), diskRate: max(0, rate),
                                      diskTotal: disk))
        }
        previous = next
        return out
    }

    /// Programs in /Applications and ~/Applications (and one folder level below, like Utilities).
    nonisolated static func installed() -> [InstalledAppInfo] {
        let fm = FileManager.default
        let roots = [URL(fileURLWithPath: "/Applications"),
                     fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
        var urls: [URL] = []
        for root in roots {
            guard let names = try? fm.contentsOfDirectory(atPath: root.path) else { continue }
            for n in names {
                let u = root.appendingPathComponent(n)
                if n.hasSuffix(".app") { urls.append(u) }
                else if let sub = try? fm.contentsOfDirectory(atPath: u.path) {
                    urls += sub.filter { $0.hasSuffix(".app") }.map { u.appendingPathComponent($0) }
                }
            }
        }
        return urls.map { url in
            let bundle = Bundle(url: url)
            let id = bundle?.bundleIdentifier
            var count: Int?
            var last: Date?
            if let item = MDItemCreateWithURL(nil, url as CFURL) {
                count = (MDItemCopyAttribute(item, "kMDItemUseCount" as CFString) as? NSNumber)?.intValue
                last = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
            }
            let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? url.deletingPathExtension().lastPathComponent
            return InstalledAppInfo(url: url, name: name, bundleID: id,
                                    icon: NSWorkspace.shared.icon(forFile: url.path),
                                    size: nil, useCount: count, lastUsed: last,
                                    protected: DiskRemover.isProtectedApp(bundleID: id, url: url))
        }
    }

    nonisolated static func size(of url: URL) -> Int64 { SizeCalculator.measure(url).bytes }
}
