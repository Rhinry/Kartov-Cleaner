import Foundation

/// One thing that can be cleaned: a cache folder, a log folder, an installer.
public struct FoundItem: Identifiable, Sendable, Hashable, Codable {
    public let id: UUID
    public let ruleID: String
    public let url: URL
    /// Folder or file name as found on disk (often a bundle id for app caches).
    public let name: String
    /// Grouping key on screen: the bundle id, or the rule's app group, or the rule id.
    public let appKey: String
    public let size: Int64
    public let fileCount: Int
    public let newestModification: Date?
    /// Bundle id of the app the item belongs to, when known (checked again before cleaning).
    public let appBundleID: String?
    public var locked: Bool

    public init(id: UUID = UUID(), ruleID: String, url: URL, name: String, appKey: String,
                size: Int64, fileCount: Int, newestModification: Date?, appBundleID: String? = nil,
                locked: Bool) {
        self.id = id; self.ruleID = ruleID; self.url = url; self.name = name; self.appKey = appKey
        self.size = size; self.fileCount = fileCount; self.newestModification = newestModification
        self.appBundleID = appBundleID; self.locked = locked
    }

    /// Key used to remember "keep" choices across scans.
    public var selectionKey: String { ruleID + "|" + appKey }
}

public enum SkipReason: String, Sendable, Codable {
    case notFound
    case noPermission
    case needsAdmin
}

public enum ScanEvent: Sendable {
    case locationStarted(ruleID: String)
    case progress(ruleID: String, currentPath: String, filesSeen: Int)
    case found(FoundItem)
    case locationFinished(ruleID: String, bytes: Int64, items: Int)
    case locationSkipped(ruleID: String, reason: SkipReason)
    case finished(totalBytes: Int64)
}

public protocol RunningAppsProviding: Sendable {
    func runningBundleIDs() -> Set<String>
}

public struct NoRunningApps: RunningAppsProviding {
    public init() {}
    public func runningBundleIDs() -> Set<String> { [] }
}

public enum SizeCalculator {
    public struct Result: Sendable {
        public var bytes: Int64 = 0
        public var files: Int = 0
        public var newest: Date?
    }

    private static let keys: [URLResourceKey] = [
        .isRegularFileKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey,
        .fileAllocatedSizeKey, .fileSizeKey, .contentModificationDateKey
    ]

    private static func bytes(of values: URLResourceValues) -> Int64 {
        if let v = values.totalFileAllocatedSize { return Int64(v) }
        if let v = values.fileAllocatedSize { return Int64(v) }
        if let v = values.fileSize { return Int64(v) }
        return 0
    }

    /// Allocated size of a file or folder. Never follows symbolic links.
    public static func measure(_ url: URL,
                               fileManager fm: FileManager = .default,
                               progressEvery: Int = 400,
                               onProgress: ((String, Int) -> Void)? = nil) -> Result {
        var result = Result()
        let set = Set(keys)
        if let v = try? url.resourceValues(forKeys: set) {
            if v.isSymbolicLink == true { return result }
            if v.isRegularFile == true {
                result.bytes = bytes(of: v)
                result.files = 1
                result.newest = v.contentModificationDate
                return result
            }
        }
        guard let e = fm.enumerator(at: url, includingPropertiesForKeys: keys, options: [],
                                    errorHandler: { _, _ in true }) else { return result }
        for case let file as URL in e {
            if Task.isCancelled { break }
            guard let v = try? file.resourceValues(forKeys: set) else { continue }
            if v.isSymbolicLink == true { continue }
            if let d = v.contentModificationDate, d > (result.newest ?? .distantPast) { result.newest = d }
            guard v.isRegularFile == true else { continue }
            result.bytes += bytes(of: v)
            result.files += 1
            if let onProgress = onProgress, result.files % progressEvery == 0 {
                onProgress(file.deletingLastPathComponent().path, result.files)
            }
        }
        return result
    }
}

/// Walks every rule's roots and reports what it finds, location by location,
/// so the scan screen can show exactly which folders are being read.
public final class CacheScanner: @unchecked Sendable {
    public let rules: [CleanRule]
    public let paths: Paths
    public let policy: SafetyPolicy
    private let running: RunningAppsProviding
    private let now: Date

    public init(rules: [CleanRule], paths: Paths = Paths(),
                running: RunningAppsProviding = NoRunningApps(), now: Date = Date()) {
        self.rules = rules
        self.paths = paths
        self.policy = SafetyPolicy(paths: paths)
        self.running = running
        self.now = now
    }

    public func scan() -> AsyncStream<ScanEvent> {
        AsyncStream { continuation in
            let task = Task.detached(priority: .userInitiated) { [self] in
                self.run { continuation.yield($0) }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Synchronous scan, used by `scan()` and by tests.
    public func run(_ emit: @escaping (ScanEvent) -> Void) {
        let fm = FileManager.default
        let runningIDs = running.runningBundleIDs()
        var total: Int64 = 0
        /// Paths already reported, so overlapping rules never count (or delete) anything twice.
        var claimed: [String] = []
        func isClaimed(_ p: String) -> Bool {
            claimed.contains { p == $0 || p.hasPrefix($0 + "/") || $0.hasPrefix(p + "/") }
        }

        for rule in rules {
            if Task.isCancelled { break }
            emit(.locationStarted(ruleID: rule.id))
            if rule.safety == .admin {
                emit(.locationSkipped(ruleID: rule.id, reason: .needsAdmin))
                continue
            }

            struct Candidate { let url: URL; let capture: String?; let measured: SizeCalculator.Result? }
            var candidates: [Candidate] = []
            var anyRootExists = false
            var permissionDenied = false
            var filesSeen = 0

            for pattern in rule.roots {
                for match in paths.expandGlob(pattern, fileManager: fm) {
                    if Task.isCancelled { break }
                    if rule.appKeyFromGlob == true, let cap = match.capture, let ex = rule.exclude,
                       ex.contains(where: { Wildcard.matches(pattern: $0, cap) }) { continue }
                    anyRootExists = true
                    switch rule.itemLevel {
                    case .root:
                        candidates.append(Candidate(url: match.url, capture: match.capture, measured: nil))
                    case .children:
                        do {
                            let names = try fm.contentsOfDirectory(atPath: match.url.path)
                            for name in names.sorted() where rule.accepts(childName: name) {
                                candidates.append(Candidate(url: match.url.appendingPathComponent(name),
                                                            capture: match.capture, measured: nil))
                            }
                        } catch {
                            permissionDenied = true
                        }
                    case .largeFiles:
                        let found = largeFiles(under: match.url, rule: rule, fm: fm) { path, files in
                            emit(.progress(ruleID: rule.id, currentPath: path, filesSeen: filesSeen + files))
                        }
                        filesSeen += found.seen
                        if found.denied { permissionDenied = true }
                        candidates += found.files.map { Candidate(url: $0.0, capture: nil, measured: $0.1) }
                    }
                }
            }

            if !anyRootExists {
                emit(.locationSkipped(ruleID: rule.id, reason: .notFound))
                continue
            }
            if candidates.isEmpty && permissionDenied {
                emit(.locationSkipped(ruleID: rule.id, reason: .noPermission))
                continue
            }

            var ruleBytes: Int64 = 0
            var ruleItems = 0
            for c in candidates {
                if Task.isCancelled { break }
                let url = c.url
                if isClaimed(url.path) { continue }
                guard policy.check(url, rule: rule, fileManager: fm) == .ok else { continue }
                let m: SizeCalculator.Result
                if let pre = c.measured {
                    m = pre
                } else {
                    emit(.progress(ruleID: rule.id, currentPath: url.path, filesSeen: filesSeen))
                    let base = filesSeen
                    m = SizeCalculator.measure(url, fileManager: fm) { path, files in
                        emit(.progress(ruleID: rule.id, currentPath: path, filesSeen: base + files))
                    }
                    filesSeen += m.files
                }
                guard m.bytes > 0 else { continue }
                if let days = rule.minAgeDays, let newest = m.newest,
                   now.timeIntervalSince(newest) < Double(days) * 86_400 {
                    continue
                }
                let name = url.lastPathComponent
                let appKey: String
                var bundleID: String? = nil
                if rule.group.isUserData {
                    appKey = url.path
                } else if rule.childIsBundleID == true {
                    appKey = name; bundleID = name
                } else if rule.appKeyFromGlob == true, let cap = c.capture {
                    appKey = cap
                    if rule.appKeyIsBundleID == true { bundleID = cap }
                } else {
                    appKey = rule.appGroup ?? rule.id
                }
                let item = FoundItem(ruleID: rule.id, url: url, name: name, appKey: appKey,
                                     size: m.bytes, fileCount: m.files, newestModification: m.newest,
                                     appBundleID: bundleID,
                                     locked: rule.isBlocked(appBundleID: bundleID, running: runningIDs))
                claimed.append(url.path)
                ruleBytes += m.bytes
                ruleItems += 1
                emit(.found(item))
            }
            total += ruleBytes
            emit(.locationFinished(ruleID: rule.id, bytes: ruleBytes, items: ruleItems))
        }
        emit(.finished(totalBytes: total))
    }

    /// Regular files of at least `minSizeMB` under `root`, skipping hidden folders and packages.
    private func largeFiles(under root: URL, rule: CleanRule, fm: FileManager,
                            onProgress: (String, Int) -> Void) -> (files: [(URL, SizeCalculator.Result)], seen: Int, denied: Bool) {
        let minBytes = Int64(rule.minSizeMB ?? 500) * 1_000_000
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .isPackageKey,
                                      .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey,
                                      .contentModificationDateKey]
        var denied = false
        guard let e = fm.enumerator(at: root, includingPropertiesForKeys: keys,
                                    options: [.skipsHiddenFiles, .skipsPackageDescendants],
                                    errorHandler: { _, _ in denied = true; return true }) else {
            return ([], 0, true)
        }
        var out: [(URL, SizeCalculator.Result)] = []
        var seen = 0
        for case let file as URL in e {
            if Task.isCancelled { break }
            guard let v = try? file.resourceValues(forKeys: Set(keys)) else { continue }
            if v.isSymbolicLink == true { continue }
            if v.isPackage == true || SafetyPolicy.packageExtensions.contains(where: { file.lastPathComponent.lowercased().hasSuffix($0) }) {
                e.skipDescendants()
                continue
            }
            guard v.isRegularFile == true else { continue }
            if let include = rule.include, !include.isEmpty {
                let name = file.lastPathComponent.lowercased()
                if !include.contains(where: { Wildcard.matches(pattern: $0.lowercased(), name) }) { continue }
            }
            seen += 1
            if seen % 500 == 0 { onProgress(file.deletingLastPathComponent().path, seen) }
            let bytes = Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? v.fileSize ?? 0)
            guard bytes >= minBytes else { continue }
            out.append((file, SizeCalculator.Result(bytes: bytes, files: 1, newest: v.contentModificationDate)))
        }
        return (out, seen, denied)
    }
}
