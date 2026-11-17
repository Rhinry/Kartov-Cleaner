import Foundation
import CryptoKit
import Darwin

/// "Kopyalar": files in the full scan whose contents are byte for byte the same. Only the content
/// decides; names never do. One file of every group is always kept, and nothing is picked for the user
/// without being shown.
public struct DuplicateFile: Identifiable, Sendable, Hashable {
    public var id: String { entry.id }
    public let entry: DiskEntry
    /// Bytes only this file holds on disk (not shared with APFS clones). nil when macOS could not tell.
    public let privateBytes: Int64?

    public init(entry: DiskEntry, privateBytes: Int64?) {
        self.entry = entry
        self.privateBytes = privateBytes
    }

    /// A Finder "Duplicate" copy: it shares its blocks, so removing it frees (almost) nothing.
    public var isClone: Bool {
        guard let p = privateBytes else { return false }
        return p * 10 < entry.size
    }

    /// What moving this file to the Trash (and emptying it) would free.
    public var reclaimable: Int64 { isClone ? 0 : (privateBytes ?? entry.size) }
}

public struct DuplicateGroup: Identifiable, Sendable, Hashable {
    /// SHA-256 of the contents, hex.
    public let id: String
    public let size: Int64
    public var files: [DuplicateFile]
    public var suggestedKeep: String

    public init(id: String, size: Int64, files: [DuplicateFile], suggestedKeep: String) {
        self.id = id; self.size = size; self.files = files; self.suggestedKeep = suggestedKeep
    }

    public func reclaimable(keeping keepID: String) -> Int64 {
        files.filter { $0.id != keepID }.reduce(0) { $0 + $1.reclaimable }
    }

    /// The copies worth removing: all but the kept one, clones left out.
    public func suggested(keeping keepID: String) -> [DuplicateFile] {
        files.filter { $0.id != keepID && !$0.isClone }
    }
}

extension Array where Element == DuplicateGroup {
    /// The groups after the given files are gone; groups left with one file drop out.
    /// If the kept file is among them, another one becomes the kept file.
    public func removing(paths: Set<String>, home: URL = Paths().home) -> [DuplicateGroup] {
        compactMap { g in
            var g = g
            g.files.removeAll { paths.contains($0.entry.url.path) }
            guard g.files.count >= 2 else { return nil }
            if !g.files.contains(where: { $0.id == g.suggestedKeep }) {
                g.suggestedKeep = DuplicateFinder(home: home).chooseKeep(g.files.map(\.entry))
            }
            return g
        }
    }
}

public struct DuplicateFinder: Sendable {
    public let home: URL
    static let edgeBytes = 64 * 1024
    static let chunkBytes = 1024 * 1024

    public init(home: URL = Paths().home) {
        self.home = home
    }

    /// Groups of identical files among the entries, biggest saving first.
    public func find(in entries: [DiskEntry], progress: (Int, Int) -> Void = { _, _ in }) -> [DuplicateGroup] {
        let fm = FileManager.default
        // Candidates: plain files only (no apps, no packages or folders), grouped by size.
        var bySize: [Int64: [(DiskEntry, Int64)]] = [:]
        for e in entries where e.kind != .app && e.size > 0 {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: e.url.path, isDirectory: &isDir), !isDir.boolValue,
                  let real = Self.fileSize(e.url) else { continue }
            bySize[real, default: []].append((e, real))
        }
        var sizeGroups: [[DiskEntry]] = []
        for (_, list) in bySize where list.count >= 2 {
            // Hard links are one file under two names.
            var seen = Set<String>()
            let unique = list.map(\.0).filter { e in
                guard let key = Self.inode(e.url) else { return false }
                return seen.insert(key).inserted
            }
            if unique.count >= 2 { sizeGroups.append(unique) }
        }
        let total = sizeGroups.reduce(0) { $0 + $1.count }
        var done = 0
        var groups: [DuplicateGroup] = []
        for candidates in sizeGroups {
            if Task.isCancelled { return [] }
            var byEdge: [String: [DiskEntry]] = [:]
            for e in candidates {
                if let h = Self.edgeHash(e.url) { byEdge[h, default: []].append(e) }
                done += 1
                progress(done, total)
            }
            for (_, same) in byEdge where same.count >= 2 {
                var byFull: [String: [DiskEntry]] = [:]
                for e in same {
                    if Task.isCancelled { return [] }
                    if let h = Self.fullHash(e.url) { byFull[h, default: []].append(e) }
                }
                for (hash, files) in byFull where files.count >= 2 {
                    let dup = files.map { DuplicateFile(entry: $0, privateBytes: Self.privateBytes(of: $0.url)) }
                    groups.append(DuplicateGroup(id: hash, size: files[0].size, files: dup, suggestedKeep: chooseKeep(files)))
                }
            }
        }
        progress(total, total)
        return groups.sorted { $0.reclaimable(keeping: $0.suggestedKeep) > $1.reclaimable(keeping: $1.suggestedKeep) }
    }

    /// The copy to keep: one outside Downloads and Desktop first, then the oldest, then the shortest path.
    public func chooseKeep(_ files: [DiskEntry]) -> String {
        let loose = ["Downloads", "Desktop"].map { home.appendingPathComponent($0).standardizedFileURL.path + "/" }
        func isLoose(_ e: DiskEntry) -> Bool { loose.contains { e.url.standardizedFileURL.path.hasPrefix($0) } }
        let best = files.min { a, b in
            let la = isLoose(a), lb = isLoose(b)
            if la != lb { return !la }
            let da = a.modified ?? .distantFuture, db = b.modified ?? .distantFuture
            if da != db { return da < db }
            return a.url.path.count < b.url.path.count
        }
        return best?.id ?? files.first?.id ?? ""
    }

    /// Bytes not shared with any clone (getattrlist ATTR_CMNEXT_PRIVATESIZE).
    public static func privateBytes(of url: URL) -> Int64? {
        let privateSize: UInt32 = 0x0000_0008        // ATTR_CMNEXT_PRIVATESIZE
        let extended: UInt32 = 0x0000_0020           // FSOPT_ATTR_CMN_EXTENDED
        var al = attrlist(bitmapcount: u_short(ATTR_BIT_MAP_COUNT), reserved: 0, commonattr: 0,
                          volattr: 0, dirattr: 0, fileattr: 0, forkattr: attrgroup_t(privateSize))
        var buf = [UInt8](repeating: 0, count: 16)
        let rc = buf.withUnsafeMutableBytes { getattrlist(url.path, &al, $0.baseAddress, $0.count, extended) }
        guard rc == 0 else { return nil }
        // Packed: 4-byte length, then the off_t.
        return buf.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: Int64.self) }
    }

    // MARK: helpers

    static func fileSize(_ url: URL) -> Int64? {
        var st = stat()
        guard lstat(url.path, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG else { return nil }
        return Int64(st.st_size)
    }

    static func inode(_ url: URL) -> String? {
        var st = stat()
        guard lstat(url.path, &st) == 0 else { return nil }
        return "\(st.st_dev):\(st.st_ino)"
    }

    static func edgeHash(_ url: URL) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        do {
            var sha = SHA256()
            sha.update(data: try h.read(upToCount: edgeBytes) ?? Data())
            let end = try h.seekToEnd()
            if end > UInt64(edgeBytes) {
                try h.seek(toOffset: end - UInt64(edgeBytes))
                sha.update(data: try h.read(upToCount: edgeBytes) ?? Data())
            }
            return hex(sha.finalize())
        } catch { return nil }
    }

    static func fullHash(_ url: URL) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        var sha = SHA256()
        do {
            while true {
                if Task.isCancelled { return nil }
                let chunk = try autoreleasepool { try h.read(upToCount: chunkBytes) }
                guard let chunk, !chunk.isEmpty else { break }
                sha.update(data: chunk)
            }
        } catch { return nil }
        return hex(sha.finalize())
    }

    static func hex(_ d: SHA256.Digest) -> String { d.map { String(format: "%02x", $0) }.joined() }
}
