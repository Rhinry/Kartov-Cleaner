import Foundation

// MARK: - storage forecast

/// One reading of the startup disk.
public struct DiskSample: Codable, Sendable, Hashable {
    public var date: Date
    public var used: Int64
    public var total: Int64
    public init(date: Date, used: Int64, total: Int64) {
        self.date = date; self.used = used; self.total = total
    }
}

/// When the disk will be full at the current pace, from a straight line through recent readings.
public struct StorageForecast: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// Not enough history yet; `daysCollected` of `daysNeeded`.
        case collecting(daysCollected: Double, daysNeeded: Double)
        /// Use is flat or shrinking.
        case steady
        /// Full in about `days` days.
        case fills(days: Double)
    }
    public var kind: Kind
    /// Bytes added per day (negative when shrinking).
    public var perDay: Double
    /// The readings used, oldest first.
    public var samples: [DiskSample]

    public static let daysNeeded: Double = 2
    /// Below this growth per day the disk counts as steady.
    public static let steadyBelow: Double = 100_000_000

    /// Least-squares line over the last `window` days.
    public static func make(_ all: [DiskSample], now: Date = Date(), window: Double = 30) -> StorageForecast {
        let cutoff = now.addingTimeInterval(-window * 86_400)
        let s = all.filter { $0.date >= cutoff && $0.total > 0 }.sorted { $0.date < $1.date }
        guard let first = s.first, let last = s.last else {
            return StorageForecast(kind: .collecting(daysCollected: 0, daysNeeded: daysNeeded), perDay: 0, samples: s)
        }
        let span = last.date.timeIntervalSince(first.date) / 86_400
        guard span >= daysNeeded, s.count >= 3 else {
            return StorageForecast(kind: .collecting(daysCollected: max(0, span), daysNeeded: daysNeeded), perDay: 0, samples: s)
        }
        let xs = s.map { $0.date.timeIntervalSince(first.date) / 86_400 }
        let ys = s.map { Double($0.used) }
        let n = Double(s.count)
        let mx = xs.reduce(0, +) / n, my = ys.reduce(0, +) / n
        var num = 0.0, den = 0.0
        for i in 0..<s.count { num += (xs[i] - mx) * (ys[i] - my); den += (xs[i] - mx) * (xs[i] - mx) }
        let slope = den > 0 ? num / den : 0
        guard slope >= steadyBelow else { return StorageForecast(kind: .steady, perDay: slope, samples: s) }
        // "Full" means 98 % used: macOS stops working well before the last byte.
        let room = Double(last.total) * 0.98 - Double(last.used)
        let days = max(0, room / slope)
        return StorageForecast(kind: days > 3650 ? .steady : .fills(days: days), perDay: slope, samples: s)
    }

    /// Keeps every reading from the last two weeks and one per six hours before that, for up to 180 days.
    public static func thin(_ all: [DiskSample], now: Date = Date()) -> [DiskSample] {
        let recent = now.addingTimeInterval(-14 * 86_400)
        let oldest = now.addingTimeInterval(-180 * 86_400)
        var out: [DiskSample] = []
        var lastKept: Date?
        for s in all.sorted(by: { $0.date < $1.date }) where s.date >= oldest {
            if s.date >= recent { out.append(s); continue }
            if let k = lastKept, s.date.timeIntervalSince(k) < 6 * 3600 { continue }
            out.append(s)
            lastKept = s.date
        }
        return out
    }
}

// MARK: - crash reports

/// One diagnostic report from ~/Library/Logs/DiagnosticReports or /Library/Logs/DiagnosticReports.
public struct CrashReport: Sendable, Identifiable, Hashable {
    public enum Kind: String, Sendable, Codable { case crash, hang, resource, panic }
    public var id: String { url.path }
    public let url: URL
    public let app: String
    public let bundleID: String?
    public let version: String?
    public let date: Date
    public let kind: Kind
    /// `EXC_BAD_ACCESS`, `EXC_CRASH (SIGABRT)`, `cpu_resource`…
    public let reason: String?

    public init(url: URL, app: String, bundleID: String?, version: String?, date: Date, kind: Kind, reason: String?) {
        self.url = url; self.app = app; self.bundleID = bundleID; self.version = version
        self.date = date; self.kind = kind; self.reason = reason
    }
}

public enum CrashReportParser {
    static let extensions: Set<String> = ["ips", "crash", "hang", "spin", "diag", "panic"]

    /// Reads every report newer than `since` in the given folders (and their "Retired" subfolders).
    public static func scan(folders: [URL], since: Date, fileManager fm: FileManager = .default) -> [CrashReport] {
        var out: [CrashReport] = []
        var dirs = folders
        dirs += folders.map { $0.appendingPathComponent("Retired") }
        for dir in dirs {
            guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
            for name in names {
                let url = dir.appendingPathComponent(name)
                guard extensions.contains(url.pathExtension.lowercased()) else { continue }
                let attrs = try? fm.attributesOfItem(atPath: url.path)
                let modified = attrs?[.modificationDate] as? Date ?? .distantPast
                guard modified >= since else { continue }
                let size = (attrs?[.size] as? NSNumber)?.intValue ?? 0
                if let r = parse(url, modified: modified, size: size) { out.append(r) }
            }
        }
        return out.sorted { $0.date > $1.date }
    }

    /// Reads one report. Only the first part of large files is read.
    public static func parse(_ url: URL, modified: Date, size: Int = 0) -> CrashReport? {
        let name = url.lastPathComponent
        let lower = name.lowercased()
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let data = handle.readData(ofLength: 2_000_000)
        let text = String(decoding: data, as: UTF8.self)
        let fileApp = appName(fromFileName: name)

        if lower.hasSuffix(".panic") || lower.hasPrefix("kernel") {
            return CrashReport(url: url, app: "macOS", bundleID: nil, version: nil, date: modified, kind: .panic,
                               reason: "kernel panic")
        }
        if url.pathExtension.lowercased() == "ips" {
            // First line: a small JSON header. The rest: the report body (JSON on recent macOS).
            let parts = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            let header = parts.first.flatMap { json(String($0)) } ?? [:]
            let body = parts.count > 1 ? (json(String(parts[1])) ?? [:]) : [:]
            let bugType = header["bug_type"] as? String ?? ""
            let app = (header["app_name"] as? String) ?? (header["name"] as? String) ?? (body["procName"] as? String) ?? fileApp
            let bundle = (header["bundleID"] as? String) ?? ((body["bundleInfo"] as? [String: Any])?["CFBundleIdentifier"] as? String)
            let version = (header["app_version"] as? String) ?? ((body["bundleInfo"] as? [String: Any])?["CFBundleShortVersionString"] as? String)
            let date = (header["timestamp"] as? String).flatMap(parseDate) ?? modified
            guard var kind = kindFor(bugType: bugType, fileName: lower) else { return nil }
            var reason: String?
            if let ex = body["exception"] as? [String: Any] {
                let type = ex["type"] as? String ?? ""
                let signal = ex["signal"] as? String
                reason = signal.map { "\(type) (\($0))" } ?? type
            } else if kind == .panic || bugType == "210" {
                kind = .panic
                reason = "kernel panic"
            } else if kind == .resource {
                reason = resourceReason(lower)
            }
            if reason == nil, let term = body["termination"] as? [String: Any], let ind = term["indicator"] as? String {
                reason = ind
            }
            return CrashReport(url: url, app: app, bundleID: bundle, version: version, date: date, kind: kind, reason: reason)
        }
        // Older plain-text reports.
        var app = fileApp, bundle: String?, version: String?, reason: String?
        for line in text.split(separator: "\n").prefix(80) {
            let l = String(line)
            if l.hasPrefix("Process:") { app = clean(l.dropFirst(8)).components(separatedBy: " [").first ?? app }
            else if l.hasPrefix("Identifier:") { bundle = clean(l.dropFirst(11)) }
            else if l.hasPrefix("Version:") { version = clean(l.dropFirst(8)).components(separatedBy: " (").first }
            else if l.hasPrefix("Exception Type:") { reason = clean(l.dropFirst(15)) }
        }
        guard let kind = kindFor(bugType: "", fileName: lower) else { return nil }
        if kind == .resource && reason == nil { reason = resourceReason(lower) }
        return CrashReport(url: url, app: app, bundleID: bundle, version: version, date: modified, kind: kind, reason: reason)
    }

    /// Only real crashes, hangs, resource reports and panics; macOS's many analytics and
    /// diagnostics files (JetsamEvent, SFA-*, proactive_event_tracker…) are skipped.
    static func kindFor(bugType: String, fileName: String) -> CrashReport.Kind? {
        if fileName.hasSuffix(".panic") || bugType == "210" { return .panic }
        if fileName.hasSuffix(".diag") && fileName.contains("_resource") { return .resource }
        if fileName.hasSuffix(".hang") || fileName.hasSuffix(".spin") || bugType == "409" || bugType == "228" { return .hang }
        if bugType == "309" || bugType == "109" || fileName.hasSuffix(".crash") { return .crash }
        return nil
    }

    static func resourceReason(_ fileName: String) -> String {
        if fileName.contains("cpu_resource") { return "cpu_resource" }
        if fileName.contains("diskwrites_resource") { return "diskwrites_resource" }
        if fileName.contains("wakeups_resource") { return "wakeups_resource" }
        return "resource"
    }

    /// "Google Chrome_2026-11-04-101522_MacBook.ips" → "Google Chrome"
    public static func appName(fromFileName name: String) -> String {
        var base = (name as NSString).deletingPathExtension
        base = base.replacingOccurrences(of: ".cpu_resource", with: "")
            .replacingOccurrences(of: ".diskwrites_resource", with: "")
            .replacingOccurrences(of: ".wakeups_resource", with: "")
        if let r = base.range(of: #"[-_]\d{4}-\d{2}-\d{2}"#, options: .regularExpression) {
            return String(base[..<r.lowerBound])
        }
        return base
    }

    static func json(_ s: String) -> [String: Any]? {
        guard let d = s.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
    }

    static func clean(_ s: Substring) -> String { s.trimmingCharacters(in: .whitespaces) }

    /// "2026-11-04 10:15:22.00 +0300"
    static func parseDate(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd HH:mm:ss.SS Z", "yyyy-MM-dd HH:mm:ss Z", "yyyy-MM-dd HH:mm:ss.SSSS Z"] {
            f.dateFormat = format
            if let d = f.date(from: s) { return d }
        }
        return nil
    }
}

// MARK: - what an app keeps in the Library

/// The files an app has spread over ~/Library, grouped by what they are for.
public struct FootprintNode: Sendable, Identifiable, Hashable {
    public enum Kind: String, Sendable, CaseIterable, Codable {
        case cache, logs, preferences, support, container, savedState, webData, startup

        /// Regenerated by the app: may be moved to the Trash (after the user confirms).
        public var removable: Bool { self == .cache || self == .logs || self == .savedState || self == .webData }
    }
    public var id: String { kind.rawValue }
    public let kind: Kind
    public let urls: [URL]
    public let bytes: Int64
    public init(kind: Kind, urls: [URL], bytes: Int64) { self.kind = kind; self.urls = urls; self.bytes = bytes }
}

public enum AppFootprint {
    /// Only exact names are matched (the app's bundle id, or its full name when it is long enough),
    /// so another app's files are never mistaken for this one's.
    public static func scan(bundleID: String, appName: String, home: URL = FileManager.default.homeDirectoryForCurrentUser,
                            measure: Bool = true, fileManager fm: FileManager = .default) -> [FootprintNode] {
        guard bundleID.count > 3, !bundleID.hasPrefix("com.apple.") else { return [] }
        let lib = home.appendingPathComponent("Library")
        let useName = appName.count >= 4 && !appName.contains("/")
        var map: [FootprintNode.Kind: [String]] = [
            .cache: ["Caches/\(bundleID)"],
            .logs: ["Logs/\(bundleID)"],
            .preferences: ["Preferences/\(bundleID).plist"],
            .support: ["Application Support/\(bundleID)"],
            .container: ["Containers/\(bundleID)"],
            .savedState: ["Saved Application State/\(bundleID).savedState"],
            .webData: ["HTTPStorages/\(bundleID)", "HTTPStorages/\(bundleID).binarycookies", "WebKit/\(bundleID)",
                       "Cookies/\(bundleID).binarycookies"],
            .startup: []
        ]
        if useName {
            map[.cache, default: []].append("Caches/\(appName)")
            map[.logs, default: []].append("Logs/\(appName)")
            map[.support, default: []].append("Application Support/\(appName)")
        }
        var extra: [FootprintNode.Kind: [URL]] = [:]
        // Per-machine preferences: ByHost/<bundle id>.<uuid>.plist
        let byHost = lib.appendingPathComponent("Preferences/ByHost")
        if let names = try? fm.contentsOfDirectory(atPath: byHost.path) {
            extra[.preferences, default: []] += names.filter { $0.hasPrefix(bundleID + ".") }.map { byHost.appendingPathComponent($0) }
        }
        // Shared containers are named "<team id>.<group id>".
        let groups = lib.appendingPathComponent("Group Containers")
        if let names = try? fm.contentsOfDirectory(atPath: groups.path) {
            extra[.container, default: []] += names.filter { $0.hasSuffix("." + bundleID) }.map { groups.appendingPathComponent($0) }
        }
        // Helpers that start with the Mac, named after the app's bundle id.
        for dir in [lib.appendingPathComponent("LaunchAgents"), URL(fileURLWithPath: "/Library/LaunchAgents"),
                    URL(fileURLWithPath: "/Library/LaunchDaemons")] {
            if let names = try? fm.contentsOfDirectory(atPath: dir.path) {
                extra[.startup, default: []] += names.filter { $0.hasPrefix(bundleID) && $0.hasSuffix(".plist") }
                    .map { dir.appendingPathComponent($0) }
            }
        }
        var out: [FootprintNode] = []
        for kind in FootprintNode.Kind.allCases {
            var seen = Set<String>()
            var urls: [URL] = []
            let candidates = (map[kind] ?? []).map { lib.appendingPathComponent($0) } + (extra[kind] ?? [])
            for u in candidates {
                let p = u.standardizedFileURL.path
                guard !seen.contains(p), fm.fileExists(atPath: p), !Paths.isSymlink(p, fm) else { continue }
                seen.insert(p)
                urls.append(u)
            }
            guard !urls.isEmpty else { continue }
            let bytes = measure ? urls.reduce(Int64(0)) { $0 + SizeCalculator.measure($1, fileManager: fm).bytes } : 0
            out.append(FootprintNode(kind: kind, urls: urls, bytes: bytes))
        }
        return out
    }

    /// Total bytes an app keeps in the Library (for growth tracking).
    public static func total(bundleID: String, appName: String, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Int64 {
        scan(bundleID: bundleID, appName: appName, home: home).filter { $0.kind != .startup }.reduce(0) { $0 + $1.bytes }
    }
}

// MARK: - moving chosen paths to the Trash

/// Moves the given paths to the Trash and returns a History record (undoable).
public enum PathTrasher {
    public static func trash(_ urls: [URL], ruleID: String, appKey: String,
                             remover: FileRemoving = SystemFileRemover(), date: Date = Date()) -> CleanRecord {
        var items: [CleanItemRecord] = []
        var trashed: Int64 = 0
        for u in urls {
            let size = SizeCalculator.measure(u).bytes
            var rec = CleanItemRecord(id: UUID(), ruleID: ruleID, appKey: appKey, originalPath: u.path,
                                      trashedPath: nil, size: size, status: .skipped, reason: nil)
            do {
                rec.trashedPath = try remover.trash(u)?.path
                rec.status = .trashed
                trashed += size
            } catch {
                rec.status = .failed
                rec.reason = L("macOS izin vermedi; Finder'dan çöpe atabilirsin")
            }
            items.append(rec)
        }
        return CleanRecord(id: UUID(), date: date, items: items, bytesCleaned: trashed, bytesDeleted: 0,
                           bytesInTrash: trashed, measuredFreed: nil, undoneAt: nil, automatic: nil)
    }
}

// MARK: - release notes in several languages

/// GitHub shows the English notes. Translations ride along in a hidden HTML comment at the end:
///
///     <!-- kartov-i18n
///     [tr]
///     Türkçe notlar
///     [de]
///     …
///     -->
///
/// The app shows the part in its own language, or the English text when there is none.
public enum ReleaseNotes {
    public static func localized(_ body: String, language: String) -> String {
        let text = body.replacingOccurrences(of: "\r\n", with: "\n")
        guard let start = text.range(of: "<!-- kartov-i18n") else {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let rest = text[start.upperBound...]
        let end = rest.range(of: "-->")
        let block = end.map { String(rest[..<$0.lowerBound]) } ?? String(rest)
        var visible = String(text[..<start.lowerBound])
        if let end { visible += String(rest[end.upperBound...]) }
        visible = visible.trimmingCharacters(in: .whitespacesAndNewlines)

        var sections: [String: [String]] = [:]
        var current: String?
        for line in block.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.count >= 4, t.hasPrefix("["), t.hasSuffix("]"), !t.contains(" ") {
                current = String(t.dropFirst().dropLast()).lowercased()
                sections[current!] = []
            } else if let c = current {
                sections[c, default: []].append(line)
            }
        }
        let lang = language.lowercased()
        if lang != "en", let lines = sections[lang] {
            let t = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t }
        }
        return visible
    }
}

// MARK: - weekly summary

/// What happened on the Mac over the last week, in a few short sentences.
public struct WeeklyDigest: Sendable, Equatable {
    /// Bytes the disk filled (positive) or emptied (negative); nil without enough readings.
    public var diskDelta: Int64?
    public var cleaned: Int64
    public var alerts: Int
    public var crashes: Int
    public var growthName: String?
    public var growthBytes: Int64
    public var idleProjects: Int
    public var idleProjectBytes: Int64

    public init(diskDelta: Int64? = nil, cleaned: Int64 = 0, alerts: Int = 0, crashes: Int = 0,
                growthName: String? = nil, growthBytes: Int64 = 0, idleProjects: Int = 0, idleProjectBytes: Int64 = 0) {
        self.diskDelta = diskDelta; self.cleaned = cleaned; self.alerts = alerts; self.crashes = crashes
        self.growthName = growthName; self.growthBytes = growthBytes
        self.idleProjects = idleProjects; self.idleProjectBytes = idleProjectBytes
    }

    /// How much the used space changed between the oldest reading of the last `days` days and the newest.
    /// Needs readings at least three days apart.
    public static func diskChange(_ samples: [DiskSample], days: Double = 7, now: Date = Date()) -> Int64? {
        let cutoff = now.addingTimeInterval(-(days + 0.5) * 86_400)
        let s = samples.filter { $0.date >= cutoff && $0.date <= now }.sorted { $0.date < $1.date }
        guard let first = s.first, let last = s.last, last.date.timeIntervalSince(first.date) >= 3 * 86_400 else { return nil }
        return last.used - first.used
    }

    /// The sentences, joined. `bytes` formats a byte count ("3,2 GB").
    public func text(bytes: (Int64) -> String) -> String {
        var parts: [String] = []
        if let d = diskDelta {
            if d >= 100_000_000 { parts.append(L("Bu hafta disk {0} doldu.", bytes(d))) }
            else if d <= -100_000_000 { parts.append(L("Bu hafta diskte {0} yer açıldı.", bytes(-d))) }
            else { parts.append(L("Bu hafta disk kullanımı değişmedi.")) }
        }
        if cleaned > 0 { parts.append(L("Kartov {0} temizledi.", bytes(cleaned))) }
        if alerts == 0 && crashes == 0 { parts.append(L("Uyarı ya da çökme yok.")) }
        else { parts.append(L("{0} uyarı, {1} çökme.", alerts, crashes)) }
        if let n = growthName, growthBytes > 0 { parts.append(L("En çok büyüyen: {0} (+{1}).", n, bytes(growthBytes))) }
        if idleProjects > 0 && idleProjectBytes > 0 {
            parts.append(L("{0} projeye uzun süredir dokunulmadı; önbellekleri {1} tutuyor.", idleProjects, bytes(idleProjectBytes)))
        }
        return parts.joined(separator: " ")
    }
}
