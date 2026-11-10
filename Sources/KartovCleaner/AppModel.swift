import SwiftUI
import AppKit
import Combine
import KartovCore

enum AppSection: String, Hashable, CaseIterable, Identifiable {
    case dashboard, overview, scan, results, projects, fullScan, system, analysis, guardian, maintenance, history, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .dashboard: return L("Ana sayfa")
        case .overview: return L("Genel bakış")
        case .scan: return L("Tarama")
        case .results: return L("Bulunanlar")
        case .projects: return L("Projeler")
        case .fullScan: return L("Tam tarama")
        case .system: return L("Sistem durumu")
        case .maintenance: return L("Otomatik bakım")
        case .history: return L("Geçmiş")
        case .settings: return L("Ayarlar")
        case .analysis: return L("Analiz")
        case .guardian: return L("Gözetim")
        }
    }
    var symbol: String {
        switch self {
        case .dashboard: return "globe.europe.africa.fill"
        case .overview: return "square.grid.2x2.fill"
        case .scan: return "magnifyingglass"
        case .results: return "square.stack.3d.up.fill"
        case .projects: return "film.stack.fill"
        case .fullScan: return "chart.pie.fill"
        case .system: return "speedometer"
        case .maintenance: return "clock.badge.checkmark"
        case .history: return "clock.arrow.circlepath"
        case .settings: return "gearshape"
        case .analysis: return "chart.bar.xaxis"
        case .guardian: return "shield.lefthalf.filled"
        }
    }
}

enum ScanPhase: Equatable {
    case idle, scanning, results, cleaning, done
}

enum LocationStatus: Equatable {
    case queued, scanning, done, skipped(SkipReason)
}

struct LocationState: Identifiable, Equatable {
    let id: String          // rule id
    let name: String
    let paths: String
    var status: LocationStatus = .queued
    var bytes: Int64 = 0
    var items: Int = 0
}

struct RecentFind: Identifiable, Equatable {
    let id = UUID()
    let path: String
    let size: Int64
}

/// One part of an app's cache, e.g. After Effects → disk cache.
struct CachePart: Identifiable, Equatable {
    var id: String { key }
    let key: String          // selection key
    let ruleID: String
    let title: String
    let detail: String
    let size: Int64
    let items: [FoundItem]
    let locked: Bool
    var kept: Bool
}

/// One row on the results screen.
struct CacheGroup: Identifiable, Equatable {
    let id: String
    let section: CategoryGroup
    let title: String
    let iconKey: String?
    let parts: [CachePart]
    var size: Int64 { parts.reduce(0) { $0 + $1.size } }
    var selectedSize: Int64 { parts.filter { !$0.kept && !$0.locked }.reduce(0) { $0 + $1.size } }
    var locked: Bool { parts.allSatisfy(\.locked) }
    var state: ToggleState {
        let open = parts.filter { !$0.locked }
        if open.isEmpty { return .locked }
        let kept = open.filter(\.kept).count
        if kept == 0 { return .clean }
        if kept == open.count { return .keep }
        return .mixed
    }
}

enum ToggleState { case clean, keep, mixed, locked }

struct FlyingItem: Identifiable, Equatable {
    let id: String
    let iconKey: String?
    let title: String
    let isUserFile: Bool
}

enum FullSort: String, CaseIterable, Identifiable {
    case size, name, oldest
    var id: String { rawValue }
    var title: String {
        switch self { case .size: return L("Boyut"); case .name: return L("Ad"); case .oldest: return L("En eski") }
    }
}

/// Collects scan results inside a background task.
final class FoundBox: @unchecked Sendable { var items: [FoundItem] = [] }

/// What a click on the menu bar icon does.
enum MenuBarAction: String, CaseIterable, Identifiable {
    case panel, clean, optimize, both
    var id: String { rawValue }
    var title: String {
        switch self {
        case .panel: return L("Küçük paneli aç")
        case .clean: return L("Hızlı temizlik yap")
        case .optimize: return L("Belleği optimize et")
        case .both: return L("Temizle ve optimize et")
        }
    }
}

enum AutoFrequency: String, CaseIterable, Identifiable {
    case daily, weekly, monthly
    var id: String { rawValue }
    var title: String {
        switch self { case .daily: return L("Her gün"); case .weekly: return L("Haftada bir"); case .monthly: return L("Ayda bir") }
    }
    var interval: TimeInterval {
        switch self { case .daily: return 86_400; case .weekly: return 7 * 86_400; case .monthly: return 30 * 86_400 }
    }
}

struct SectionBytes: Identifiable {
    let group: CategoryGroup
    let bytes: Int64
    var id: CategoryGroup { group }
}

/// An open program that holds caches chosen for cleaning.
struct LockedApp: Identifiable {
    let id: String
    let name: String
    let icon: NSImage?
    var bytes: Int64
    let app: NSRunningApplication
}

@MainActor
final class AppModel: ObservableObject {
    @Published var section: AppSection = .dashboard
    @Published var phase: ScanPhase = .idle
    @Published var hasFullDiskAccess = true

    // Scan
    @Published var locations: [LocationState] = []
    @Published var currentPath = ""
    @Published var filesSeen = 0
    @Published var foundBytes: Int64 = 0
    @Published var recent: [RecentFind] = []
    @Published var items: [FoundItem] = []
    @Published var lastScanDate: Date?

    // Selection and results
    @Published var expanded: Set<String> = ["After Effects"]
    @Published private(set) var kept: Set<String> = []
    @Published var lastRecord: CleanRecord?
    @Published var history: [CleanRecord] = []
    @Published var cleaningProgress: Double = 0
    @Published var openRecords: Set<UUID> = []
    /// "Some programs are open" step before cleaning.
    @Published var showLockedSheet = false
    @Published var quittingForClean = false
    @Published var lockedSheetMessage: String?
    /// Open programs the user chose to leave running (bundle ids), for this sheet only.
    @Published var lockedKeepOpen: Set<String> = []
    /// Items of profile-protected groups the user chose to clean anyway (this session only).
    @Published var released: Set<String> = []
    private var profileWatch: AnyCancellable?
    private var guardianObserver: NSObjectProtocol?
    @Published var errorMessage: String?
    /// Items of opt-in rules (user files, history, cookies, backups) the user chose to clean.
    @Published private(set) var optedIn: Set<String> = []
    @Published var showConfirm = false

    // Clean animation
    @Published var cleanAnimationStart: Date?
    @Published var cleanFinishedAt: Date?
    @Published var flying: [FlyingItem] = []
    @Published var cleanStartDirt: Double = 0

    // System Data (administrator)
    @Published var snapshotCount: Int?
    @Published var installDataPresent = false
    @Published var systemPurging = false
    @Published var systemPurgeMessage: String?

    // Closing running apps so their caches can be cleaned
    @Published var quitting: Set<String> = []        // group ids being closed
    @Published var quitStuck: Set<String> = []       // asked to quit but still open after a while
    @Published var forceQuitTarget: CacheGroup?      // waiting for the user's confirmation
    @Published var quitMessage: String?

    let allRules: [CleanRule]
    /// Rules used for scanning: personal photos and videos only when the user turned them on.
    var rules: [CleanRule] { allRules }
    private let store = HistoryStore()
    private let defaults = UserDefaults.standard

    // Settings
    @Published var autoEnabled: Bool {
        didSet {
            defaults.set(autoEnabled, forKey: "autoEnabled")
            if autoEnabled && !oldValue { autoEnabledAt = Date(); defaults.set(autoEnabledAt, forKey: "autoEnabledAt") }
            scheduleAutoCheck()
        }
    }
    private var autoEnabledAt: Date?
    /// Hour of day (0-23) the maintenance runs at.
    @Published var autoHour: Int { didSet { defaults.set(autoHour, forKey: "autoHour") } }
    /// Weekday for weekly runs (1 = Sunday … 7 = Saturday, like Calendar).
    @Published var autoWeekday: Int { didSet { defaults.set(autoWeekday, forKey: "autoWeekday") } }
    /// Day of month (1-28) for monthly runs.
    @Published var autoMonthDay: Int { didSet { defaults.set(autoMonthDay, forKey: "autoMonthDay") } }
    /// Categories automatic maintenance may clean.
    @Published var autoGroups: Set<CategoryGroup> { didSet { defaults.set(autoGroups.map(\.rawValue), forKey: "autoGroups") } }
    /// Clean only when at least this much has piled up (bytes); 0 = always.
    @Published var autoMinBytes: Int64 { didSet { defaults.set(autoMinBytes, forKey: "autoMinBytes") } }
    /// Do not run on battery power.
    @Published var autoOnlyOnPower: Bool { didSet { defaults.set(autoOnlyOnPower, forKey: "autoOnlyOnPower") } }
    /// Only clean items untouched for at least this many days (0 = any age).
    @Published var autoMinAgeDays: Int { didSet { defaults.set(autoMinAgeDays, forKey: "autoMinAgeDays") } }
    @Published var autoSound: Bool { didSet { defaults.set(autoSound, forKey: "autoSound") } }
    /// Dry run result: what maintenance would clean right now, per category.
    @Published var autoPreview: [CategoryGroup: Int64]?
    /// Keep running after the window closes (menu bar icon, starts with the Mac).
    @Published var runInBackground: Bool {
        didSet {
            defaults.set(runInBackground, forKey: "runInBackground")
            if runInBackground != launchAtLogin { setLaunchAtLogin(runInBackground) }
        }
    }
    /// Whether the user has answered the "run in the background?" question.
    @Published var askedBackground: Bool { didSet { defaults.set(askedBackground, forKey: "askedBackground") } }
    @Published var showMenuBarIcon: Bool { didSet { defaults.set(showMenuBarIcon, forKey: "showMenuBarIcon"); StatusBar.shared.refresh() } }
    @Published var menuBarAction: MenuBarAction { didSet { defaults.set(menuBarAction.rawValue, forKey: "menuBarAction") } }
    /// Look for junk as soon as the home screen opens.
    @Published var scanOnLaunch: Bool { didSet { defaults.set(scanOnLaunch, forKey: "scanOnLaunch") } }
    /// Play the "emptied the trash" sound after a clean.
    @Published var cleanSound: Bool { didSet { defaults.set(cleanSound, forKey: "cleanSound") } }
    @Published var language: AppLanguage = I18n.choice {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: I18n.defaultsKey)
            // macOS's own menus (Quit, Window…) follow this list.
            if language == .system { UserDefaults.standard.removeObject(forKey: "AppleLanguages") }
            else { UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages") }
        }
    }
    /// The language picked differs from the one running: a restart is needed.
    var languageNeedsRestart: Bool { language != launchLanguage }
    private let launchLanguage = I18n.choice
    // Analysis: every program, open or installed
    enum RunningSort: String, CaseIterable, Identifiable {
        case memory, cpu, disk
        var id: String { rawValue }
        var title: String {
            switch self { case .memory: return L("Bellek"); case .cpu: return L("İşlemci"); case .disk: return L("Disk") }
        }
    }
    @Published var runningApps: [RunningAppInfo] = []
    @Published var runningSort: RunningSort = .memory
    @Published var installedApps: [InstalledAppInfo] = []
    @Published var installedLoading = false
    /// The program waiting for "yes, remove it".
    @Published var removeCandidate: String?
    @Published var analysisMessage: String?
    private var analysisTimer: Timer?

    /// Two-step confirmation for "reset everything".
    @Published var confirmResetAll = false
    /// Set by the main window so the menu bar icon can reopen it after it was closed.
    var openMainWindow: (() -> Void)?
    var showBackgroundQuestion: Bool { !showTutorial && !askedBackground }
    @Published var autoPreviewing = false
    @Published var autoFrequency: AutoFrequency { didSet { defaults.set(autoFrequency.rawValue, forKey: "autoFrequency") } }
    @Published var autoEmptyTrash: Bool { didSet { defaults.set(autoEmptyTrash, forKey: "autoEmptyTrash") } }
    @Published var lastAutoRun: Date? { didSet { defaults.set(lastAutoRun, forKey: "lastAutoRun") } }
    @Published var autoRunning = false
    @Published var autoMessage: String?
    @Published var launchAtLogin: Bool = LoginItem.isEnabled
    @Published var showTutorial: Bool
    @Published var tutorialStep = 0
    private var autoTimer: Timer?

    // Full scan: everything on the Mac by size
    @Published var fullEntries: [DiskEntry] = []
    @Published var fullFolders: [FolderUsage] = []
    @Published var fullScanning = false
    @Published var fullPath = ""
    @Published var fullFiles = 0
    @Published var fullScanDate: Date?
    @Published var fullFilter: DiskKind? = nil
    @Published var fullSort: FullSort = .size
    @Published var fullQuery = ""
    @Published var fullSelected: Set<String> = []
    /// Last row clicked without Shift: the start of a Shift-click range.
    private var fullAnchor: String?
    @Published var fullLimit = 200
    @Published var showFullConfirm = false
    @Published var fullMessage: String?
    private var fullTask: Task<Void, Never>?

    // System status
    @Published var cpu: Double = 0
    @Published var cpuHistory: [Double] = []
    @Published var memory: SystemMonitor.Memory?
    @Published var battery: SystemMonitor.Battery?
    @Published var topApps: [SystemMonitor.AppMemory] = []
    @Published var startupItems: [SystemMonitor.StartupItem] = []
    @Published var optimizeBusy: String?
    @Published var optimizeMessage: String?
    private var monitorTimer: Timer?
    private var lastTicks: SystemMonitor.CPUTicks?
    private var scanTask: Task<Void, Never>?
    private var progressBuffer: (path: String, files: Int)?
    private var filesBeforeLocation = 0

    init() {
        autoEnabled = UserDefaults.standard.bool(forKey: "autoEnabled")
        autoFrequency = AutoFrequency(rawValue: UserDefaults.standard.string(forKey: "autoFrequency") ?? "") ?? .weekly
        autoEmptyTrash = UserDefaults.standard.bool(forKey: "autoEmptyTrash")
        let ud = UserDefaults.standard
        autoEnabledAt = ud.object(forKey: "autoEnabledAt") as? Date
        autoHour = ud.object(forKey: "autoHour") as? Int ?? 13
        autoWeekday = ud.object(forKey: "autoWeekday") as? Int ?? 2
        autoMonthDay = ud.object(forKey: "autoMonthDay") as? Int ?? 1
        var groups: Set<CategoryGroup> = [.apps, .creative, .browsers, .developer, .logs]
        if let saved = ud.stringArray(forKey: "autoGroups") {
            groups = Set(saved.compactMap(CategoryGroup.init(rawValue:)))
        } else if ud.bool(forKey: "autoEmptyTrash") {
            groups.insert(.trash)
        }
        autoGroups = groups
        autoMinBytes = (ud.object(forKey: "autoMinBytes") as? NSNumber)?.int64Value ?? 0
        autoOnlyOnPower = ud.object(forKey: "autoOnlyOnPower") as? Bool ?? true
        autoMinAgeDays = ud.object(forKey: "autoMinAgeDays") as? Int ?? 0
        autoSound = ud.object(forKey: "autoSound") as? Bool ?? false
        runInBackground = ud.bool(forKey: "runInBackground")
        scanOnLaunch = ud.object(forKey: "scanOnLaunch") as? Bool ?? true
        cleanSound = ud.object(forKey: "cleanSound") as? Bool ?? true
        askedBackground = ud.bool(forKey: "askedBackground")
        showMenuBarIcon = ud.object(forKey: "showMenuBarIcon") as? Bool ?? true
        menuBarAction = MenuBarAction(rawValue: ud.string(forKey: "menuBarAction") ?? "") ?? .panel
        lastAutoRun = UserDefaults.standard.object(forKey: "lastAutoRun") as? Date
        showTutorial = !UserDefaults.standard.bool(forKey: "tutorialDone.v5")
        do {
            allRules = try RuleSet.bundled().rules
        } catch {
            allRules = []
            errorMessage = L("Temizlik kuralları yüklenemedi: {0}", error.localizedDescription)
        }
        let snap = store.load()
        kept = snap.kept
        optedIn = snap.optedIn
        history = snap.records.sorted { $0.date > $1.date }
        refreshPermissions()
        klog("model hazır · Tam Disk Erişimi: \(hasFullDiskAccess ? "açık" : "kapalı")")
        refreshSystemData()
        scheduleAutoCheck()
        StatusBar.shared.install(model: self)
        Updater.shared.start()
        Guardian.shared.start()
        // A new work profile changes what is kept: redraw everything that depends on it.
        profileWatch = ProfileStore.shared.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.objectWillChange.send() }
        }
        guardianObserver = NotificationCenter.default.addObserver(forName: .kartovOpenGuardian, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.section = .guardian }
        }
    }

    /// Adds a record made outside the cleanup screen (App Dependency Map) to History.
    func addRecord(_ r: CleanRecord) {
        history.insert(r, at: 0)
        store.update { $0.records.insert(r, at: 0) }
    }

    /// Answer to the first-run question.
    func chooseBackground(_ on: Bool) {
        runInBackground = on
        askedBackground = true
    }

    /// One-click clean from the menu bar: the same safe set as automatic maintenance,
    /// without the size limit and without moving the schedule.
    func quickClean() { runAutoMaintenance(quick: true) }

    // MARK: tutorial

    func finishTutorial() {
        showTutorial = false
        tutorialStep = 0
        section = .dashboard
        defaults.set(true, forKey: "tutorialDone.v5")
    }

    func openTutorial() {
        goToTourStep(0)
        showTutorial = true
    }

    /// Moves the tour and opens the tab it talks about.
    func goToTourStep(_ i: Int) {
        tutorialStep = max(0, min(i, Tour.steps.count - 1))
        section = Tour.steps[tutorialStep].section
    }

    /// The tab the tour is pointing at, for the sidebar highlight.
    var tourSection: AppSection? { showTutorial ? Tour.steps[min(tutorialStep, Tour.steps.count - 1)].section : nil }

    // MARK: automatic maintenance

    /// Categories the user can hand to automatic maintenance. Personal files and history never.
    static let autoAllowedGroups: [CategoryGroup] = [.apps, .creative, .browsers, .developer, .logs, .updates, .trash]

    static let weekdayNames = [L("Pazar"), L("Pazartesi"), L("Salı"), L("Çarşamba"), L("Perşembe"), L("Cuma"), L("Cumartesi")]

    /// "Her Pazartesi 13:00" style summary of the schedule.
    var autoScheduleText: String {
        let time = String(format: "%02d:00", autoHour)
        switch autoFrequency {
        case .daily: return L("Her gün {0}", time)
        case .weekly: return L("Her {0} {1}", Self.weekdayNames[max(0, min(6, autoWeekday - 1))], time)
        case .monthly: return L("Her ayın {0}. günü {1}", autoMonthDay, time)
        }
    }

    /// Next scheduled run: the first chosen time slot after the last run (or after switching it on).
    /// A slot missed while the Mac was asleep runs as soon as it wakes.
    var nextAutoRun: Date? {
        guard autoEnabled else { return nil }
        let base = lastAutoRun ?? autoEnabledAt ?? Date()
        var c = DateComponents()
        c.hour = autoHour; c.minute = 0
        switch autoFrequency {
        case .daily: break
        case .weekly: c.weekday = autoWeekday
        case .monthly: c.day = autoMonthDay
        }
        return Calendar.current.nextDate(after: base, matching: c, matchingPolicy: .nextTime)
    }

    /// Checks every 15 minutes (and right away) whether maintenance is due.
    func scheduleAutoCheck() {
        autoTimer?.invalidate()
        autoTimer = nil
        guard autoEnabled else { return }
        autoTimer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.runAutoIfDue() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in self?.runAutoIfDue() }
    }

    func runAutoIfDue() {
        guard autoEnabled, let next = nextAutoRun, next <= Date() else { return }
        if autoOnlyOnPower, let b = SystemMonitor.battery(), !b.charging, b.percent < 100 { return }   // try again later
        runAutoMaintenance()
    }

    /// The rules automatic maintenance uses: only chosen categories, only rules that are on by
    /// default, never personal files, history, cookies or device backups.
    var autoRules: [CleanRule] {
        allRules.filter { r in
            autoGroups.contains(r.group) && r.defaultOn && !r.group.isUserData && r.group != .privacy &&
            r.id != "backups.ios" && !ProfileStore.shared.protects(r.group)
        }
    }

    private func autoScan(_ rules: [CleanRule]) async -> [FoundItem] {
        let keptKeys = kept
        let minAge = autoMinAgeDays
        return await Task.detached(priority: .utility) {
            let box = FoundBox()
            let cutoff = Date().addingTimeInterval(-Double(minAge) * 86_400)
            CacheScanner(rules: rules, running: WorkspaceRunningApps()).run { e in
                guard case .found(let item) = e, !item.locked, !keptKeys.contains(item.selectionKey) else { return }
                if minAge > 0 {
                    let d = (try? item.url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                    if let d, d > cutoff { return }
                }
                box.items.append(item)
            }
            return box.items
        }.value
    }

    /// Shows what maintenance would clean now, without deleting anything.
    func previewAutoMaintenance() {
        guard !autoPreviewing else { return }
        autoPreviewing = true
        let rules = autoRules
        Task {
            let found = await autoScan(rules)
            var d: [CategoryGroup: Int64] = [:]
            for i in found { if let r = rule(i.ruleID) { d[r.group, default: 0] += i.size } }
            autoPreview = d
            autoPreviewing = false
        }
    }

    /// Scans with the chosen categories and cleans what is found, skipping running apps,
    /// anything marked "keep" and items newer than the chosen age.
    func runAutoMaintenance(quick: Bool = false) {
        Task { await performAutoMaintenance(quick: quick) }
    }

    @discardableResult
    func performAutoMaintenance(quick: Bool = false) async -> String? {
        guard !autoRunning, phase != .scanning, phase != .cleaning else { return nil }
        autoRunning = true
        autoMessage = nil
        var rules = autoRules
        if rules.isEmpty && quick {
            let safeGroups: Set<CategoryGroup> = [.apps, .creative, .browsers, .developer, .logs]
            rules = allRules.filter { safeGroups.contains($0.group) && $0.defaultOn && $0.safety == .safe &&
                !ProfileStore.shared.protects($0.group) }
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let all = allRules
        let threshold = quick ? 0 : autoMinBytes
        let label = quick ? L("Hızlı temizlik") : L("Otomatik bakım")
        do {
            let found = await autoScan(rules)
            let total = found.reduce(Int64(0)) { $0 + $1.size }
            if !quick { lastAutoRun = Date() }
            if total == 0 || total < threshold {
                autoRunning = false
                autoMessage = total == 0 ? L("{0} çalıştı; temizlenecek bir şey yoktu.", label)
                    : L("{0} birikmiş; sınırın ({1}) altında olduğu için dokunulmadı.", KBytes.format(total), KBytes.format(threshold))
                return autoMessage
            }
            let record: CleanRecord = await Task.detached(priority: .utility) {
                Cleaner(rules: all, running: WorkspaceRunningApps()).clean(found, measureAt: home)
            }.value
            var r = record
            r.automatic = true
            autoRunning = false
            history.insert(r, at: 0)
            store.update { $0.records.insert(r, at: 0) }
            autoMessage = L("{0} {1} yer açtı.", label, KBytes.format(r.bytesCleaned))
            if (autoSound || quick) && cleanSound { CleanSound.play() }
            if quick && !items.isEmpty { startScan() }   // keep the globe honest after a quick clean
            klog(autoMessage ?? "")
            return autoMessage
        }
    }

    // MARK: analysis

    var sortedRunning: [RunningAppInfo] {
        switch runningSort {
        case .memory: return runningApps.sorted { $0.memory > $1.memory }
        case .cpu: return runningApps.sorted { $0.cpu > $1.cpu }
        case .disk: return runningApps.sorted { $0.diskRate == $1.diskRate ? $0.diskTotal > $1.diskTotal : $0.diskRate > $1.diskRate }
        }
    }

    var mostUsedApps: [InstalledAppInfo] {
        installedApps.filter { ($0.useCount ?? 0) > 0 }.sorted { ($0.useCount ?? 0) > ($1.useCount ?? 0) }
    }

    var largestApps: [InstalledAppInfo] {
        installedApps.filter { $0.size != nil }.sorted { ($0.size ?? 0) > ($1.size ?? 0) }
    }

    /// Not opened for three months (or never, as far as macOS knows).
    var forgottenApps: [InstalledAppInfo] {
        let cutoff = Date().addingTimeInterval(-90 * 86_400)
        return installedApps.filter { !$0.protected && ($0.lastUsed.map { $0 < cutoff } ?? true) }
            .sorted { ($0.size ?? 0) > ($1.size ?? 0) }
    }

    func startAnalysis() {
        sampleRunning()
        startMonitoring()
        if analysisTimer == nil {
            analysisTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.sampleRunning() }
            }
        }
        if installedApps.isEmpty { loadInstalled() }
    }

    func stopAnalysis() {
        analysisTimer?.invalidate()
        analysisTimer = nil
        stopMonitoring()
    }

    func sampleRunning() { runningApps = AppAnalyzer.running() }

    func loadInstalled() {
        guard !installedLoading else { return }
        installedLoading = true
        Task {
            let list = await Task.detached(priority: .utility) { AppAnalyzer.installed() }.value
            installedApps = list
            // Sizes take a while; fill them in one by one, biggest folders first doesn't matter.
            for app in list {
                let url = app.url
                let bytes = await Task.detached(priority: .utility) { AppAnalyzer.size(of: url) }.value
                if let i = installedApps.firstIndex(where: { $0.id == app.id }) { installedApps[i].size = bytes }
            }
            installedLoading = false
        }
    }

    func forceQuit(pid: pid_t) {
        NSRunningApplication(processIdentifier: pid)?.forceTerminate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.sampleRunning() }
    }

    func openApp(_ url: URL) {
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Moves a program (and its leftover settings and caches) to the Trash. Undo from History.
    func removeApp(_ app: InstalledAppInfo) {
        removeCandidate = nil
        guard !app.protected else { return }
        if let id = app.bundleID {
            for r in NSWorkspace.shared.runningApplications where r.bundleIdentifier == id { r.terminate() }
        }
        let entry = DiskEntry(url: app.url, name: app.name, kind: .app, size: app.size ?? 0, modified: nil,
                              lastUsed: app.lastUsed, bundleID: app.bundleID, protected: false)
        let remover = DiskRemover()
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            let record = await Task.detached { remover.trash([entry]) }.value
            if record.items.contains(where: { $0.status == .trashed }) {
                installedApps.removeAll { $0.id == app.id }
                fullEntries.removeAll { $0.url.path == app.url.path }
                history.insert(record, at: 0)
                store.update { $0.records.insert(record, at: 0) }
                analysisMessage = L("{0} çöp kutusuna taşındı. Geri almak için Geçmiş › Geri al.", app.name)
                if cleanSound { CleanSound.play() }
            } else {
                analysisMessage = L("{0} kaldırılamadı. Açıksa kapatıp yeniden dene.", app.name)
            }
        }
    }

    // MARK: system status

    func startMonitoring() {
        guard monitorTimer == nil else { return }
        lastTicks = SystemMonitor.cpuTicks()
        sampleSystem()
        startupItems = SystemMonitor.startupItems()
        monitorTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sampleSystem() }
        }
    }

    func stopMonitoring() {
        monitorTimer?.invalidate()
        monitorTimer = nil
    }

    func sampleSystem() {
        if let now = SystemMonitor.cpuTicks() {
            if let last = lastTicks {
                cpu = SystemMonitor.cpuUsage(from: last, to: now)
                cpuHistory.append(cpu)
                if cpuHistory.count > 40 { cpuHistory.removeFirst(cpuHistory.count - 40) }
            }
            lastTicks = now
        }
        memory = SystemMonitor.memory()
        battery = SystemMonitor.battery()
        topApps = SystemMonitor.topApps()
    }

    func quitApp(pid: pid_t) {
        NSRunningApplication(processIdentifier: pid)?.terminate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.sampleSystem() }
    }

    func runOptimize(_ id: String) {
        Task { await performOptimize(id) }
    }

    @discardableResult
    func performOptimize(_ id: String) async -> String? {
        guard optimizeBusy == nil else { return nil }
        optimizeBusy = id
        optimizeMessage = nil
        if memory == nil { sampleSystem() }
        let before = memory?.used
        let r = await Task.detached { id == "dns" ? SystemMonitor.flushDNS() : SystemMonitor.purgeMemory() }.value
        sampleSystem()
        var msg = r.1
        if r.0, id == "ram", let b = before, let after = memory?.used, b > after {
            msg += L(" {0} boşaldı.", KBytes.format(Int64(b - after)))
        }
        optimizeMessage = msg
        optimizeBusy = nil
        return msg
    }

    // MARK: one-click actions (menu bar)

    /// What the menu bar feedback bubble shows: the step running now, then the result.
    @Published var quickStatus: String?
    @Published var quickResults: [String] = []
    @Published var quickBusy = false

    func runQuick(_ action: MenuBarAction) {
        guard !quickBusy else { return }
        quickBusy = true
        quickResults = []
        Task {
            if action == .clean || action == .both {
                quickStatus = L("Önbellekler temizleniyor…")
                if let m = await performAutoMaintenance(quick: true) { quickResults.append(m) }
            }
            if action == .optimize || action == .both {
                quickStatus = L("Bellek boşaltılıyor… (Mac şifreni sorabilir)")
                if let m = await performOptimize("ram") { quickResults.append(m) }
            }
            quickStatus = nil
            quickBusy = false
        }
    }

    func removeStartupItem(_ item: SystemMonitor.StartupItem) {
        guard !item.systemWide else { return }
        do {
            try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
            optimizeMessage = L("{0} artık açılışta başlamayacak (bir sonraki oturum açışından itibaren). Dosyası çöp kutusunda.", item.name)
        } catch {
            optimizeMessage = L("{0} kaldırılamadı.", item.name)
        }
        startupItems = SystemMonitor.startupItems()
    }

    // MARK: full scan

    func startFullScan() {
        fullTask?.cancel()
        fullScanning = true
        fullEntries = []
        fullFolders = []
        fullSelected = []
        fullFiles = 0
        fullPath = ""
        fullMessage = nil
        fullLimit = 200
        let analyzer = DiskAnalyzer()
        fullTask = Task {
            let result = await Task.detached(priority: .userInitiated) { () -> DiskAnalyzer.Result in
                var last = Date.distantPast
                return analyzer.run { path, files in
                    guard Date().timeIntervalSince(last) > 0.1 else { return }
                    last = Date()
                    Task { @MainActor [weak self] in self?.fullPath = path; self?.fullFiles = files }
                }
            }.value
            guard !Task.isCancelled else { return }
            fullEntries = result.entries
            fullFolders = result.folders.sorted { $0.bytes > $1.bytes }
            fullFiles = result.filesSeen
            fullScanning = false
            fullScanDate = Date()
            klog("tam tarama bitti · \(result.entries.count) öğe")
        }
    }

    func cancelFullScan() {
        fullTask?.cancel()
        fullScanning = false
    }

    /// What the list shows: filtered by kind and search, sorted, capped for speed.
    var fullVisible: [DiskEntry] {
        let q = fullQuery.trimmingCharacters(in: .whitespaces).lowercased()
        var list = fullEntries.filter { e in
            (fullFilter == nil || e.kind == fullFilter) && (q.isEmpty || e.name.lowercased().contains(q))
        }
        switch fullSort {
        case .size: break
        case .name: list.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .oldest: list.sort { ($0.lastUsed ?? $0.modified ?? .distantFuture) < ($1.lastUsed ?? $1.modified ?? .distantFuture) }
        }
        return list
    }

    func bytes(of kind: DiskKind) -> Int64 {
        fullEntries.filter { $0.kind == kind }.reduce(0) { $0 + $1.size }
    }

    /// Click: toggles one row. Shift-click: selects every row between the last click and this one.
    func toggleFull(_ e: DiskEntry) {
        guard !e.protected else { return }
        if NSEvent.modifierFlags.contains(.shift), let anchor = fullAnchor {
            let list = Array(fullVisible.prefix(fullLimit))
            if let a = list.firstIndex(where: { $0.id == anchor }), let b = list.firstIndex(where: { $0.id == e.id }) {
                for item in list[min(a, b)...max(a, b)] where !item.protected { fullSelected.insert(item.id) }
                return
            }
        }
        if fullSelected.contains(e.id) { fullSelected.remove(e.id) } else { fullSelected.insert(e.id) }
        fullAnchor = e.id
    }

    /// Everything the list shows right now (current filter and search), except protected items.
    var fullSelectableVisible: [DiskEntry] { fullVisible.filter { !$0.protected } }

    var fullAllVisibleSelected: Bool {
        let v = fullSelectableVisible
        return !v.isEmpty && v.allSatisfy { fullSelected.contains($0.id) }
    }

    func selectAllVisible() {
        if fullAllVisibleSelected {
            for e in fullSelectableVisible { fullSelected.remove(e.id) }
        } else {
            for e in fullSelectableVisible { fullSelected.insert(e.id) }
        }
        fullAnchor = nil
    }

    func clearFullSelection() {
        fullSelected = []
        fullAnchor = nil
    }

    var fullSelectedEntries: [DiskEntry] { fullEntries.filter { fullSelected.contains($0.id) } }
    var fullSelectedBytes: Int64 { fullSelectedEntries.reduce(0) { $0 + $1.size } }

    /// Running apps among the selection must be closed first.
    var fullSelectedRunningApps: [String] {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        return fullSelectedEntries.filter { $0.kind == .app && $0.bundleID.map(running.contains) == true }.map(\.name)
    }

    func trashFullSelection() {
        let picked = fullSelectedEntries
        guard !picked.isEmpty else { return }
        // Close the selected apps that are open (they will ask to save if needed).
        let ids = Set(picked.compactMap(\.bundleID))
        for app in NSWorkspace.shared.runningApplications where app.bundleIdentifier.map(ids.contains) == true {
            app.terminate()
        }
        let remover = DiskRemover()
        Task {
            try? await Task.sleep(nanoseconds: ids.isEmpty ? 0 : 1_500_000_000)
            let record = await Task.detached { remover.trash(picked) }.value
            let moved = Set(record.items.filter { $0.status == .trashed }.map(\.originalPath))
            fullEntries.removeAll { moved.contains($0.url.path) }
            fullSelected = []
            history.insert(record, at: 0)
            store.update { $0.records.insert(record, at: 0) }
            let failed = record.items.filter { $0.status != .trashed }.count
            fullMessage = L("{0} çöp kutusuna taşındı. Geri almak için Geçmiş › Geri al.", KBytes.format(record.bytesInTrash)) +
                (failed > 0 ? L(" {0} öğe taşınamadı.", failed) : "")
            if cleanSound { CleanSound.play() }
        }
    }

    func setLaunchAtLogin(_ on: Bool) {
        launchAtLogin = LoginItem.set(on)
    }


    func refreshPermissions() {
        hasFullDiskAccess = Permissions.hasFullDiskAccess()
        if hasFullDiskAccess { fdaTimer?.invalidate(); fdaTimer = nil }
        else if fdaTimer == nil {
            // Keep checking while the permission screen is up, so it closes by itself once granted.
            fdaTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    if Permissions.hasFullDiskAccess() { self.refreshPermissions() }
                }
            }
        }
    }
    private var fdaTimer: Timer?

    func rule(_ id: String) -> CleanRule? { allRules.first { $0.id == id } }

    // MARK: scanning

    func startScan() {
        scanTask?.cancel()
        refreshPermissions()
        phase = .scanning
        section = .scan
        items = []
        recent = []
        foundBytes = 0
        filesSeen = 0
        filesBeforeLocation = 0
        currentPath = ""
        lastRecord = nil
        locations = rules.map { r in
            LocationState(id: r.id, name: r.appGroup.map { "\(L($0)) · \(r.name)" } ?? r.name,
                          paths: r.roots.joined(separator: " · "))
        }
        let scanner = CacheScanner(rules: rules, running: WorkspaceRunningApps())
        scanTask = Task { [weak self] in
            var lastFlush = Date.distantPast
            for await event in scanner.scan() {
                guard let self else { return }
                self.apply(event)
                // Path updates can arrive thousands of times a second; draw at most ~12 per second.
                if Date().timeIntervalSince(lastFlush) > 0.08 {
                    self.flushProgress()
                    lastFlush = Date()
                }
            }
            self?.flushProgress()
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        phase = items.isEmpty ? .idle : .results
        currentPath = ""
    }

    private func apply(_ event: ScanEvent) {
        switch event {
        case .locationStarted(let id):
            update(id) { $0.status = .scanning }
            filesBeforeLocation = filesSeen
        case .progress(_, let path, let files):
            progressBuffer = (path, files)
        case .found(let item):
            items.append(item)
            foundBytes += item.size
            update(item.ruleID) { $0.bytes += item.size; $0.items += 1 }
            recent.insert(RecentFind(path: item.url.path, size: item.size), at: 0)
            if recent.count > 8 { recent.removeLast(recent.count - 8) }
        case .locationFinished(let id, _, _):
            update(id) { $0.status = .done }
            if let p = progressBuffer { filesSeen = filesBeforeLocation + p.files }
            progressBuffer = nil
        case .locationSkipped(let id, let reason):
            update(id) { $0.status = .skipped(reason) }
        case .finished(let total):
            klog("tarama bitti · \(items.count) kalem · \(KBytes.format(total))")
            phase = .results
            lastScanDate = Date()
            currentPath = ""
        }
    }

    private func flushProgress() {
        guard let p = progressBuffer else { return }
        currentPath = p.path
        filesSeen = max(filesSeen, filesBeforeLocation + p.files)
    }

    private func update(_ id: String, _ change: (inout LocationState) -> Void) {
        guard let i = locations.firstIndex(where: { $0.id == id }) else { return }
        change(&locations[i])
    }

    var scanFraction: Double {
        guard !locations.isEmpty else { return 0 }
        let finished = locations.filter {
            switch $0.status { case .done, .skipped: return true; default: return false }
        }.count
        return Double(finished) / Double(locations.count)
    }

    // MARK: grouping for the results screen

    /// Items of rules that are on by default are cleaned unless kept; items of opt-in rules
    /// (the user's own files, history, cookies, backups) are kept unless chosen.
    func isKept(_ item: FoundItem) -> Bool {
        guard let r = rule(item.ruleID) else { return kept.contains(item.selectionKey) }
        if r.defaultOn == false { return !optedIn.contains(item.selectionKey) }
        // The work profile protects some groups: kept unless the user switches them on by hand.
        if ProfileStore.shared.protects(r.group) { return !released.contains(item.selectionKey) }
        return kept.contains(item.selectionKey)
    }

    var groups: [CacheGroup] {
        var byGroup: [String: [FoundItem]] = [:]
        for item in items {
            byGroup[item.appKey + "#" + (rule(item.ruleID)?.group.rawValue ?? ""), default: []].append(item)
        }
        var out: [CacheGroup] = []
        for (gid, list) in byGroup {
            guard let first = list.first, let firstRule = rule(first.ruleID) else { continue }
            var byRule: [String: [FoundItem]] = [:]
            for i in list { byRule[i.ruleID, default: []].append(i) }
            let parts: [CachePart] = byRule.compactMap { ruleID, its in
                guard let r = rule(ruleID) else { return nil }
                let size = its.reduce(Int64(0)) { $0 + $1.size }
                let title: String
                if r.group.isUserData { title = r.name }
                else if firstRule.childIsBundleID == true || r.appGroup == nil { title = r.name }
                else if its.count == 1, r.itemLevel == .children { title = r.name + " · " + its[0].name }
                else { title = r.name }
                return CachePart(key: its[0].selectionKey, ruleID: ruleID, title: title,
                                 detail: r.description, size: size, items: its,
                                 locked: its.allSatisfy(\.locked), kept: its.allSatisfy { isKept($0) })
            }.sorted { $0.size > $1.size }
            let isApp = firstRule.childIsBundleID == true || first.appBundleID != nil
            let title: String
            if firstRule.group.isUserData { title = first.name }
            else if isApp { title = AppInfoResolver.shared.name(for: first.appBundleID ?? first.appKey) }
            else if firstRule.appKeyFromGlob == true { title = first.appKey }
            else { title = firstRule.appGroup.map { L($0) } ?? firstRule.name }
            out.append(CacheGroup(id: gid, section: firstRule.group, title: title,
                                  iconKey: isApp ? (first.appBundleID ?? first.appKey) : nil, parts: parts))
        }
        return out.sorted { $0.size > $1.size }
    }

    var totalFound: Int64 { items.reduce(0) { $0 + $1.size } }

    var selectedItems: [FoundItem] { items.filter { !$0.locked && !isKept($0) } }
    var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + $1.size } }
    var keptBytes: Int64 { items.filter { !$0.locked && isKept($0) }.reduce(0) { $0 + $1.size } }
    var lockedBytes: Int64 { items.filter(\.locked).reduce(0) { $0 + $1.size } }
    var lockedAppNames: [String] {
        Array(Set(groups.filter { g in g.parts.contains(where: \.locked) }.map(\.title))).sorted()
    }

    /// Bytes per section, for the dashboard breakdown.
    var bytesBySection: [SectionBytes] {
        var d: [CategoryGroup: Int64] = [:]
        for i in items { if let r = rule(i.ruleID) { d[r.group, default: 0] += i.size } }
        return CategoryGroup.allCases.compactMap { g in d[g].map { SectionBytes(group: g, bytes: $0) } }
    }

    // MARK: keep / clean choices

    func toggle(group: CacheGroup) {
        let target: Bool = group.state == .clean || group.state == .mixed // true = keep all
        for part in group.parts where !part.locked { setKept(part, target) }
        persistChoices()
    }

    func toggle(part: CachePart) {
        guard !part.locked else { return }
        setKept(part, !part.kept)
        persistChoices()
    }

    private func setKept(_ part: CachePart, _ keep: Bool) {
        for item in part.items {
            if rule(item.ruleID)?.defaultOn == false {
                if keep { optedIn.remove(item.selectionKey) } else { optedIn.insert(item.selectionKey) }
            } else if let r = rule(item.ruleID), ProfileStore.shared.protects(r.group) {
                if keep { released.remove(item.selectionKey) } else { released.insert(item.selectionKey) }
            } else {
                if keep { kept.insert(item.selectionKey) } else { kept.remove(item.selectionKey) }
            }
        }
    }

    /// Forgets every clean in the list. Files already in the Trash stay there.
    func clearHistory() {
        history = []
        store.update { $0.records = [] }
    }

    /// Puts every setting back to how it was on first launch and restarts.
    func resetAllSettings() {
        if let id = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: id) }
        resetChoices()
        clearHistory()
        if launchAtLogin { setLaunchAtLogin(false) }
        Permissions.relaunch()
    }

    func resetChoices() {
        kept = []
        optedIn = []
        store.update { $0.kept = []; $0.optedIn = [] }
    }

    private func persistChoices() {
        let k = kept
        // Choices about the user's own files are for this session only: files change.
        let o = optedIn.filter { key in
            guard let ruleID = key.split(separator: "|").first else { return false }
            return rule(String(ruleID))?.group.isUserData != true
        }
        store.update { $0.kept = k; $0.optedIn = o }
    }

    /// Selected items whose rule deletes for good after asking (the Trash).
    var confirmItems: [FoundItem] { selectedItems.filter { rule($0.ruleID)?.confirm == true } }
    var confirmBytes: Int64 { confirmItems.reduce(0) { $0 + $1.size } }
    var confirmTrashBytes: Int64 { confirmItems.filter { rule($0.ruleID)?.group == .trash }.reduce(0) { $0 + $1.size } }
    /// Browsers whose history is selected.
    var selectedHistoryBrowsers: [String] {
        let names = selectedItems.compactMap { i -> String? in
            guard let r = rule(i.ruleID), r.group == .privacy else { return nil }
            return r.appGroup.map { L($0) } ?? r.name
        }
        return Array(Set(names)).sorted()
    }
    var selectedUserFileBytes: Int64 {
        selectedItems.filter { rule($0.ruleID)?.group.isUserData == true }.reduce(0) { $0 + $1.size }
    }

    /// The Clean button: asks first when the Trash would be emptied or personal files moved.
    func requestClean() {
        // Programs may have opened since the scan: look again before promising a number.
        refreshLocks()
        if lockedSelectedBytes > 0 && !lockedApps.isEmpty {
            lockedSheetMessage = nil
            lockedKeepOpen = []
            showLockedSheet = true
            return
        }
        proceedClean()
    }

    /// The usual path once open programs are dealt with: ask about the Trash, history and
    /// personal files when needed, otherwise clean right away.
    func proceedClean() {
        showLockedSheet = false
        guard selectedBytes > 0 else { return }
        if confirmBytes > 0 || selectedUserFileBytes > 0 {
            section = .results          // the question is asked on the results screen
            showConfirm = true
        } else {
            clean()
        }
    }

    /// Chosen items that cannot be cleaned now because their program is open.
    var lockedSelectedBytes: Int64 { items.filter { $0.locked && !isKept($0) }.reduce(0) { $0 + $1.size } }

    /// Open programs holding chosen items, with how much each holds.
    var lockedApps: [LockedApp] {
        var out: [String: LockedApp] = [:]
        for g in groups {
            let bytes = g.parts.filter { $0.locked && !$0.kept }.reduce(Int64(0)) { $0 + $1.size }
            guard bytes > 0 else { continue }
            for app in blockingApps(for: g) {
                guard let id = app.bundleIdentifier else { continue }
                var e = out[id] ?? LockedApp(id: id, name: app.localizedName ?? g.title, icon: app.icon, bytes: 0, app: app)
                e.bytes += bytes
                out[id] = e
            }
        }
        return out.values.sorted { $0.bytes > $1.bytes }
    }

    func toggleKeepOpen(_ id: String) {
        if lockedKeepOpen.contains(id) { lockedKeepOpen.remove(id) } else { lockedKeepOpen.insert(id) }
    }

    /// Closes the programs that hold chosen caches (each may ask to save first), then cleans.
    func quitLockedAppsAndClean() {
        let apps = lockedApps.filter { !lockedKeepOpen.contains($0.id) }.map(\.app)
        guard !apps.isEmpty else { proceedClean(); return }
        quittingForClean = true
        for app in apps { _ = app.terminate() }
        Task {
            for _ in 0..<20 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if apps.allSatisfy(\.isTerminated) { break }
            }
            // Give the programs a moment to let go of their cache files.
            try? await Task.sleep(nanoseconds: 700_000_000)
            quittingForClean = false
            refreshLocks()
            let still = apps.filter { !$0.isTerminated }.compactMap(\.localizedName)
            if !still.isEmpty {
                quitMessage = L("{0} kapanmadı; onun önbelleği bu sefer atlandı.", still.joined(separator: ", "))
            }
            proceedClean()
        }
    }

    /// Cleans everything selected except the confirm-only items (keeps the Trash as it is).
    func cleanSkippingConfirmItems() {
        clean(excluding: Set(confirmItems.map(\.id)))
    }

    // MARK: cleaning

    func clean(excluding: Set<UUID> = []) {
        let targets = selectedItems.filter { !excluding.contains($0.id) }
        guard !targets.isEmpty else { return }
        phase = .cleaning
        cleaningProgress = 0
        let started = Date()
        flying = groups.filter { $0.selectedSize > 0 }.prefix(6).map {
            FlyingItem(id: $0.id, iconKey: $0.iconKey, title: $0.title, isUserFile: $0.section.isUserData)
        }
        cleanFinishedAt = nil
        cleanStartDirt = dirtLevel(selectedBytes)
        cleanAnimationStart = started
        let cleaner = Cleaner(rules: allRules, running: WorkspaceRunningApps())
        let home = FileManager.default.homeDirectoryForCurrentUser
        Task {
            let record = await Task.detached(priority: .userInitiated) { () -> CleanRecord in
                cleaner.clean(targets, measureAt: home) { done, total in
                    let fraction = Double(done) / Double(max(total, 1))
                    Task { @MainActor [weak self] in self?.cleaningProgress = fraction }
                }
            }.value
            // Let the falling animation play at least once, even when cleaning is instant.
            let elapsed = Date().timeIntervalSince(started)
            if elapsed < 2.4 { try? await Task.sleep(nanoseconds: UInt64((2.4 - elapsed) * 1_000_000_000)) }
            let removedIDs = Set(record.items.filter { $0.status == .deleted || $0.status == .trashed }.map(\.id))
            items.removeAll { removedIDs.contains($0.id) }
            lastRecord = record
            history.insert(record, at: 0)
            store.update { $0.records.insert(record, at: 0) }
            cleaningProgress = 1
            phase = .done
            cleanFinishedAt = Date()
            if cleanSound { CleanSound.play() }
            klog("temizlik bitti · \(KBytes.format(record.bytesDeleted)) silindi · \(KBytes.format(record.bytesInTrash)) çöp kutusunda")
        }
    }

    func dismissCleanOverlay() {
        cleanAnimationStart = nil
        cleanFinishedAt = nil
    }

    // MARK: closing running apps

    /// Apps that must never be closed from here, whatever a rule says.
    private static let neverQuit: Set<String> = [
        "com.apple.finder", "com.apple.dock", "com.apple.loginwindow", "com.apple.systemuiserver",
        "com.apple.controlcenter", "com.apple.WindowManager", "com.apple.Spotlight"
    ]

    /// Running apps that keep this group locked.
    func blockingApps(for group: CacheGroup) -> [NSRunningApplication] {
        let me = Bundle.main.bundleIdentifier
        var ids = Set<String>()
        for part in group.parts where part.locked {
            guard let r = rule(part.ruleID) else { continue }
            for item in part.items { if let b = item.appBundleID { ids.insert(b) } }
            if let prefixes = r.blockIfRunning {
                for app in NSWorkspace.shared.runningApplications {
                    if let b = app.bundleIdentifier, prefixes.contains(where: { b.hasPrefix($0) }) { ids.insert(b) }
                }
            }
        }
        return NSWorkspace.shared.runningApplications.filter { app in
            guard let b = app.bundleIdentifier else { return false }
            return ids.contains(b) && b != me && !Self.neverQuit.contains(b) && !app.isTerminated
        }
    }

    func blockingAppNames(for group: CacheGroup) -> String {
        let names = Array(Set(blockingApps(for: group).compactMap(\.localizedName))).sorted()
        return names.isEmpty ? group.title : names.joined(separator: ", ")
    }

    /// Asks the apps to quit (they may ask to save first). With `force`, ends them at once.
    func quitApps(for group: CacheGroup, force: Bool) {
        let apps = blockingApps(for: group)
        guard !apps.isEmpty else { refreshLocks(); return }
        quitting.insert(group.id)
        quitStuck.remove(group.id)
        quitMessage = nil
        for app in apps { _ = force ? app.forceTerminate() : app.terminate() }
        Task {
            // Wait up to 8 seconds for them to close.
            for _ in 0..<16 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if apps.allSatisfy(\.isTerminated) { break }
            }
            // Give the app a moment to release its cache files.
            try? await Task.sleep(nanoseconds: 700_000_000)
            quitting.remove(group.id)
            refreshLocks()
            if apps.allSatisfy(\.isTerminated) {
                quitMessage = L("{0} kapatıldı; önbelleği artık temizlenebilir.", group.title)
            } else {
                quitStuck.insert(group.id)
                quitMessage = L("{0} kapanmadı. Kaydedilmemiş bir iş soruyor olabilir; ya ona bak ya da Zorla kapat.", group.title)
            }
        }
    }

    /// Closes every app that locks something, politely.
    func quitAllLockedApps() {
        for g in groups where g.parts.contains(where: \.locked) { quitApps(for: g, force: false) }
    }

    /// Re-checks which items are locked by a running app.
    func refreshLocks() {
        let running = WorkspaceRunningApps().runningBundleIDs()
        for i in items.indices {
            guard let r = rule(items[i].ruleID) else { continue }
            items[i].locked = r.isBlocked(appBundleID: items[i].appBundleID, running: running)
        }
    }

    // MARK: System Data (Time Machine local snapshots, unfinished macOS updates)

    func refreshSystemData() {
        Task {
            let result = await Task.detached { (SystemData.localSnapshots().count, SystemData.installDataExists()) }.value
            snapshotCount = result.0
            installDataPresent = result.1
        }
    }

    /// Shows macOS's administrator password dialog, then removes the items and measures the gain.
    func purgeSystemData() {
        guard !systemPurging else { return }
        systemPurging = true
        systemPurgeMessage = nil
        let home = FileManager.default.homeDirectoryForCurrentUser
        let snapshots = (snapshotCount ?? 0) > 0
        let installData = installDataPresent
        Task {
            let before = Volume.freeBytes(at: home)
            let outcome = await Task.detached { SystemData.purge(snapshots: snapshots, installData: installData) }.value
            if outcome.ok {
                // Snapshot deletion finishes in the background; give the volume a few seconds.
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                let after = Volume.freeBytes(at: home)
                if let b = before, let a = after, a > b {
                    systemPurgeMessage = L("Sistem Verisi'nden {0} yer açıldı.", KBytes.format(a - b))
                } else {
                    systemPurgeMessage = L("Silindi. macOS boş alanı birkaç dakika içinde güncelleyebilir.")
                }
                if cleanSound { CleanSound.play() }
            } else {
                systemPurgeMessage = outcome.message ?? L("İşlem yapılmadı.")
            }
            systemPurging = false
            refreshSystemData()
        }
    }

    func undo(_ record: CleanRecord) {
        let cleaner = Cleaner(rules: allRules)
        Task {
            let updated = await Task.detached { cleaner.undo(record) }.value
            if let i = history.firstIndex(where: { $0.id == record.id }) { history[i] = updated }
            if lastRecord?.id == record.id { lastRecord = updated }
            store.update { snap in
                if let i = snap.records.firstIndex(where: { $0.id == record.id }) { snap.records[i] = updated }
            }
        }
    }

    var lastCleanDate: Date? { history.first?.date }

    func toggleRecord(_ id: UUID) {
        if openRecords.contains(id) { openRecords.remove(id) } else { openRecords.insert(id) }
    }
}
