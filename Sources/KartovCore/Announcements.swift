import Foundation

/// Short messages from the developer, read from `announcements.json` in the GitHub repository.
/// No server: the app fetches the file now and then and shows each announcement once.
///
/// File format:
/// ```json
/// { "announcements": [ {
///     "id": "2026-11-16-hello",                 // unique, never reused
///     "title": { "en": "…", "tr": "…" },        // English is the fallback
///     "body":  { "en": "…", "tr": "…" },
///     "url": "https://…",                       // optional, opened only when the user clicks
///     "minVersion": "0.8.1", "maxVersion": "0.9",  // optional: who sees it
///     "expires": "2026-12-31"                   // optional: not shown after this day
/// } ] }
/// ```
public struct Announcement: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: [String: String]
    public let body: [String: String]
    public let url: String?
    public let minVersion: String?
    public let maxVersion: String?
    public let expires: String?

    public init(id: String, title: [String: String], body: [String: String], url: String? = nil,
                minVersion: String? = nil, maxVersion: String? = nil, expires: String? = nil) {
        self.id = id; self.title = title; self.body = body; self.url = url
        self.minVersion = minVersion; self.maxVersion = maxVersion; self.expires = expires
    }

    /// The text in `language`, else English, else any language given.
    public static func pick(_ texts: [String: String], language: String) -> String {
        let clean = texts.mapValues { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.value.isEmpty }
        return clean[language.lowercased()] ?? clean["en"] ?? clean.sorted { $0.key < $1.key }.first?.value ?? ""
    }

    public func title(in language: String) -> String { Self.pick(title, language: language) }
    public func body(in language: String) -> String { Self.pick(body, language: language) }

    /// Only https links are ever opened.
    public var link: URL? {
        guard let s = url?.trimmingCharacters(in: .whitespaces), let u = URL(string: s),
              u.scheme?.lowercased() == "https", u.host != nil else { return nil }
        return u
    }

    /// The last day it is shown (inclusive), read as a local date.
    var expiryDate: Date? {
        guard let e = expires?.trimmingCharacters(in: .whitespaces), !e.isEmpty else { return nil }
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        guard let day = f.date(from: e) else { return nil }
        return Calendar(identifier: .gregorian).date(byAdding: .day, value: 1, to: day)
    }

    public func isActive(version: String, now: Date = Date()) -> Bool {
        if let end = expiryDate, now >= end { return false }
        if let min = minVersion, !min.isEmpty, AppVersion.isNewer(min, than: version) { return false }
        if let max = maxVersion, !max.isEmpty, AppVersion.isNewer(version, than: max) { return false }
        return true
    }
}

public enum AppVersion {
    /// "0.10" > "0.9", "1.0" == "1".
    public static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}

public enum AnnouncementFeed {
    struct File: Codable { let announcements: [Announcement] }

    /// Reads the file; a broken file or a broken entry is skipped, never shown half-way.
    public static func parse(_ data: Data) -> [Announcement] {
        guard let f = try? JSONDecoder().decode(File.self, from: data) else { return [] }
        return f.announcements.filter { !$0.id.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// What to show now: active, not seen yet, with a title, at most `limit`, in file order.
    public static func toShow(_ all: [Announcement], seen: Set<String>, version: String, language: String,
                              now: Date = Date(), limit: Int = 2) -> [Announcement] {
        var out: [Announcement] = []
        var ids = Set<String>()
        for a in all where !seen.contains(a.id) && !ids.contains(a.id) {
            guard a.isActive(version: version, now: now), !a.title(in: language).isEmpty else { continue }
            out.append(a)
            ids.insert(a.id)
            if out.count == limit { break }
        }
        return out
    }
}
