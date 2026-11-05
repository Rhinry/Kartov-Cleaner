import Foundation
import AppKit
import Darwin
import IOKit.ps
import UserNotifications
import KartovCore

/// Something Gözetim noticed.
struct GuardianAlert: Codable, Identifiable, Hashable {
    enum Kind: String, Codable { case cpu, memory, diskLow, diskBurst, appGrowth, thermal }
    var id: UUID
    var date: Date
    var kind: Kind
    var title: String
    var detail: String
    var bundleID: String?
    var appName: String?
    var read: Bool

    var symbol: String {
        switch kind {
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .diskLow: return "externaldrive.badge.exclamationmark"
        case .diskBurst: return "arrow.up.right.circle"
        case .appGrowth: return "chart.line.uptrend.xyaxis"
        case .thermal: return "thermometer.high"
        }
    }
}

/// Current load of the Mac, each 0…1.
struct Vitals: Equatable {
    var cpu: Double = 0
    var memory: Double = 0
    var disk: Double = 0
    var thermal: Double = 0
    /// macOS memory pressure: 1 normal, 2 warning, 4 critical.
    var pressure: Int = 1
}

struct FootprintPoint: Codable, Hashable { var date: Date; var bytes: Int64 }

/// One hour of energy use per program, in joules.
struct EnergyBucket: Codable {
    var hour: Date
    var total: [String: Double] = [:]
    var onBattery: [String: Double] = [:]
}

/// A program whose Library files grew.
struct AppGrowth: Identifiable, Hashable {
    var id: String { bundleID }
    let bundleID: String
    let name: String
    let bytes: Int64
    let delta: Int64
    let since: Date
}

struct EnergyRow: Identifiable {
    let id: String
    let name: String
    let bundleID: String?
    let icon: NSImage?
    /// Estimated power right now (live list) or average over the period (day list), in watts.
    let watts: Double
    /// Energy over the period, in joules (day list).
    let joules: Double
}

private struct GuardianState: Codable {
    var disk: [DiskSample] = []
    var footprints: [String: [FootprintPoint]] = [:]
    var names: [String: String] = [:]
    var lastFootprintRun: Date?
    var alerts: [GuardianAlert] = []
    var cooldown: [String: Date] = [:]
    var energy: [EnergyBucket] = []

    init() {}

    enum CodingKeys: String, CodingKey { case disk, footprints, names, lastFootprintRun, alerts, cooldown, energy }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        disk = (try? c.decodeIfPresent([DiskSample].self, forKey: .disk)) ?? []
        footprints = (try? c.decodeIfPresent([String: [FootprintPoint]].self, forKey: .footprints)) ?? [:]
        names = (try? c.decodeIfPresent([String: String].self, forKey: .names)) ?? [:]
        lastFootprintRun = try? c.decodeIfPresent(Date.self, forKey: .lastFootprintRun)
        alerts = (try? c.decodeIfPresent([GuardianAlert].self, forKey: .alerts)) ?? []
        cooldown = (try? c.decodeIfPresent([String: Date].self, forKey: .cooldown)) ?? [:]
        energy = (try? c.decodeIfPresent([EnergyBucket].self, forKey: .energy)) ?? []
    }
}

extension Notification.Name {
    static let kartovOpenGuardian = Notification.Name("KartovOpenGuardian")
}

/// Gözetim: watches the Mac in the background (once a minute) and speaks up when something is off —
/// a program that has been busy for minutes, memory about to run out, the disk filling fast or
/// a program's files suddenly growing. It only reads; it never removes anything.
@MainActor
final class Guardian: ObservableObject {
    static let shared = Guardian()

    enum Page: String, CaseIterable, Identifiable {
        case overview, energy, crashes, privacy
        var id: Self { self }
        var title: String {
            switch self {
            case .overview: return L("Genel")
            case .energy: return L("Enerji")
            case .crashes: return L("Çökmeler")
            case .privacy: return L("Gizlilik")
            }
        }
        var symbol: String {
            switch self {
            case .overview: return "shield.lefthalf.filled"
            case .energy: return "bolt.fill"
            case .crashes: return "exclamationmark.triangle.fill"
            case .privacy: return "hand.raised.fill"
            }
        }
    }

    // Settings
    @Published var enabled: Bool { didSet { defaults.set(enabled, forKey: "guardianEnabled"); enabled ? start() : stop() } }
    @Published var notify: Bool { didSet { defaults.set(notify, forKey: "guardianNotify") } }
    @Published var watchCPU: Bool { didSet { defaults.set(watchCPU, forKey: "guardianCPU") } }
    @Published var watchMemory: Bool { didSet { defaults.set(watchMemory, forKey: "guardianMemory") } }
    @Published var watchDisk: Bool { didSet { defaults.set(watchDisk, forKey: "guardianDisk") } }
    @Published var watchGrowth: Bool { didSet { defaults.set(watchGrowth, forKey: "guardianGrowth") } }

    // Readings
    @Published private(set) var vitals = Vitals()
    @Published private(set) var alerts: [GuardianAlert] = []
    @Published private(set) var forecast = StorageForecast.make([])
    @Published private(set) var growth: [AppGrowth] = []
    @Published private(set) var lastCheck: Date?
    @Published private(set) var measuringApps = false
    @Published private(set) var liveEnergy: [EnergyRow] = []
    @Published private(set) var dayEnergy: [EnergyRow] = []
    @Published private(set) var dayEnergyOnBattery = false

    // Crash Detective and Privacy Inspector
    @Published private(set) var crashes: [CrashReport] = []
    @Published private(set) var crashesLoaded = false
    @Published private(set) var crashesLoading = false
    @Published private(set) var privacy: [PrivacyApp] = []
    @Published private(set) var privacyReadable = true
    @Published private(set) var privacyLoading = false

    // Screen state (kept here: @State needs full Xcode on the macOS 27 SDK)
    @Published var page: Page = .overview
    @Published var openCrashGroups: Set<String> = []
    @Published var privacyFilter: PrivacyService?
    @Published var privacyConfirm: String?
    @Published var privacyMessage: String?

    var unread: Int { alerts.filter { !$0.read }.count }

    private let defaults = UserDefaults.standard
    private var state = GuardianState()
    private var timer: Timer?
    private var liveTimer: Timer?
    private var energyTimer: Timer?
    private var lastTicks: SystemMonitor.CPUTicks?
    private var liveTicks: SystemMonitor.CPUTicks?
    private var procPrev: [pid_t: (cpu: UInt64, energy: UInt64, at: Date)] = [:]
    private var livePrev: [pid_t: (energy: UInt64, at: Date)] = [:]
    private var hotStreak: [String: Int] = [:]
    private var memoryStreak = 0
    private var lastSave = Date.distantPast
    private var started = false

    private let fileURL: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("KartovCleaner/guardian.json")

    nonisolated private static let timebase: (numer: UInt64, denom: UInt64) = {
        var t = mach_timebase_info_data_t()
        mach_timebase_info(&t)
        return (UInt64(t.numer), UInt64(max(t.denom, 1)))
    }()

    private init() {
        let d = UserDefaults.standard
        enabled = d.object(forKey: "guardianEnabled") as? Bool ?? true
        notify = d.object(forKey: "guardianNotify") as? Bool ?? true
        watchCPU = d.object(forKey: "guardianCPU") as? Bool ?? true
        watchMemory = d.object(forKey: "guardianMemory") as? Bool ?? true
        watchDisk = d.object(forKey: "guardianDisk") as? Bool ?? true
        watchGrowth = d.object(forKey: "guardianGrowth") as? Bool ?? true
        load()
    }

    // MARK: running

    func start() {
        guard enabled, !started else { return }
        started = true
        lastTicks = SystemMonitor.cpuTicks()
        readVitals(ticks: &lastTicks)
        recordDiskSample(force: state.disk.isEmpty)
        recomputeGrowth()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer?.tolerance = 10
        // The first look at program sizes waits a little so it does not slow down the launch.
        DispatchQueue.main.asyncAfter(deadline: .now() + 90) { [weak self] in self?.measureFootprintsIfDue() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        started = false
        save()
    }

    /// Faster vitals while the home globe is on screen.
    func startLiveVitals() {
        guard liveTimer == nil else { return }
        liveTicks = SystemMonitor.cpuTicks()
        readVitals(ticks: &liveTicks)
        liveTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.readVitals(ticks: &self.liveTicks)
            }
        }
    }

    func stopLiveVitals() {
        liveTimer?.invalidate()
        liveTimer = nil
    }

    private func readVitals(ticks: inout SystemMonitor.CPUTicks?) {
        var v = vitals
        if let now = SystemMonitor.cpuTicks() {
            if let last = ticks { v.cpu = SystemMonitor.cpuUsage(from: last, to: now) }
            ticks = now
        }
        v.memory = SystemMonitor.memory()?.pressure ?? v.memory
        let disk = DiskInfo.read()
        v.disk = disk.total > 0 ? Double(disk.used) / Double(disk.total) : 0
        v.thermal = SystemMonitor.thermal.1
        v.pressure = Self.pressureLevel()
        if v != vitals { vitals = v }
    }

    // MARK: the globe's mood

    /// 0…1: how hard the processor (and heat) is pushing.
    var heat: Double {
        let cpu = max(0, min(1, (vitals.cpu - 0.55) / 0.4))
        let warm = max(0, min(1, (vitals.thermal - 0.3) / 0.6))
        return max(cpu, warm)
    }

    /// 0…1: how full memory is.
    var fog: Double {
        switch vitals.pressure {
        case 4...: return 1
        case 2, 3: return 0.6
        default: return max(0, min(0.3, (vitals.memory - 0.85) / 0.4))
        }
    }

    /// One sentence when something is stretched, nil when all is calm.
    var stressNote: String? {
        if vitals.disk >= 0.92 { return L("Disk %{0} dolu; yer açmak iyi gelir.", Int(vitals.disk * 100)) }
        if vitals.pressure >= 2 { return L("Bellek dolmak üzere; dünya bulutlandı.") }
        if vitals.cpu >= 0.85 { return L("İşlemci yoğun çalışıyor; dünya ısındı.") }
        if vitals.thermal >= 0.8 { return L("Mac'in ısınmış.") }
        return nil
    }

    // MARK: once a minute

    private func tick() {
        readVitals(ticks: &lastTicks)
        lastCheck = Date()
        recordDiskSample(force: false)
        checkDisk()
        checkMemory()
        scanProcesses()
        measureFootprintsIfDue()
        if Date().timeIntervalSince(lastSave) > 300 { save() }
    }

    private func recordDiskSample(force: Bool) {
        let d = DiskInfo.read()
        guard d.total > 0 else { return }
        if !force, let last = state.disk.last, Date().timeIntervalSince(last.date) < 30 * 60 { return }
        state.disk.append(DiskSample(date: Date(), used: d.used, total: d.total))
        state.disk = StorageForecast.thin(state.disk)
        forecast = StorageForecast.make(state.disk)
    }

    private func checkDisk() {
        guard watchDisk else { return }
        let d = DiskInfo.read()
        guard d.total > 0 else { return }
        if Double(d.free) / Double(d.total) < 0.05 {
            flag(.diskLow, key: "disk.low", cooldown: 24 * 3600,
                  title: L("Disk neredeyse dolu"),
                  detail: L("Yalnızca {0} boş yer kaldı. Temizlik ya da Tam tarama yer açar.", KBytes.format(d.free)))
        }
        // A sudden jump: compare with a reading from about an hour ago.
        let now = Date()
        if let past = state.disk.last(where: { now.timeIntervalSince($0.date) >= 50 * 60 && now.timeIntervalSince($0.date) <= 2.5 * 3600 }) {
            let grew = d.used - past.used
            let limit = max(Int64(5_000_000_000), d.total / 50)
            if grew > limit {
                let hours = max(1, Int((now.timeIntervalSince(past.date) / 3600).rounded()))
                flag(.diskBurst, key: "disk.burst", cooldown: 6 * 3600,
                      title: L("Disk hızla doluyor"),
                      detail: L("Son {0} saatte {1} doldu. Neyin yer kapladığına Tam tarama ile bakabilirsin.", hours, KBytes.format(grew)))
            }
        }
    }

    private func checkMemory() {
        guard watchMemory else { memoryStreak = 0; return }
        // macOS's own memory pressure: critical for 3 minutes, or warning for 9 minutes.
        memoryStreak = vitals.pressure >= 2 ? memoryStreak + (vitals.pressure >= 4 ? 3 : 1) : 0
        if memoryStreak >= 9 {
            let top = SystemMonitor.topApps(limit: 1).first
            flag(.memory, key: "memory", cooldown: 3 * 3600,
                  title: L("Bellek dolmak üzere"),
                  detail: top.map { L("Birkaç dakikadır bellek %{0} dolu. En çok kullanan: {1} ({2}).", Int(vitals.memory * 100), $0.name, KBytes.format(Int64($0.bytes))) }
                    ?? L("Birkaç dakikadır bellek %{0} dolu.", Int(vitals.memory * 100)),
                  bundleID: top?.bundleID, appName: top?.name)
        }
    }

    /// Every process we may read (the user's own): processor use for the warnings, energy for the Enerji page.
    private func scanProcesses() {
        let now = Date()
        let me = ProcessInfo.processInfo.processIdentifier
        var apps: [pid_t: NSRunningApplication] = [:]
        for a in NSWorkspace.shared.runningApplications { apps[a.processIdentifier] = a }
        let onBattery = Self.onBattery()
        var next: [pid_t: (cpu: UInt64, energy: UInt64, at: Date)] = [:]
        var seenHot = Set<String>()
        var energyNow: [String: Double] = [:]
        for pid in Self.allPIDs() where pid != me {
            guard let u = Self.usage(pid) else { continue }
            next[pid] = (u.cpu, u.energy, now)
            guard let p = procPrev[pid] else { continue }
            let dt = now.timeIntervalSince(p.at)
            guard dt > 5 else { continue }
            let app = apps[pid]
            let regular = app?.activationPolicy == .regular
            if regular, let id = app?.bundleIdentifier, u.energy >= p.energy {
                energyNow[id, default: 0] += Double(u.energy - p.energy) / 1e9
                state.names[id] = app?.localizedName ?? id
            }
            guard watchCPU, u.cpu >= p.cpu else { continue }
            let cores = Double(u.cpu - p.cpu) / 1e9 / dt
            guard cores >= 0.85 else { continue }
            let name = app?.localizedName ?? Self.processName(pid) ?? "pid \(pid)"
            if ["kernel_task", "WindowServer", "Kartov Cleaner", "KartovCleaner"].contains(name) { continue }
            let bundle = app?.bundleIdentifier
            if ProfileStore.shared.isExpectedHeavy(name: name, bundleID: bundle) { continue }
            let key = bundle ?? name
            seenHot.insert(key)
            let streak = (hotStreak[key] ?? 0) + 1
            hotStreak[key] = streak
            if streak >= 5 {
                flag(.cpu, key: "cpu." + key, cooldown: 6 * 3600,
                      title: L("{0} işlemciyi yoruyor", name),
                      detail: L("{0} dakikadır işlemcinin %{1} kadarını kullanıyor. Takıldıysa Analiz'den kapatabilirsin.", streak, Int(cores * 100)),
                      bundleID: bundle, appName: name)
            }
        }
        for k in hotStreak.keys where !seenHot.contains(k) { hotStreak[k] = nil }
        procPrev = next
        addEnergy(energyNow, onBattery: onBattery, at: now)
    }

    private func addEnergy(_ joules: [String: Double], onBattery: Bool, at now: Date) {
        guard !joules.isEmpty else { return }
        let hour = Calendar.current.dateInterval(of: .hour, for: now)?.start ?? now
        if state.energy.last?.hour != hour { state.energy.append(EnergyBucket(hour: hour)) }
        let i = state.energy.count - 1
        for (id, j) in joules {
            state.energy[i].total[id, default: 0] += j
            if onBattery { state.energy[i].onBattery[id, default: 0] += j }
        }
        let cutoff = now.addingTimeInterval(-24 * 3600)
        state.energy.removeAll { $0.hour < cutoff }
    }

    // MARK: programs whose files grow

    private func measureFootprintsIfDue() {
        guard enabled, watchGrowth, !measuringApps else { return }
        if let last = state.lastFootprintRun, Date().timeIntervalSince(last) < 6 * 3600 { return }
        measuringApps = true
        Task.detached(priority: .background) {
            let apps = Guardian.installedBundles()
            var out: [(String, String, Int64)] = []
            for (id, name) in apps {
                let b = AppFootprint.total(bundleID: id, appName: name)
                if b > 0 { out.append((id, name, b)) }
            }
            let result = out
            await MainActor.run { Guardian.shared.recordFootprints(result) }
        }
    }

    private func recordFootprints(_ list: [(String, String, Int64)]) {
        let now = Date()
        state.lastFootprintRun = now
        measuringApps = false
        let cutoff = now.addingTimeInterval(-14 * 86_400)
        for (id, name, bytes) in list {
            state.names[id] = name
            var pts = state.footprints[id] ?? []
            pts.append(FootprintPoint(date: now, bytes: bytes))
            pts.removeAll { $0.date < cutoff }
            state.footprints[id] = Array(pts.suffix(60))
            // Compare with the newest reading that is at least 20 hours old.
            if watchGrowth, let base = pts.last(where: { now.timeIntervalSince($0.date) >= 20 * 3600 }) {
                let delta = bytes - base.bytes
                if delta > 2_000_000_000 && Double(delta) > Double(max(base.bytes, 1)) * 0.3 {
                    flag(.appGrowth, key: "grow." + id, cooldown: 24 * 3600,
                          title: L("{0} hızla büyüyor", name),
                          detail: L("Dosyaları bir günde {0} büyüdü (şimdi {1}). Bağlantılı dosyalarına bakabilirsin.", KBytes.format(delta), KBytes.format(bytes)),
                          bundleID: id, appName: name)
                }
            }
        }
        recomputeGrowth()
        save()
    }

    private func recomputeGrowth() {
        let now = Date()
        var out: [AppGrowth] = []
        for (id, pts) in state.footprints {
            guard let last = pts.last, let first = pts.first(where: { now.timeIntervalSince($0.date) <= 7 * 86_400 }),
                  last.date > first.date else { continue }
            let delta = last.bytes - first.bytes
            if delta >= 50_000_000 {
                out.append(AppGrowth(bundleID: id, name: state.names[id] ?? id, bytes: last.bytes, delta: delta, since: first.date))
            }
        }
        growth = Array(out.sorted { $0.delta > $1.delta }.prefix(6))
    }

    var footprintSince: Date? { state.footprints.values.compactMap { $0.first?.date }.min() }

    /// Bundle ids and names of the programs in /Applications and ~/Applications (not Apple's).
    nonisolated static func installedBundles() -> [(String, String)] {
        let fm = FileManager.default
        var out: [(String, String)] = []
        for root in [URL(fileURLWithPath: "/Applications"), fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")] {
            guard let names = try? fm.contentsOfDirectory(atPath: root.path) else { continue }
            var urls: [URL] = []
            for n in names {
                let u = root.appendingPathComponent(n)
                if n.hasSuffix(".app") { urls.append(u) }
                else if let sub = try? fm.contentsOfDirectory(atPath: u.path) {
                    urls += sub.filter { $0.hasSuffix(".app") }.map { u.appendingPathComponent($0) }
                }
            }
            for u in urls {
                guard let b = Bundle(url: u), let id = b.bundleIdentifier, !id.hasPrefix("com.apple.") else { continue }
                let name = (b.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (b.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? u.deletingPathExtension().lastPathComponent
                out.append((id, name))
            }
        }
        return out
    }

    // MARK: alerts

    private func flag(_ kind: GuardianAlert.Kind, key: String, cooldown: TimeInterval, title: String, detail: String,
                       bundleID: String? = nil, appName: String? = nil) {
        let now = Date()
        if let until = state.cooldown[key], until > now { return }
        state.cooldown[key] = now.addingTimeInterval(cooldown)
        state.cooldown = state.cooldown.filter { $0.value > now }
        let a = GuardianAlert(id: UUID(), date: now, kind: kind, title: title, detail: detail,
                              bundleID: bundleID, appName: appName, read: false)
        alerts.insert(a, at: 0)
        if alerts.count > 100 { alerts.removeLast(alerts.count - 100) }
        klog("gözetim: \(title)")
        save()
        guard notify, !ProfileStore.shared.holdNotifications else { return }
        let center = UNUserNotificationCenter.current()
        let id = "kartov-guardian-" + a.id.uuidString
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = detail
            content.sound = .default
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
        }
    }

    func markAllRead() {
        for i in alerts.indices { alerts[i].read = true }
        save()
    }

    func dismiss(_ a: GuardianAlert) {
        alerts.removeAll { $0.id == a.id }
        save()
    }

    func clearAlerts() {
        alerts = []
        save()
    }

    /// Forgets readings and alerts (Settings › Reset).
    func resetData() {
        state = GuardianState()
        alerts = []
        growth = []
        forecast = StorageForecast.make([])
        recordDiskSample(force: true)
        save()
    }

    // MARK: energy

    func startLiveEnergy() {
        refreshDayEnergy()
        guard energyTimer == nil else { return }
        livePrev = [:]
        sampleLiveEnergy()
        energyTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sampleLiveEnergy() }
        }
    }

    func stopLiveEnergy() {
        energyTimer?.invalidate()
        energyTimer = nil
    }

    private func sampleLiveEnergy() {
        let now = Date()
        var next: [pid_t: Bool] = [:]
        var rows: [EnergyRow] = []
        let me = ProcessInfo.processInfo.processIdentifier
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && app.processIdentifier != me {
            let pid = app.processIdentifier
            guard let u = Self.usage(pid) else { continue }
            next[pid] = true
            var watts = 0.0
            if let p = livePrev[pid], u.energy >= p.energy {
                let dt = now.timeIntervalSince(p.at)
                if dt > 0.5 { watts = Double(u.energy - p.energy) / 1e9 / dt }
            } else {
                livePrev[pid] = (u.energy, now)
            }
            rows.append(EnergyRow(id: "\(pid)", name: app.localizedName ?? L("Uygulama"), bundleID: app.bundleIdentifier,
                                  icon: app.icon, watts: watts, joules: 0))
        }
        // Energy counters move in bursts, so the live figure is the average since the page opened
        // (first reading per program kept in livePrev).
        livePrev = livePrev.filter { next[$0.key] != nil }
        liveEnergy = rows.sorted { $0.watts > $1.watts }
    }

    func refreshDayEnergy() {
        let onBattery = state.energy.contains { !$0.onBattery.isEmpty }
        var sum: [String: Double] = [:]
        for b in state.energy {
            for (id, j) in (onBattery ? b.onBattery : b.total) { sum[id, default: 0] += j }
        }
        let hours = Double(max(1, state.energy.count))
        dayEnergyOnBattery = onBattery
        dayEnergy = sum.sorted { $0.value > $1.value }.prefix(8).map { id, j in
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
            return EnergyRow(id: id, name: state.names[id] ?? id, bundleID: id,
                             icon: url.map { NSWorkspace.shared.icon(forFile: $0.path) },
                             watts: j / (hours * 3600), joules: j)
        }
    }

    // MARK: crash detective

    func loadCrashes(force: Bool = false) {
        guard !crashesLoading, force || !crashesLoaded else { return }
        crashesLoading = true
        Task.detached(priority: .utility) {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let found = CrashReportParser.scan(
                folders: [home.appendingPathComponent("Library/Logs/DiagnosticReports"),
                          URL(fileURLWithPath: "/Library/Logs/DiagnosticReports")],
                since: Date().addingTimeInterval(-30 * 86_400))
            await MainActor.run {
                let g = Guardian.shared
                g.crashes = found
                g.crashesLoaded = true
                g.crashesLoading = false
            }
        }
    }

    func toggleCrashGroup(_ id: String) {
        if openCrashGroups.contains(id) { openCrashGroups.remove(id) } else { openCrashGroups.insert(id) }
    }

    // MARK: privacy inspector

    func loadPrivacy() {
        guard !privacyLoading else { return }
        privacyLoading = true
        Task.detached(priority: .utility) {
            let result = PrivacyInspector.read()
            await MainActor.run {
                let g = Guardian.shared
                g.privacy = result.apps
                g.privacyReadable = result.readable
                g.privacyLoading = false
            }
        }
    }

    /// Clears the permissions an uninstalled program left behind (`tccutil reset All <bundle id>`).
    func resetPermissions(of app: PrivacyApp) {
        privacyConfirm = nil
        guard let id = app.bundleID, !app.installed else { return }
        let ok = PrivacyInspector.reset(bundleID: id)
        privacyMessage = ok ? L("{0} için kalan izinler sıfırlandı.", app.name)
                            : L("macOS izinleri sıfırlamadı. Sistem Ayarları'ndan kaldırabilirsin.")
        loadPrivacy()
    }

    // MARK: low-level readings

    struct Usage { let cpu: UInt64; let energy: UInt64 }

    /// Processor time (ns) and energy (nJ) of a process, if we may read it. Recent macOS
    /// reports measured energy (`ri_energy_nj`, rusage v6); older systems fall back to v4.
    nonisolated static func usage(_ pid: pid_t) -> Usage? {
        var v6 = rusage_info_v6()
        let r6 = withUnsafeMutablePointer(to: &v6) { ptr -> Int32 in
            ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V6, $0)
            }
        }
        if r6 == 0 {
            let cpu = (v6.ri_user_time + v6.ri_system_time) &* timebase.numer / timebase.denom
            return Usage(cpu: cpu, energy: v6.ri_energy_nj)
        }
        var info = rusage_info_v4()
        let r = withUnsafeMutablePointer(to: &info) { ptr -> Int32 in
            ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        guard r == 0 else { return nil }
        let cpu = (info.ri_user_time + info.ri_system_time) &* timebase.numer / timebase.denom
        return Usage(cpu: cpu, energy: 0)
    }

    nonisolated static func allPIDs() -> [pid_t] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        let got = pids.withUnsafeMutableBufferPointer { buf -> Int32 in
            proc_listallpids(buf.baseAddress, Int32(buf.count * MemoryLayout<pid_t>.size))
        }
        guard got > 0 else { return [] }
        return pids.prefix(Int(got)).filter { $0 > 0 }
    }

    nonisolated static func processName(_ pid: pid_t) -> String? {
        var buf = [CChar](repeating: 0, count: 256)
        let len = proc_name(pid, &buf, UInt32(buf.count))
        return len > 0 ? String(cString: buf) : nil
    }

    nonisolated static func pressureLevel() -> Int {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else { return 1 }
        return Int(level)
    }

    nonisolated static func onBattery() -> Bool {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(blob)?.takeUnretainedValue() else { return false }
        return (type as String) == kIOPSBatteryPowerValue
    }

    /// Minutes of battery left, if macOS has an estimate.
    nonisolated static func batteryMinutesLeft() -> Int? {
        let t = IOPSGetTimeRemainingEstimate()
        guard t > 0 else { return nil }
        return Int(t / 60)
    }

    // MARK: storage

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let s = try? decoder.decode(GuardianState.self, from: data) {
            state = s
            alerts = s.alerts
            forecast = StorageForecast.make(s.disk)
        }
    }

    func save() {
        lastSave = Date()
        state.alerts = alerts
        let snapshot = state
        let url = fileURL
        Task.detached(priority: .utility) {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(snapshot) else { return }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }
}
