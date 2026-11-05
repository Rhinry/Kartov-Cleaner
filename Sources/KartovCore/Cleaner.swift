import Foundation

public enum CleanItemStatus: String, Codable, Sendable {
    case deleted, trashed, skipped, failed, restored
}

public struct CleanItemRecord: Codable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var ruleID: String
    public var appKey: String
    public var originalPath: String
    public var trashedPath: String?
    public var size: Int64
    public var status: CleanItemStatus
    public var reason: String?
}

public struct CleanRecord: Codable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var date: Date
    public var items: [CleanItemRecord]
    /// Sum of item sizes that were deleted or trashed (the estimate).
    public var bytesCleaned: Int64
    /// Of which: removed immediately (space already free).
    public var bytesDeleted: Int64
    /// Of which: waiting in the Trash (undoable; space is freed when the Trash is emptied).
    public var bytesInTrash: Int64
    /// Measured change in the volume's free space, when available.
    public var measuredFreed: Int64?
    public var undoneAt: Date?
    /// Done by automatic maintenance rather than by the user.
    public var automatic: Bool?

    public var skippedCount: Int { items.filter { $0.status == .skipped || $0.status == .failed }.count }
    public var canUndo: Bool { undoneAt == nil && items.contains { $0.status == .trashed } }
}

/// Moves things to the Trash, removes them, and puts them back.
public protocol FileRemoving: Sendable {
    func trash(_ url: URL) throws -> URL?
    func remove(_ url: URL) throws
    func restore(from trashed: URL, to original: URL) throws
}

public struct SystemFileRemover: FileRemoving {
    public init() {}

    public func trash(_ url: URL) throws -> URL? {
        #if os(macOS)
        var resulting: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
        return resulting as URL?
        #else
        throw KartovError.trashUnavailable
        #endif
    }

    public func remove(_ url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    public func restore(from trashed: URL, to original: URL) throws {
        try FileManager.default.createDirectory(at: original.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: trashed, to: original)
    }
}

public enum Volume {
    /// Free space on the volume that holds `url`.
    public static func freeBytes(at url: URL) -> Int64? {
        // Real free bytes. (The "important usage" figure already counts purgeable space such as
        // local snapshots as free, so it would hide what a clean actually gained.)
        if let v = try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey]),
           let n = v.volumeAvailableCapacity {
            return Int64(n)
        }
        return nil
    }
}

public struct Cleaner: Sendable {
    public let rules: [String: CleanRule]
    public let policy: SafetyPolicy
    public let remover: FileRemoving
    public let running: RunningAppsProviding

    public init(rules: [CleanRule], paths: Paths = Paths(),
                remover: FileRemoving = SystemFileRemover(),
                running: RunningAppsProviding = NoRunningApps()) {
        var map: [String: CleanRule] = [:]
        for r in rules { map[r.id] = r }
        self.rules = map
        self.policy = SafetyPolicy(paths: paths)
        self.remover = remover
        self.running = running
    }

    /// Cleans the given items. Every item is checked again right before it is touched:
    /// its rule must still match, it must not be a symlink, and its app must not be running.
    public func clean(_ items: [FoundItem], date: Date = Date(),
                      measureAt volumeURL: URL? = nil,
                      onItem: ((Int, Int) -> Void)? = nil) -> CleanRecord {
        let before = volumeURL.flatMap { Volume.freeBytes(at: $0) }
        let runningIDs = running.runningBundleIDs()
        var records: [CleanItemRecord] = []
        var deleted: Int64 = 0, trashed: Int64 = 0

        for (index, item) in items.enumerated() {
            onItem?(index, items.count)
            var rec = CleanItemRecord(id: item.id, ruleID: item.ruleID, appKey: item.appKey,
                                      originalPath: item.url.path, trashedPath: nil,
                                      size: item.size, status: .skipped, reason: nil)
            guard let rule = rules[item.ruleID] else {
                rec.reason = L("Kural bulunamadı")
                records.append(rec); continue
            }
            if item.locked || rule.isBlocked(appBundleID: item.appBundleID, running: runningIDs) {
                rec.reason = L("Uygulama açık")
                records.append(rec); continue
            }
            let verdict = policy.check(item.url, rule: rule)
            guard verdict == .ok else {
                rec.reason = verdict == .missing ? L("Artık yok") : L("Güvenlik kontrolü geçmedi")
                records.append(rec); continue
            }
            do {
                switch rule.mode {
                case .delete:
                    try remover.remove(item.url)
                    rec.status = .deleted
                    deleted += item.size
                case .trash:
                    let out = try remover.trash(item.url)
                    rec.trashedPath = out?.path
                    rec.status = .trashed
                    trashed += item.size
                }
            } catch {
                rec.status = .failed
                rec.reason = error.localizedDescription
            }
            records.append(rec)
        }

        var measured: Int64? = nil
        if let before = before, let url = volumeURL, let after = Volume.freeBytes(at: url) {
            measured = max(0, after - before)
        }
        return CleanRecord(id: UUID(), date: date, items: records,
                           bytesCleaned: deleted + trashed, bytesDeleted: deleted,
                           bytesInTrash: trashed, measuredFreed: measured, undoneAt: nil, automatic: nil)
    }

    /// Puts trashed items back where they were. Deleted caches cannot come back;
    /// apps rebuild them on their own.
    public func undo(_ record: CleanRecord, date: Date = Date()) -> CleanRecord {
        var out = record
        for i in out.items.indices where out.items[i].status == .trashed {
            guard let from = out.items[i].trashedPath else { continue }
            let original = URL(fileURLWithPath: out.items[i].originalPath)
            if FileManager.default.fileExists(atPath: original.path) {
                out.items[i].reason = L("Aynı yerde yeni bir dosya var, geri alınmadı")
                continue
            }
            do {
                try remover.restore(from: URL(fileURLWithPath: from), to: original)
                out.items[i].status = .restored
            } catch {
                out.items[i].reason = error.localizedDescription
            }
        }
        out.undoneAt = date
        return out
    }
}
