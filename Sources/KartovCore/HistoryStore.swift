import Foundation

/// Small JSON store for the first slice: clean history and per-app "keep" choices.
/// Lives in ~/Library/Application Support/KartovCleaner. (The SQLite schema in
/// replica/schema.sql replaces this once statistics and daily snapshots arrive.)
public final class HistoryStore: @unchecked Sendable {
    public struct Snapshot: Codable, Sendable {
        public var records: [CleanRecord] = []
        /// Selection keys (`ruleID|appKey`) the user chose to keep.
        public var kept: Set<String> = []
        /// Selection keys of opt-in rules the user chose to clean.
        public var optedIn: Set<String> = []
        public init() {}

        enum CodingKeys: String, CodingKey { case records, kept, optedIn }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            records = try c.decodeIfPresent([CleanRecord].self, forKey: .records) ?? []
            kept = try c.decodeIfPresent(Set<String>.self, forKey: .kept) ?? []
            optedIn = try c.decodeIfPresent(Set<String>.self, forKey: .optedIn) ?? []
        }
    }

    public let fileURL: URL
    private let lock = NSLock()
    private var cached: Snapshot?

    public init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KartovCleaner", isDirectory: true)
        self.fileURL = dir.appendingPathComponent("history.json")
    }

    public func load() -> Snapshot {
        lock.lock(); defer { lock.unlock() }
        if let c = cached { return c }
        var snap = Snapshot()
        if let data = try? Data(contentsOf: fileURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let s = try? decoder.decode(Snapshot.self, from: data) { snap = s }
        }
        cached = snap
        return snap
    }

    public func save(_ snap: Snapshot) {
        lock.lock(); defer { lock.unlock() }
        cached = snap
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(snap).write(to: fileURL, options: .atomic)
        } catch {
            // History is a convenience; a failed write must never block cleaning.
        }
    }

    public func update(_ change: (inout Snapshot) -> Void) {
        var s = load()
        change(&s)
        save(s)
    }
}
