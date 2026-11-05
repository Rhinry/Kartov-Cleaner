import Foundation
import AppKit
import KartovCore
import Darwin
import IOKit
import IOKit.ps

/// Live system readings for the "Sistem durumu" screen. Everything is read with public
/// macOS APIs and needs no special permission.
enum SystemMonitor {

    // MARK: CPU

    struct CPUTicks { var user: Double; var system: Double; var idle: Double; var nice: Double }

    static func cpuTicks() -> CPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return CPUTicks(user: Double(info.cpu_ticks.0), system: Double(info.cpu_ticks.1),
                        idle: Double(info.cpu_ticks.2), nice: Double(info.cpu_ticks.3))
    }

    /// Share of time busy between two readings, 0…1.
    static func cpuUsage(from a: CPUTicks, to b: CPUTicks) -> Double {
        let busy = (b.user - a.user) + (b.system - a.system) + (b.nice - a.nice)
        let total = busy + (b.idle - a.idle)
        return total > 0 ? min(1, max(0, busy / total)) : 0
    }

    // MARK: memory

    struct Memory { let used: UInt64; let total: UInt64; let compressed: UInt64; let pressure: Double }

    static func memory() -> Memory? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let page = UInt64(vm_kernel_page_size)
        let app = UInt64(stats.internal_page_count) &- UInt64(stats.purgeable_count)
        let wired = UInt64(stats.wire_count)
        let compressed = UInt64(stats.compressor_page_count)
        let used = (app + wired + compressed) * page
        let total = ProcessInfo.processInfo.physicalMemory
        return Memory(used: min(used, total), total: total, compressed: compressed * page,
                      pressure: total > 0 ? Double(min(used, total)) / Double(total) : 0)
    }

    // MARK: battery

    struct Battery { let percent: Int; let charging: Bool; let cycles: Int?; let health: Int? }

    static func battery() -> Battery? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue() as? [String: Any],
                  (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            let cur = d[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = d[kIOPSMaxCapacityKey] as? Int ?? 100
            let charging = (d[kIOPSIsChargingKey] as? Bool) ?? false
            var cycles: Int?
            var health: Int?
            let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
            if service != 0 {
                func prop(_ key: String) -> Int? {
                    IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
                        .takeRetainedValue() as? Int
                }
                cycles = prop("CycleCount")
                if let design = prop("DesignCapacity"), design > 0,
                   let full = prop("AppleRawMaxCapacity") ?? prop("NominalChargeCapacity") {
                    health = Swift.min(100, Int((Double(full) / Double(design) * 100).rounded()))
                }
                IOObjectRelease(service)
            }
            return Battery(percent: max > 0 ? Int(Double(cur) / Double(max) * 100) : cur,
                           charging: charging, cycles: cycles, health: health)
        }
        return nil
    }

    // MARK: apps using the most memory

    struct AppMemory: Identifiable {
        let id: pid_t
        let name: String
        let bundleID: String?
        let bytes: UInt64
        let icon: NSImage?
    }

    static func topApps(limit: Int = 6) -> [AppMemory] {
        let me = ProcessInfo.processInfo.processIdentifier
        var out: [AppMemory] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && app.processIdentifier != me {
            var info = rusage_info_v2()
            let r = withUnsafeMutablePointer(to: &info) { ptr -> Int32 in
                ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(app.processIdentifier, RUSAGE_INFO_V2, $0)
                }
            }
            guard r == 0 else { continue }
            out.append(AppMemory(id: app.processIdentifier, name: app.localizedName ?? L("Uygulama"),
                                 bundleID: app.bundleIdentifier, bytes: info.ri_phys_footprint, icon: app.icon))
        }
        return Array(out.sorted { $0.bytes > $1.bytes }.prefix(limit))
    }

    // MARK: programs that start on their own

    struct StartupItem: Identifiable {
        var id: String { url.path }
        let url: URL
        let name: String
        let systemWide: Bool
    }

    /// Background helpers that launch at login (LaunchAgents). Apple's own are left out.
    static func startupItems() -> [StartupItem] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dirs: [(URL, Bool)] = [(home.appendingPathComponent("Library/LaunchAgents"), false),
                                   (URL(fileURLWithPath: "/Library/LaunchAgents"), true)]
        var out: [StartupItem] = []
        for (dir, system) in dirs {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { continue }
            for n in names where n.hasSuffix(".plist") && !n.hasPrefix("com.apple.") && !n.hasPrefix("com.kartov.") {
                out.append(StartupItem(url: dir.appendingPathComponent(n), name: prettyName(n), systemWide: system))
            }
        }
        return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// `com.google.keystone.agent.plist` → "Google Keystone Agent"
    static func prettyName(_ file: String) -> String {
        var parts = file.replacingOccurrences(of: ".plist", with: "").split(separator: ".").map(String.init)
        if parts.count > 2, ["com", "org", "net", "io", "de", "us", "co"].contains(parts[0]) { parts.removeFirst() }
        return parts.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    // MARK: other readings

    static var uptime: TimeInterval { ProcessInfo.processInfo.systemUptime }

    static var thermal: (String, Double) {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return (L("Serin"), 0.2)
        case .fair: return (L("Ilık"), 0.5)
        case .serious: return (L("Sıcak"), 0.8)
        case .critical: return (L("Çok sıcak"), 1.0)
        @unknown default: return ("—", 0)
        }
    }

    // MARK: optimize actions (macOS asks for the administrator password)

    /// Frees inactive memory (the `purge` command).
    static func purgeMemory() -> (Bool, String) {
        runAdmin("/usr/sbin/purge", ok: L("Bellek rahatlatıldı."))
    }

    /// Clears the DNS cache, which fixes many "site won't open" problems.
    static func flushDNS() -> (Bool, String) {
        runAdmin("/usr/bin/dscacheutil -flushcache; /usr/bin/killall -HUP mDNSResponder", ok: L("İnternet adres önbelleği yenilendi."))
    }

    private static func runAdmin(_ command: String, ok: String) -> (Bool, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", "do shell script \"\(command)\" with administrator privileges"]
        let err = Pipe()
        p.standardError = err
        p.standardOutput = Pipe()
        do { try p.run() } catch { return (false, L("Çalıştırılamadı.")) }
        p.waitUntilExit()
        if p.terminationStatus == 0 { return (true, ok) }
        let e = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return (false, e.contains("-128") ? L("Yönetici izni verilmedi.") : L("macOS işlemi yapmadı."))
    }
}
