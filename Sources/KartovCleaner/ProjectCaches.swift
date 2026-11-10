import Foundation
import AppKit
import KartovCore

/// One row under a project: every cache of one kind.
struct ProjectPart: Identifiable, Hashable {
    let project: ProjectInfo
    let kind: ProjectCacheKind
    var id: String { ProjectCaches.key(project, kind) }
    var items: [ProjectCacheItem] { project.items.filter { $0.kind == kind } }
    var bytes: Int64 { project.bytes(of: kind) }
}

/// "Projeler": project folders on the Mac with the caches editing programs left in them.
/// Screen state lives here (@State needs full Xcode on the macOS 27 SDK).
@MainActor
final class ProjectCaches: ObservableObject {
    static let shared = ProjectCaches()

    static let idleChoices = [30, 60, 90, 180]

    @Published private(set) var projects: [ProjectInfo] = []
    @Published private(set) var scanning = false
    @Published private(set) var scanPath = ""
    @Published private(set) var scanDate: Date?
    @Published private(set) var cleaning = false
    /// Selection keys: project folder + kind.
    @Published var selected: Set<String> = []
    @Published var expanded: Set<String> = []
    @Published var onlyIdle = false
    @Published var showConfirm = false
    @Published var message: String?
    /// A project counts as untouched after this many days without a save.
    @Published var idleDays: Int { didSet { defaults.set(idleDays, forKey: "projectsIdleDays"); storeSummary() } }
    /// Folders the user added (an external disk, a work folder outside the usual places).
    @Published private(set) var extraRoots: [String] { didSet { defaults.set(extraRoots, forKey: "projectsExtraRoots") } }

    private let defaults = UserDefaults.standard
    private var task: Task<Void, Never>?

    private init() {
        let d = UserDefaults.standard
        idleDays = d.object(forKey: "projectsIdleDays") as? Int ?? 60
        extraRoots = d.stringArray(forKey: "projectsExtraRoots") ?? []
    }

    nonisolated static func key(_ p: ProjectInfo, _ k: ProjectCacheKind) -> String { p.id + "|" + k.rawValue }

    // MARK: where to look

    var roots: [URL] {
        ProjectScanner.defaultRoots() + extraRoots.map { URL(fileURLWithPath: $0) }
    }

    func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = L("Ekle")
        panel.message = L("Projelerinin durduğu klasörü ya da harici diski seç.")
        guard panel.runModal() == .OK else { return }
        var added = false
        for url in panel.urls {
            let path = url.standardizedFileURL.path
            let covered = roots.contains { path == $0.path || path.hasPrefix($0.path + "/") }
            if !covered && path != "/" { extraRoots.append(path); added = true }
        }
        if added { scan() }
    }

    func removeRoot(_ path: String) {
        extraRoots.removeAll { $0 == path }
        projects.removeAll { $0.id == path || $0.id.hasPrefix(path + "/") }
        prune()
        storeSummary()
    }

    // MARK: scanning

    func scan() {
        task?.cancel()
        scanning = true
        scanPath = ""
        message = nil
        selected = []
        let roots = self.roots
        task = Task {
            let found = await Task.detached(priority: .userInitiated) { () -> [ProjectInfo] in
                var last = Date.distantPast
                return ProjectScanner().scan(roots: roots) { path in
                    guard Date().timeIntervalSince(last) > 0.1 else { return }
                    last = Date()
                    Task { @MainActor in ProjectCaches.shared.scanPath = path }
                }
            }.value
            guard !Task.isCancelled else { return }
            projects = found
            scanning = false
            scanDate = Date()
            storeSummary()
            klog("proje taraması bitti · \(found.count) proje")
        }
    }

    func cancel() {
        task?.cancel()
        scanning = false
    }

    // MARK: reading the list

    func isIdle(_ p: ProjectInfo) -> Bool { (p.idleDays() ?? 0) >= idleDays }

    var visible: [ProjectInfo] { onlyIdle ? projects.filter(isIdle) : projects }
    var totalBytes: Int64 { projects.reduce(0) { $0 + $1.bytes } }
    var idleProjects: [ProjectInfo] { projects.filter { isIdle($0) && $0.regenerableBytes > 0 } }
    var idleBytes: Int64 { idleProjects.reduce(0) { $0 + $1.regenerableBytes } }

    func parts(of p: ProjectInfo) -> [ProjectPart] { p.kinds.map { ProjectPart(project: p, kind: $0) } }

    // MARK: choosing

    func toggle(_ part: ProjectPart) {
        if selected.contains(part.id) { selected.remove(part.id) } else { selected.insert(part.id) }
        message = nil
    }

    /// Kinds chosen when the whole project row is ticked: only what rebuilds itself.
    private func safeKeys(_ p: ProjectInfo) -> [String] {
        p.kinds.filter { $0.regenerable }.map { Self.key(p, $0) }
    }

    enum Tick { case none, some, all }

    func tick(of p: ProjectInfo) -> Tick {
        let all = p.kinds.map { Self.key(p, $0) }
        let on = all.filter { selected.contains($0) }.count
        if on == 0 { return .none }
        return on == all.count ? .all : .some
    }

    /// Ticks the caches that rebuild themselves; a second click clears the project.
    func toggle(_ p: ProjectInfo) {
        let all = p.kinds.map { Self.key(p, $0) }
        if all.contains(where: { selected.contains($0) }) {
            for k in all { selected.remove(k) }
        } else {
            let safe = safeKeys(p)
            for k in (safe.isEmpty ? all : safe) { selected.insert(k) }
            if safe.count < all.count { expanded.insert(p.id) }
        }
        message = nil
    }

    func selectIdle() {
        for p in idleProjects { for k in safeKeys(p) { selected.insert(k) } }
        message = nil
    }

    func clearSelection() { selected = [] }

    func toggleExpanded(_ p: ProjectInfo) {
        if expanded.contains(p.id) { expanded.remove(p.id) } else { expanded.insert(p.id) }
    }

    var picks: [ProjectPick] {
        projects.flatMap { p in
            p.items.filter { selected.contains(Self.key(p, $0.kind)) }.map { ProjectPick(project: p.name, item: $0) }
        }
    }

    var selectedBytes: Int64 { picks.reduce(0) { $0 + $1.item.size } }
    var selectedProjectCount: Int { projects.filter { tick(of: $0) != .none }.count }

    /// Editing programs that are open right now (their open project's caches are in use).
    var openEditors: [String] {
        let ids = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        // Premiere Pro and Media Encoder carry their version in the bundle id.
        var out = ProjectApp.allCases.filter { app in ids.contains { $0.hasPrefix(app.bundleID) } }.map { $0.title }
        if ids.contains(where: { $0.hasPrefix("com.adobe.ame") }) { out.append("Media Encoder") }
        return out
    }

    // MARK: cleaning

    func trashSelection(model: AppModel) {
        let picked = picks
        guard !picked.isEmpty, !cleaning else { return }
        cleaning = true
        let remover = ProjectCacheRemover(roots: roots)
        Task {
            let record = await Task.detached { remover.trash(picked) }.value
            let moved = Set(record.items.filter { $0.status == .trashed }.map(\.originalPath))
            for i in projects.indices { projects[i].items.removeAll { moved.contains($0.url.path) } }
            projects.removeAll { $0.items.isEmpty }
            prune()
            cleaning = false
            model.addRecord(record)
            storeSummary()
            let failed = record.items.filter { $0.status != .trashed }.count
            message = L("{0} çöp kutusuna taşındı. Geri almak için Geçmiş › Geri al.", KBytes.format(record.bytesInTrash)) +
                (failed > 0 ? L(" {0} öğe taşınamadı.", failed) : "")
            if model.cleanSound && record.bytesInTrash > 0 { CleanSound.play() }
        }
    }

    /// Drops selection and open rows that no longer exist.
    private func prune() {
        let keys = Set(projects.flatMap { p in p.kinds.map { Self.key(p, $0) } })
        selected = selected.intersection(keys)
        expanded = expanded.intersection(Set(projects.map(\.id)))
    }

    // MARK: for the weekly summary

    /// Untouched projects found by the last scan, and what their rebuildable caches take.
    nonisolated static var storedSummary: (count: Int, bytes: Int64)? {
        let d = UserDefaults.standard
        guard let date = d.object(forKey: "projectsSummaryDate") as? Date,
              Date().timeIntervalSince(date) < 30 * 86_400 else { return nil }
        return (d.integer(forKey: "projectsIdleCount"), (d.object(forKey: "projectsIdleBytes") as? NSNumber)?.int64Value ?? 0)
    }

    private func storeSummary() {
        guard scanDate != nil else { return }
        defaults.set(idleProjects.count, forKey: "projectsIdleCount")
        defaults.set(NSNumber(value: idleBytes), forKey: "projectsIdleBytes")
        defaults.set(scanDate, forKey: "projectsSummaryDate")
    }
}
