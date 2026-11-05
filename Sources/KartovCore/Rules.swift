import Foundation

/// Which part of the app a rule belongs to. Used for grouping on screen.
public enum CategoryGroup: String, Codable, Sendable, CaseIterable {
    case apps, creative, browsers, developer, logs, updates, trash, privacy, userFiles

    public var title: String {
        switch self {
        case .apps: return L("Uygulama önbellekleri")
        case .creative: return L("Video ve tasarım programları")
        case .browsers: return L("İnternet tarayıcıları")
        case .developer: return L("Yazılım araçları")
        case .logs: return L("Kayıt dosyaları")
        case .updates: return L("Eski kurulum dosyaları")
        case .trash: return L("Çöp kutusu")
        case .privacy: return L("Tarama geçmişi")
        case .userFiles: return L("Büyük dosyalar")
        }
    }

    /// Groups whose items are the user's own data: shown, never chosen for them.
    public var isUserData: Bool { self == .userFiles }
}

public enum Safety: String, Codable, Sendable {
    /// Regenerated automatically; selected by default.
    case safe
    /// The user's data or large one-off files; goes to the Trash (or needs confirmation).
    case caution
    /// Needs administrator rights.
    case admin
}

public enum CleanMode: String, Codable, Sendable {
    /// Removed immediately. Space is freed right away.
    case delete
    /// Moved to the Trash. Undoable, but space is freed only when the Trash is emptied.
    case trash
}

public enum ItemLevel: String, Codable, Sendable {
    /// Each immediate child of a root is one item.
    case children
    /// The root itself (folder or file) is one item.
    case root
    /// Every regular file at any depth under a root that is at least `minSizeMB`.
    /// Never descends into packages (apps, photo and video libraries) or hidden folders.
    case largeFiles
}

public struct CleanRule: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public var name: String
    public let group: CategoryGroup
    public let safety: Safety
    public let roots: [String]
    public let itemLevel: ItemLevel
    public let include: [String]?
    public let exclude: [String]?
    public let minAgeDays: Int?
    public let minSizeMB: Int?
    public let blockIfRunning: [String]?
    /// For `children`: the child folder name is the app's bundle id.
    public let childIsBundleID: Bool?
    /// For roots with `*`: the first matched segment names the app (one row per app).
    public let appKeyFromGlob: Bool?
    /// That matched segment is a bundle id (used for the app name, icon and "is it running").
    public let appKeyIsBundleID: Bool?
    public var appGroup: String?
    public let defaultOn: Bool
    public let mode: CleanMode
    /// Ask before cleaning (permanent deletion of something the user put aside, like the Trash).
    public let confirm: Bool?
    public var description: String

    public init(id: String, name: String, group: CategoryGroup, safety: Safety, roots: [String],
                itemLevel: ItemLevel, include: [String]? = nil, exclude: [String]? = nil,
                minAgeDays: Int? = nil, minSizeMB: Int? = nil, blockIfRunning: [String]? = nil,
                childIsBundleID: Bool? = nil, appKeyFromGlob: Bool? = nil, appKeyIsBundleID: Bool? = nil,
                appGroup: String? = nil, defaultOn: Bool = true, mode: CleanMode = .delete,
                confirm: Bool? = nil, description: String = "") {
        self.id = id; self.name = name; self.group = group; self.safety = safety; self.roots = roots
        self.itemLevel = itemLevel; self.include = include; self.exclude = exclude
        self.minAgeDays = minAgeDays; self.minSizeMB = minSizeMB; self.blockIfRunning = blockIfRunning
        self.childIsBundleID = childIsBundleID; self.appKeyFromGlob = appKeyFromGlob
        self.appKeyIsBundleID = appKeyIsBundleID; self.appGroup = appGroup
        self.defaultOn = defaultOn; self.mode = mode; self.confirm = confirm; self.description = description
    }

    /// Whether a child with this file name belongs to the rule (include/exclude wildcard lists).
    public func accepts(childName name: String) -> Bool {
        if name.hasPrefix(".") && name != ".Trash" { return false }
        if let include = include, !include.isEmpty,
           !include.contains(where: { Wildcard.matches(pattern: $0, name) }) {
            return false
        }
        if let exclude = exclude, exclude.contains(where: { Wildcard.matches(pattern: $0, name) }) {
            return false
        }
        return true
    }

    /// True when a running app's bundle id starts with one of this rule's prefixes,
    /// or equals the bundle id this particular item belongs to.
    public func isBlocked(appBundleID: String?, running: Set<String>) -> Bool {
        if let prefixes = blockIfRunning {
            for id in running where prefixes.contains(where: { id.hasPrefix($0) }) { return true }
        }
        if let id = appBundleID, running.contains(id) { return true }
        return false
    }
}

public struct RuleSet: Codable, Sendable {
    public let version: Int
    public let rules: [CleanRule]

    public init(version: Int, rules: [CleanRule]) {
        self.version = version
        self.rules = rules
    }

    /// The rules shipped inside the app.
    public static func bundled() throws -> RuleSet {
        // Inside "Kartov Cleaner.app" the resource bundle sits in Contents/Resources.
        // Look there first: Bundle.module stops the app if its build-time path is missing.
        let set: RuleSet
        if let url = rulesInAppBundle() {
            set = try JSONDecoder().decode(RuleSet.self, from: Data(contentsOf: url))
        } else {
            guard let url = Bundle.module.url(forResource: "rules", withExtension: "json") else {
                throw KartovError.missingRules
            }
            set = try JSONDecoder().decode(RuleSet.self, from: Data(contentsOf: url))
        }
        // Rule names and explanations are written in Turkish; show them in the chosen language.
        return RuleSet(version: set.version, rules: set.rules.map { rule in
            var r = rule
            r.name = L(r.name)
            r.description = L(r.description)
            // appGroup stays as written: it is also the key that remembers "keep" choices.
            return r
        })
    }

    private static func rulesInAppBundle() -> URL? {
        guard let resources = Bundle.main.resourceURL,
              let names = try? FileManager.default.contentsOfDirectory(atPath: resources.path) else { return nil }
        for name in names where name.hasSuffix(".bundle") && name.contains("KartovCore") {
            let bundleURL = resources.appendingPathComponent(name)
            for candidate in ["rules.json", "Contents/Resources/rules.json"] {
                let url = bundleURL.appendingPathComponent(candidate)
                if FileManager.default.fileExists(atPath: url.path) { return url }
            }
        }
        return nil
    }
}

public enum KartovError: Error, LocalizedError, Equatable {
    case missingRules
    case trashUnavailable
    case unsafePath(String)

    public var errorDescription: String? {
        switch self {
        case .missingRules: return L("Temizlik kuralları bulunamadı.")
        case .trashUnavailable: return L("Çöp kutusu bu sistemde kullanılamıyor.")
        case .unsafePath(let p): return L("Güvenlik kontrolü bu yolu reddetti: {0}", p)
        }
    }
}

/// Minimal wildcard matching: `*` matches any run of characters, everything else is literal.
public enum Wildcard {
    public static func matches(pattern: String, _ text: String) -> Bool {
        let p = Array(pattern), t = Array(text)
        var pi = 0, ti = 0, star = -1, mark = 0
        while ti < t.count {
            if pi < p.count, p[pi] != "*", p[pi] == t[ti] {
                pi += 1; ti += 1
            } else if pi < p.count, p[pi] == "*" {
                star = pi; mark = ti; pi += 1
            } else if star >= 0 {
                pi = star + 1; mark += 1; ti = mark
            } else {
                return false
            }
        }
        while pi < p.count, p[pi] == "*" { pi += 1 }
        return pi == p.count
    }
}

/// Expands `~` and `$TMPDIR`, and `*` path segments. Tests pass a temporary home.
public struct Paths: Sendable {
    public let home: URL
    public let temp: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                temp: URL = FileManager.default.temporaryDirectory) {
        self.home = home.standardizedFileURL
        self.temp = temp.standardizedFileURL
    }

    public func expand(_ path: String) -> URL {
        if path == "~" { return home }
        if path.hasPrefix("~/") {
            return home.appendingPathComponent(String(path.dropFirst(2))).standardizedFileURL
        }
        if path == "$TMPDIR" { return temp }
        if path.hasPrefix("$TMPDIR/") {
            return temp.appendingPathComponent(String(path.dropFirst(8))).standardizedFileURL
        }
        return URL(fileURLWithPath: path).standardizedFileURL
    }

    public struct Match: Sendable, Hashable {
        public let url: URL
        /// The name matched by the first `*` segment, if any.
        public let capture: String?
    }

    /// Existing paths matching a root pattern. A `*` matches one path segment, never a hidden
    /// name, and the walk never passes through a symbolic link.
    public func expandGlob(_ pattern: String, fileManager fm: FileManager = .default) -> [Match] {
        let base = expand(pattern)
        guard base.path.contains("*") else {
            return fm.fileExists(atPath: base.path) ? [Match(url: base, capture: nil)] : []
        }
        var current: [Match] = [Match(url: URL(fileURLWithPath: "/"), capture: nil)]
        for comp in base.pathComponents.dropFirst() {
            var next: [Match] = []
            for m in current {
                if comp.contains("*") {
                    guard let names = try? fm.contentsOfDirectory(atPath: m.url.path) else { continue }
                    for n in names.sorted() where !n.hasPrefix(".") && Wildcard.matches(pattern: comp, n) {
                        let u = m.url.appendingPathComponent(n)
                        if Paths.isSymlink(u.path, fm) { continue }
                        next.append(Match(url: u, capture: m.capture ?? n))
                    }
                } else {
                    next.append(Match(url: m.url.appendingPathComponent(comp), capture: m.capture))
                }
            }
            current = next
            if current.isEmpty { break }
        }
        return current.filter { fm.fileExists(atPath: $0.url.path) }
            .map { Match(url: $0.url.standardizedFileURL, capture: $0.capture) }
    }

    static func isSymlink(_ path: String, _ fm: FileManager) -> Bool {
        guard let attrs = try? fm.attributesOfItem(atPath: path) else { return false }
        return (attrs[.type] as? FileAttributeType) == .typeSymbolicLink
    }
}
