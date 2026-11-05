import Foundation

/// The last line of defence before anything is removed.
///
/// An item may be cleaned only when it is an exact match of the rule it was found by:
/// the rule's root itself (`root`), an immediate accepted child of a root (`children`),
/// or a regular file somewhere under a root, outside any package (`largeFiles`).
/// It must not be a symbolic link or sit behind one, and it must never be one of the
/// protected folders themselves.
///
/// Personal folders (Documents, Desktop, Downloads, Movies, Music, Pictures) are protected
/// too, with one way in: rules that only *offer* files there (never selected by default,
/// always moved to the Trash, so every removal can be undone). iCloud Drive, Mail,
/// Messages and Keychains have no way in at all.
public struct SafetyPolicy: Sendable {
    public enum Verdict: Equatable, Sendable {
        case ok
        case forbidden
        case notMatchingRule
        case symlink
        case missing
    }

    public let paths: Paths
    public let forbidden: Set<String>

    /// Shown on the scan screen as "never touched".
    public static let neverTouchedNames = ["iCloud Drive", L("Fotoğraflar arşivi"), L("Final Cut ve iMovie kütüphaneleri"),
                                           L("Mail ve Mesajlar"), L("Anahtar Zinciri"), L("Uygulama paketlerinin içi")]

    /// Folder name endings that are opaque packages: their insides are never listed or touched.
    public static let packageExtensions = [".app", ".photoslibrary", ".photolibrary", ".fcpbundle", ".imovielibrary",
                                           ".musiclibrary", ".tvlibrary", ".aplibrary", ".logicx", ".band",
                                           ".bundle", ".framework", ".xcodeproj", ".xcworkspace", ".prproj",
                                           ".aep", ".drp", ".plugin", ".kext", ".sparsebundle"]

    public init(paths: Paths) {
        self.paths = paths
        let h = paths.home.path
        var f: Set<String> = [
            "/", "/System", "/Library", "/Applications", "/Users", "/Users/Shared", "/private", "/usr", "/bin",
            "/sbin", "/var", "/etc", "/opt", "/Volumes", paths.temp.path
        ]
        for sub in ["", "/Documents", "/Desktop", "/Downloads", "/Pictures", "/Movies", "/Music",
                    "/Public", "/Applications", "/Library", "/Library/Mobile Documents",
                    "/Library/CloudStorage", "/Library/Application Support", "/Library/Containers",
                    "/Library/Group Containers", "/Library/Caches", "/Library/Logs",
                    "/Library/Preferences", "/Library/Keychains", "/Library/Mail", "/Library/Messages",
                    "/Library/Photos", "/Library/Safari", "/.Trash", "/Library/Developer"] {
            f.insert(h + sub)
        }
        self.forbidden = f
    }

    /// Never reachable by any rule.
    private var hardTrees: [String] {
        let h = paths.home.path
        return [h + "/Library/Mobile Documents", h + "/Library/CloudStorage", h + "/Library/Keychains",
                h + "/Library/Mail", h + "/Library/Messages", h + "/Library/Photos", "/System"]
    }

    /// The user's own folders: reachable only by rules that merely offer files (see type doc).
    private var personalTrees: [String] {
        let h = paths.home.path
        return [h + "/Documents", h + "/Desktop", h + "/Downloads", h + "/Pictures", h + "/Movies", h + "/Music"]
    }

    private func offersOnly(_ rule: CleanRule) -> Bool {
        rule.mode == .trash && (!rule.defaultOn || (rule.include?.isEmpty == false && rule.itemLevel == .children))
    }

    public func check(_ url: URL, rule: CleanRule, fileManager fm: FileManager = .default) -> Verdict {
        let std = url.standardizedFileURL
        let path = std.path
        if forbidden.contains(path) { return .forbidden }
        if hardTrees.contains(where: { path.hasPrefix($0 + "/") }) { return .forbidden }
        if personalTrees.contains(where: { path.hasPrefix($0 + "/") }) {
            let regenerableException = path == paths.home.path + "/Movies/CacheClip" && rule.itemLevel == .root
            if !regenerableException && !offersOnly(rule) { return .forbidden }
        }

        let roots = rule.roots.flatMap { paths.expandGlob($0, fileManager: fm) }.map(\.url)
        let rootPaths = roots.map(\.path)
        let parent = std.deletingLastPathComponent()

        switch rule.itemLevel {
        case .root:
            guard rootPaths.contains(path) else { return .notMatchingRule }
        case .children:
            guard rootPaths.contains(parent.path), rule.accepts(childName: std.lastPathComponent) else {
                return .notMatchingRule
            }
        case .largeFiles:
            guard let root = rootPaths.first(where: { path.hasPrefix($0 + "/") }) else { return .notMatchingRule }
            if Self.crossesPackageOrHidden(path: path, below: root) { return .notMatchingRule }
        }

        guard let attrs = try? fm.attributesOfItem(atPath: path) else { return .missing }
        let type = attrs[.type] as? FileAttributeType
        if type == .typeSymbolicLink { return .symlink }
        if rule.itemLevel == .largeFiles && type != .typeRegular { return .notMatchingRule }

        // No symlink anywhere between the root and the item.
        let resolvedParent = parent.resolvingSymlinksInPath().path
        let chainOK: Bool
        switch rule.itemLevel {
        case .root:
            chainOK = roots.contains { $0.deletingLastPathComponent().resolvingSymlinksInPath().path == resolvedParent }
        case .children:
            chainOK = roots.contains { $0.resolvingSymlinksInPath().path == resolvedParent }
        case .largeFiles:
            chainOK = roots.contains {
                let r = $0.resolvingSymlinksInPath().path
                return resolvedParent == r || resolvedParent.hasPrefix(r + "/")
            }
        }
        return chainOK ? .ok : .symlink
    }

    /// True when a folder between `root` and the file is a package or a hidden folder.
    static func crossesPackageOrHidden(path: String, below root: String) -> Bool {
        let rest = path.dropFirst(root.count + 1).split(separator: "/").dropLast()
        for comp in rest {
            let c = String(comp)
            if c.hasPrefix(".") { return true }
            if packageExtensions.contains(where: { c.lowercased().hasSuffix($0) }) { return true }
        }
        return false
    }
}
