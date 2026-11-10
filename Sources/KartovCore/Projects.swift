import Foundation

/// "Projeler": what editing programs leave next to a project file — preview renders, media
/// caches, auto-save copies, proxies — grouped by project, with the date the project was last
/// touched. Nothing here is ever chosen for the user, and everything removed goes to the Trash
/// (undoable from History). The project file itself, its media and its renders are never offered.
public enum ProjectApp: String, Codable, Sendable, CaseIterable {
    case afterEffects, premiere

    public var title: String {
        switch self {
        case .afterEffects: return "After Effects"
        case .premiere: return "Premiere Pro"
        }
    }

    public var bundleID: String {
        switch self {
        case .afterEffects: return "com.adobe.AfterEffects"
        case .premiere: return "com.adobe.PremierePro"
        }
    }

    /// The program a project file belongs to, by its name.
    public static func of(fileName: String) -> ProjectApp? {
        let l = fileName.lowercased()
        if l.hasSuffix(".aep") || l.hasSuffix(".aepx") { return .afterEffects }
        if l.hasSuffix(".prproj") { return .premiere }
        return nil
    }
}

public enum ProjectCacheKind: String, Codable, Sendable, CaseIterable {
    case previews, mediaCache, renderTemp, autoSave, proxies

    public var title: String {
        switch self {
        case .previews: return L("Önizleme renderları")
        case .mediaCache: return L("Medya önbelleği")
        case .renderTemp: return L("Media Encoder artıkları")
        case .autoSave: return L("Otomatik kayıt yedekleri")
        case .proxies: return L("Proxy dosyaları")
        }
    }

    public var detail: String {
        switch self {
        case .previews: return L("Zaman çizelgesinde render edilen önizlemeler. Proje açılınca yeniden render edilebilir.")
        case .mediaCache: return L("Ses dalga formları ve hızlı kopyalar (.pek, .cfa). Medya açılınca yeniden oluşturulur.")
        case .renderTemp: return L("Media Encoder'a gönderirken geride kalan geçici proje kopyaları.")
        case .autoSave: return L("Projenin eski otomatik kayıtları. Proje dosyasının kendisi değildir; bitmiş projelerde silmek daha güvenlidir.")
        case .proxies: return L("Düşük çözünürlüklü çalışma kopyaları. Yeniden üretilebilir ama uzun sürer.")
        }
    }

    /// Rebuilt by the program on its own; the only cost is a little time.
    public var regenerable: Bool {
        switch self {
        case .previews, .mediaCache, .renderTemp: return true
        case .autoSave, .proxies: return false
        }
    }
}

/// One cache folder or file that belongs to a project.
public struct ProjectCacheItem: Identifiable, Sendable, Hashable {
    public var id: String { url.path }
    public let url: URL
    public let kind: ProjectCacheKind
    public let size: Int64

    public init(url: URL, kind: ProjectCacheKind, size: Int64) {
        self.url = url; self.kind = kind; self.size = size
    }
}

/// A folder that holds at least one project file, with the caches found in it.
public struct ProjectInfo: Identifiable, Sendable, Hashable {
    public var id: String { folder.path }
    public let folder: URL
    public let name: String
    public let apps: [ProjectApp]
    /// Names of the project files in the folder.
    public let projectFiles: [String]
    /// When a project file in the folder was last saved.
    public let lastModified: Date?
    public var items: [ProjectCacheItem]

    public init(folder: URL, name: String, apps: [ProjectApp], projectFiles: [String],
                lastModified: Date?, items: [ProjectCacheItem]) {
        self.folder = folder; self.name = name; self.apps = apps; self.projectFiles = projectFiles
        self.lastModified = lastModified; self.items = items
    }

    public var bytes: Int64 { items.reduce(0) { $0 + $1.size } }
    public func bytes(of kind: ProjectCacheKind) -> Int64 { items.filter { $0.kind == kind }.reduce(0) { $0 + $1.size } }
    public var regenerableBytes: Int64 { items.filter { $0.kind.regenerable }.reduce(0) { $0 + $1.size } }
    /// The kinds present, in a fixed order.
    public var kinds: [ProjectCacheKind] { ProjectCacheKind.allCases.filter { k in items.contains { $0.kind == k } } }

    /// Whole days since the project was last saved.
    public func idleDays(now: Date = Date()) -> Int? {
        guard let d = lastModified else { return nil }
        return max(0, Int(now.timeIntervalSince(d) / 86_400))
    }
}

public struct ProjectScanner: Sendable {
    public let maxDepth: Int

    public init(maxDepth: Int = 12) { self.maxDepth = maxDepth }

    /// Where projects usually live. More folders (an external disk) can be added by the user.
    public static func defaultRoots(paths: Paths = Paths()) -> [URL] {
        ["Desktop", "Documents", "Downloads", "Movies"].map { paths.home.appendingPathComponent($0) }
    }

    /// A cache folder, by its exact name.
    public static func kind(ofFolder name: String) -> ProjectCacheKind? {
        switch name.lowercased() {
        case "adobe premiere pro video previews", "adobe premiere pro audio previews": return .previews
        case "adobe premiere pro auto-save", "adobe after effects auto-save": return .autoSave
        case "media cache", "media cache files", "peak files": return .mediaCache
        case "proxies": return .proxies
        default: return nil
        }
    }

    /// A cache file, by its name.
    public static func kind(ofFile name: String) -> ProjectCacheKind? {
        let l = name.lowercased()
        if l.hasPrefix("tmpaetoameproject") && l.hasSuffix(".aep") { return .renderTemp }
        if l.hasSuffix(".pek") || l.hasSuffix(".cfa") { return .mediaCache }
        return nil
    }

    /// For a project file lying loose in Desktop, Documents… only folders and files that carry
    /// the program's own name are counted: a "Proxies" folder there could be anyone's.
    static let looseKinds: Set<ProjectCacheKind> = [.previews, .autoSave, .renderTemp]

    static let skippedFolders: Set<String> = ["node_modules", "library", "applications"]

    private final class Builder {
        let folder: URL
        /// The project file sits directly in one of the scanned roots.
        let loose: Bool
        var apps = Set<ProjectApp>()
        var files: [String] = []
        var lastModified: Date?
        var items: [ProjectCacheItem] = []
        init(folder: URL, loose: Bool) { self.folder = folder; self.loose = loose }
    }

    /// Walks the roots and returns every project that has something to offer, largest first.
    public func scan(roots: [URL], fileManager fm: FileManager = .default,
                     progress: (String) -> Void = { _ in }) -> [ProjectInfo] {
        var builders: [Builder] = []
        var seen = Set<String>()
        for root in roots {
            let std = root.standardizedFileURL
            guard !seen.contains(std.path), fm.fileExists(atPath: std.path), !Paths.isSymlink(std.path, fm) else { continue }
            seen.insert(std.path)
            walk(std, depth: 0, owner: nil, isRoot: true, into: &builders, fm: fm, progress: progress)
        }
        return builders.filter { !$0.items.isEmpty }.map { b in
            ProjectInfo(folder: b.folder, name: b.folder.lastPathComponent,
                        apps: ProjectApp.allCases.filter { b.apps.contains($0) },
                        projectFiles: b.files.sorted(), lastModified: b.lastModified,
                        items: b.items.sorted { $0.size > $1.size })
        }
        .sorted { $0.bytes > $1.bytes }
    }

    private func walk(_ dir: URL, depth: Int, owner: Builder?, isRoot: Bool, into out: inout [Builder],
                      fm: FileManager, progress: (String) -> Void) {
        if Task.isCancelled { return }
        guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return }
        progress(dir.path)

        // A folder with a project file in it starts a new project; everything below belongs to it.
        var here: Builder?
        let projectNames = names.filter { !$0.hasPrefix(".") && ProjectApp.of(fileName: $0) != nil && Self.kind(ofFile: $0) == nil }
        if !projectNames.isEmpty {
            let b = Builder(folder: dir, loose: isRoot)
            for n in projectNames {
                let path = dir.appendingPathComponent(n).path
                guard let attrs = try? fm.attributesOfItem(atPath: path),
                      (attrs[.type] as? FileAttributeType) == .typeRegular else { continue }
                b.files.append(n)
                if let app = ProjectApp.of(fileName: n) { b.apps.insert(app) }
                if let d = attrs[.modificationDate] as? Date, d > (b.lastModified ?? .distantPast) { b.lastModified = d }
            }
            if !b.files.isEmpty { out.append(b); here = b }
        }
        let current = here ?? owner

        for name in names.sorted() where !name.hasPrefix(".") {
            if Task.isCancelled { return }
            let url = dir.appendingPathComponent(name)
            guard let attrs = try? fm.attributesOfItem(atPath: url.path),
                  let type = attrs[.type] as? FileAttributeType else { continue }
            if type == .typeDirectory {
                let lower = name.lowercased()
                if let kind = Self.kind(ofFolder: name) {
                    // A cache folder is measured as a whole and never walked into.
                    if let c = current, accepts(kind, project: c, directChild: here != nil) {
                        let m = SizeCalculator.measure(url, fileManager: fm)
                        if m.bytes > 0 { c.items.append(ProjectCacheItem(url: url, kind: kind, size: m.bytes)) }
                    }
                    continue
                }
                if SafetyPolicy.packageExtensions.contains(where: { lower.hasSuffix($0) }) { continue }
                if Self.skippedFolders.contains(lower) && isRoot { continue }
                if depth < maxDepth {
                    walk(url, depth: depth + 1, owner: current, isRoot: false, into: &out, fm: fm, progress: progress)
                }
            } else if type == .typeRegular, let kind = Self.kind(ofFile: name), let c = current,
                      accepts(kind, project: c, directChild: here != nil) {
                let v = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey])
                let bytes = Int64(v?.totalFileAllocatedSize ?? v?.fileAllocatedSize ?? v?.fileSize ?? 0)
                if bytes > 0 { c.items.append(ProjectCacheItem(url: url, kind: kind, size: bytes)) }
            }
        }
    }

    private func accepts(_ kind: ProjectCacheKind, project: Builder, directChild: Bool) -> Bool {
        if project.loose { return directChild && Self.looseKinds.contains(kind) }
        return true
    }
}

/// One thing the user picked on the Projects screen.
public struct ProjectPick: Sendable, Hashable {
    public let project: String
    public let item: ProjectCacheItem
    public init(project: String, item: ProjectCacheItem) { self.project = project; self.item = item }
}

/// Moves picked project caches to the Trash. Every item is checked again right before it is
/// touched: it must still be a cache folder or file by name, must not be a symbolic link and
/// must sit inside one of the scanned folders.
public struct ProjectCacheRemover: Sendable {
    public let roots: [URL]
    public let remover: FileRemoving

    public init(roots: [URL], remover: FileRemoving = SystemFileRemover()) {
        self.roots = roots
        self.remover = remover
    }

    public func canRemove(_ item: ProjectCacheItem, fileManager fm: FileManager = .default) -> Bool {
        let std = item.url.standardizedFileURL
        let name = std.lastPathComponent
        guard let attrs = try? fm.attributesOfItem(atPath: std.path),
              let type = attrs[.type] as? FileAttributeType else { return false }
        switch type {
        case .typeDirectory: guard ProjectScanner.kind(ofFolder: name) == item.kind else { return false }
        case .typeRegular: guard ProjectScanner.kind(ofFile: name) == item.kind else { return false }
        default: return false   // symbolic links and everything else
        }
        // No symbolic link between a scanned folder and the item.
        let plain = std.deletingLastPathComponent().path
        let parent = std.deletingLastPathComponent().resolvingSymlinksInPath().path
        return roots.contains { root in
            let r = root.standardizedFileURL
            let inside = plain == r.path || plain.hasPrefix(r.path + "/")
            let resolved = r.resolvingSymlinksInPath().path
            return inside && (parent == resolved || parent.hasPrefix(resolved + "/"))
        }
    }

    public func trash(_ picks: [ProjectPick], date: Date = Date()) -> CleanRecord {
        var items: [CleanItemRecord] = []
        var trashed: Int64 = 0
        for p in picks {
            var rec = CleanItemRecord(id: UUID(), ruleID: "projects." + p.item.kind.rawValue, appKey: p.project,
                                      originalPath: p.item.url.path, trashedPath: nil, size: p.item.size,
                                      status: .skipped, reason: nil)
            if !canRemove(p.item) {
                rec.reason = FileManager.default.fileExists(atPath: p.item.url.path)
                    ? L("Güvenlik kontrolü geçmedi") : L("Artık yok")
            } else {
                do {
                    rec.trashedPath = try remover.trash(p.item.url)?.path
                    rec.status = .trashed
                    trashed += p.item.size
                } catch {
                    rec.status = .failed
                    rec.reason = L("macOS izin vermedi; Finder'dan çöpe atabilirsin")
                }
            }
            items.append(rec)
        }
        return CleanRecord(id: UUID(), date: date, items: items, bytesCleaned: trashed, bytesDeleted: 0,
                           bytesInTrash: trashed, measuredFreed: nil, undoneAt: nil, automatic: nil)
    }
}
