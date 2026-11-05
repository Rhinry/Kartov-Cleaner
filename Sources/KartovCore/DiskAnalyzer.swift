import Foundation

/// "Tam tarama": everything that takes space on the Mac, by size, so the user can sort it and
/// remove what they no longer want. Nothing here is ever chosen for the user, and everything
/// removed goes to the Trash (undoable from History).
public enum DiskKind: String, Codable, Sendable, CaseIterable {
    case app, video, image, audio, document, archive, other

    public var title: String {
        switch self {
        case .app: return L("Programlar")
        case .video: return L("Videolar")
        case .image: return L("Görseller")
        case .audio: return L("Müzik ve ses")
        case .document: return L("Belgeler")
        case .archive: return L("Arşiv ve kurulum dosyaları")
        case .other: return L("Diğer")
        }
    }

    static func of(_ url: URL) -> DiskKind {
        let ext = url.pathExtension.lowercased()
        if ext == "app" { return .app }
        if ["mov", "mp4", "m4v", "avi", "mkv", "mxf", "mts", "m2ts", "webm", "wmv", "3gp", "braw", "r3d", "hevc", "flv", "mpg", "mpeg"].contains(ext) { return .video }
        if ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "dng", "raw", "cr2", "cr3", "nef", "arw", "raf", "orf", "rw2",
            "psd", "psb", "gif", "webp", "exr", "bmp", "svg", "ai", "eps"].contains(ext) { return .image }
        if ["mp3", "wav", "aif", "aiff", "m4a", "flac", "aac", "ogg", "caf", "alac", "opus"].contains(ext) { return .audio }
        if ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "key", "pages", "numbers", "txt", "rtf", "md", "csv",
            "aep", "prproj", "drp", "indd", "sketch", "fig", "blend", "c4d", "psdx"].contains(ext) { return .document }
        if ["zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz", "dmg", "pkg", "iso", "xip", "mpkg", "zxp"].contains(ext) { return .archive }
        return .other
    }
}

public struct DiskEntry: Identifiable, Sendable, Hashable, Codable {
    public var id: String { url.path }
    public let url: URL
    public let name: String
    public let kind: DiskKind
    public let size: Int64
    public let modified: Date?
    /// Apps only: when it was last opened, if macOS knows.
    public let lastUsed: Date?
    /// Apps only.
    public let bundleID: String?
    /// Shown for information but cannot be removed from here (system apps, libraries kept by macOS).
    public let protected: Bool

    public init(url: URL, name: String, kind: DiskKind, size: Int64, modified: Date?,
                lastUsed: Date?, bundleID: String?, protected: Bool) {
        self.url = url; self.name = name; self.kind = kind; self.size = size; self.modified = modified
        self.lastUsed = lastUsed; self.bundleID = bundleID; self.protected = protected
    }
}

public struct FolderUsage: Sendable, Hashable, Identifiable {
    public var id: String { name }
    public let name: String
    public let bytes: Int64
}

public final class DiskAnalyzer: @unchecked Sendable {
    public let paths: Paths
    /// Files smaller than this are counted but not listed one by one.
    public let minimumListedBytes: Int64

    public init(paths: Paths = Paths(), minimumListedBytes: Int64 = 1_000_000) {
        self.paths = paths
        self.minimumListedBytes = minimumListedBytes
    }

    /// Folders under the home folder that are walked file by file.
    public var userFolders: [(String, URL)] {
        [(L("Masaüstü"), "Desktop"), (L("Belgeler"), "Documents"), (L("İndirilenler"), "Downloads"), (L("Filmler"), "Movies"),
         (L("Müzik"), "Music"), (L("Resimler"), "Pictures"), (L("Genel"), "Public")]
            .map { ($0.0, paths.home.appendingPathComponent($0.1)) }
    }

    public var appFolders: [URL] {
        [URL(fileURLWithPath: "/Applications"), paths.home.appendingPathComponent("Applications")]
    }

    public struct Result: Sendable {
        public var entries: [DiskEntry] = []
        public var folders: [FolderUsage] = []
        public var filesSeen = 0
    }

    public func run(progress: (String, Int) -> Void) -> Result {
        var result = Result()
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .isPackageKey, .isDirectoryKey,
                                      .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey,
                                      .contentModificationDateKey, .contentAccessDateKey]

        // Apps: each .app is one entry with its full size.
        var seenApps = Set<String>()
        for folder in appFolders {
            guard let names = try? fm.contentsOfDirectory(atPath: folder.path) else { continue }
            for name in names.sorted() {
                if Task.isCancelled { return result }
                let url = folder.appendingPathComponent(name)
                if Paths.isSymlink(url.path, fm) { continue }
                var candidates: [URL] = []
                if name.hasSuffix(".app") { candidates = [url] }
                else if !name.hasPrefix("."), let inner = try? fm.contentsOfDirectory(atPath: url.path) {
                    // One level of subfolders, e.g. /Applications/Utilities or a vendor folder.
                    candidates = inner.filter { $0.hasSuffix(".app") }.map { url.appendingPathComponent($0) }
                }
                for app in candidates where !seenApps.contains(app.path) && !Paths.isSymlink(app.path, fm) {
                    seenApps.insert(app.path)
                    progress(app.path, result.filesSeen)
                    let m = SizeCalculator.measure(app, fileManager: fm)
                    let bundle = Bundle(url: app)
                    let id = bundle?.bundleIdentifier
                    let v = try? app.resourceValues(forKeys: [.contentAccessDateKey, .contentModificationDateKey])
                    result.entries.append(DiskEntry(
                        url: app, name: String(app.deletingPathExtension().lastPathComponent), kind: .app,
                        size: m.bytes, modified: v?.contentModificationDate, lastUsed: v?.contentAccessDate,
                        bundleID: id, protected: DiskRemover.isProtectedApp(bundleID: id, url: app)))
                }
            }
        }

        // The user's folders: every file of at least `minimumListedBytes`.
        for (label, root) in userFolders {
            if Task.isCancelled { return result }
            var folderBytes: Int64 = 0
            guard fm.fileExists(atPath: root.path), !Paths.isSymlink(root.path, fm),
                  let e = fm.enumerator(at: root, includingPropertiesForKeys: keys,
                                        options: [.skipsHiddenFiles], errorHandler: { _, _ in true }) else { continue }
            for case let file as URL in e {
                if Task.isCancelled { return result }
                guard let v = try? file.resourceValues(forKeys: Set(keys)) else { continue }
                if v.isSymbolicLink == true { continue }
                let lower = file.lastPathComponent.lowercased()
                let isPackage = v.isPackage == true || SafetyPolicy.packageExtensions.contains { lower.hasSuffix($0) }
                if isPackage {
                    // Photo libraries, Final Cut libraries, projects saved as packages: one entry, whole size.
                    e.skipDescendants()
                    let m = SizeCalculator.measure(file, fileManager: fm)
                    folderBytes += m.bytes
                    result.filesSeen += m.files
                    if m.bytes >= minimumListedBytes {
                        let libraries = [".photoslibrary", ".photolibrary", ".musiclibrary", ".tvlibrary"]
                        result.entries.append(DiskEntry(
                            url: file, name: file.lastPathComponent, kind: DiskKind.of(file) == .app ? .app : packageKind(lower),
                            size: m.bytes, modified: v.contentModificationDate, lastUsed: nil, bundleID: nil,
                            protected: libraries.contains { lower.hasSuffix($0) }))
                    }
                    continue
                }
                guard v.isRegularFile == true else { continue }
                let bytes = Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? v.fileSize ?? 0)
                folderBytes += bytes
                result.filesSeen += 1
                if result.filesSeen % 400 == 0 { progress(file.deletingLastPathComponent().path, result.filesSeen) }
                guard bytes >= minimumListedBytes else { continue }
                result.entries.append(DiskEntry(
                    url: file, name: file.lastPathComponent, kind: DiskKind.of(file), size: bytes,
                    modified: v.contentModificationDate, lastUsed: nil, bundleID: nil, protected: false))
            }
            result.folders.append(FolderUsage(name: label, bytes: folderBytes))
        }
        result.folders.append(FolderUsage(name: L("Programlar"),
                                          bytes: result.entries.filter { $0.kind == .app }.reduce(0) { $0 + $1.size }))
        result.entries.sort { $0.size > $1.size }
        return result
    }

    private func packageKind(_ lowerName: String) -> DiskKind {
        if [".photoslibrary", ".photolibrary"].contains(where: { lowerName.hasSuffix($0) }) { return .image }
        if [".fcpbundle", ".imovielibrary", ".tvlibrary"].contains(where: { lowerName.hasSuffix($0) }) { return .video }
        if [".musiclibrary", ".logicx", ".band"].contains(where: { lowerName.hasSuffix($0) }) { return .audio }
        return .document
    }
}

/// Moves what the user picked in the full scan to the Trash, with the app's leftovers.
public struct DiskRemover: Sendable {
    public let paths: Paths
    public let remover: FileRemoving

    public init(paths: Paths = Paths(), remover: FileRemoving = SystemFileRemover()) {
        self.paths = paths
        self.remover = remover
    }

    /// Apple's own apps that come with macOS, and this app itself.
    public static func isProtectedApp(bundleID: String?, url: URL) -> Bool {
        if url.path.hasPrefix("/System/") { return true }
        guard let id = bundleID else { return false }
        if id.hasPrefix("com.kartov.") { return true }
        let essential = ["com.apple.Safari", "com.apple.finder", "com.apple.systempreferences", "com.apple.AppStore",
                         "com.apple.Terminal", "com.apple.ActivityMonitor", "com.apple.DiskUtility"]
        return essential.contains(id)
    }

    /// Whether this path may be moved to the Trash from the full scan.
    public func canRemove(_ url: URL, fileManager fm: FileManager = .default) -> Bool {
        let p = url.standardizedFileURL.path
        let h = paths.home.path
        if Paths.isSymlink(p, fm) { return false }
        guard fm.fileExists(atPath: p) else { return false }
        let appRoots = ["/Applications/", h + "/Applications/"]
        if p.hasSuffix(".app") && appRoots.contains(where: { p.hasPrefix($0) }) { return true }
        let allowed = ["Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures", "Public"].map { h + "/" + $0 + "/" }
        guard allowed.contains(where: { p.hasPrefix($0) }) else { return false }
        let lower = p.lowercased()
        if [".photoslibrary", ".photolibrary", ".musiclibrary", ".tvlibrary"].contains(where: { lower.hasSuffix($0) }) { return false }
        return true
    }

    /// Settings, caches and data an app leaves in the Library. Only exact bundle-id names are matched.
    public func leftovers(for bundleID: String, appName: String, fileManager fm: FileManager = .default) -> [URL] {
        let lib = paths.home.appendingPathComponent("Library")
        let candidates: [String] = [
            "Caches/\(bundleID)", "Application Support/\(bundleID)", "Preferences/\(bundleID).plist",
            "Saved Application State/\(bundleID).savedState", "Containers/\(bundleID)", "HTTPStorages/\(bundleID)",
            "HTTPStorages/\(bundleID).binarycookies", "WebKit/\(bundleID)", "Logs/\(bundleID)", "Logs/\(appName)",
            "Application Support/\(appName)", "Caches/\(appName)"
        ]
        guard !bundleID.hasPrefix("com.apple."), bundleID.count > 3 else { return [] }
        return candidates.map { lib.appendingPathComponent($0) }
            .filter { fm.fileExists(atPath: $0.path) && !Paths.isSymlink($0.path, fm) }
    }

    /// Moves the entries (and the leftovers of the apps among them) to the Trash.
    public func trash(_ entries: [DiskEntry], includeLeftovers: Bool = true, date: Date = Date()) -> CleanRecord {
        var items: [CleanItemRecord] = []
        var trashed: Int64 = 0
        for e in entries {
            var targets: [(URL, Int64)] = [(e.url, e.size)]
            if includeLeftovers, e.kind == .app, let id = e.bundleID {
                targets += leftovers(for: id, appName: e.name).map { ($0, SizeCalculator.measure($0).bytes) }
            }
            for (url, size) in targets {
                var rec = CleanItemRecord(id: UUID(), ruleID: "fullscan", appKey: e.name, originalPath: url.path,
                                          trashedPath: nil, size: size, status: .skipped, reason: nil)
                let isLeftover = url != e.url
                if e.protected || (!isLeftover && !canRemove(url)) {
                    rec.reason = L("Bu öğe buradan kaldırılamaz")
                } else {
                    do {
                        rec.trashedPath = try remover.trash(url)?.path
                        rec.status = .trashed
                        trashed += size
                    } catch {
                        rec.status = .failed
                        rec.reason = L("macOS izin vermedi; Finder'dan çöpe atabilirsin")
                    }
                }
                items.append(rec)
            }
        }
        return CleanRecord(id: UUID(), date: date, items: items, bytesCleaned: trashed, bytesDeleted: 0,
                           bytesInTrash: trashed, measuredFreed: nil, undoneAt: nil, automatic: nil)
    }
}
