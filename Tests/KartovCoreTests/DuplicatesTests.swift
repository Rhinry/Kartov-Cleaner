import XCTest
import Darwin
@testable import KartovCore

final class DuplicatesTests: XCTestCase {
    private var root: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("kartov-dups-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: root)
    }

    private func randomData(_ count: Int = 1_200_000) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        for i in bytes.indices { bytes[i] = UInt8.random(in: 0...255) }
        return Data(bytes)
    }

    @discardableResult
    private func write(_ path: String, _ data: Data, modified: Date? = nil) throws -> URL {
        let url = root.appendingPathComponent(path)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        if let modified { try fm.setAttributes([.modificationDate: modified], ofItemAtPath: url.path) }
        return url
    }

    private func entry(_ url: URL, kind: DiskKind? = nil) -> DiskEntry {
        let v = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return DiskEntry(url: url, name: url.lastPathComponent, kind: kind ?? DiskKind.of(url),
                         size: Int64(v?.fileSize ?? 0), modified: v?.contentModificationDate,
                         lastUsed: nil, bundleID: nil, protected: false)
    }

    private var finder: DuplicateFinder { DuplicateFinder(home: root) }

    func testGroupsIdenticalFiles() throws {
        let d = randomData()
        let a = try write("Documents/a.mov", d)
        let b = try write("Documents/b.mov", d)
        let c = try write("Desktop/c.mov", d)
        let other = try write("Documents/other.mov", randomData())
        let groups = finder.find(in: [a, b, c, other].map { entry($0) })
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(Set(groups[0].files.map(\.entry.url.lastPathComponent)), ["a.mov", "b.mov", "c.mov"])
        XCTAssertEqual(groups[0].files.count, 3)
    }

    func testSameSizeDifferentContentIsNotADuplicate() throws {
        var d = randomData()
        let a = try write("Documents/a.bin", d)
        d[d.count - 1] = d[d.count - 1] &+ 1
        let b = try write("Documents/b.bin", d)
        XCTAssertTrue(finder.find(in: [entry(a), entry(b)]).isEmpty)
    }

    func testHardLinksAreOneFile() throws {
        let a = try write("Documents/a.bin", randomData())
        let b = root.appendingPathComponent("Documents/b.bin")
        XCTAssertEqual(link(a.path, b.path), 0)
        XCTAssertTrue(finder.find(in: [entry(a), entry(b)]).isEmpty)
    }

    func testClonesReclaimNothing() throws {
        let a = try write("Documents/a.bin", randomData())
        let b = root.appendingPathComponent("Documents/b.bin")
        XCTAssertEqual(clonefile(a.path, b.path, 0), 0)
        let groups = finder.find(in: [entry(a), entry(b)])
        XCTAssertEqual(groups.count, 1)
        let clone = try XCTUnwrap(groups[0].files.first { $0.entry.url.lastPathComponent == "b.bin" })
        XCTAssertTrue(clone.isClone)
        XCTAssertEqual(groups[0].reclaimable(keeping: entry(a).id), 0)
    }

    func testSuggestedSkipsClones() throws {
        let d = randomData()
        let a = try write("Documents/a.bin", d)
        let b = root.appendingPathComponent("Documents/b.bin")
        XCTAssertEqual(clonefile(a.path, b.path, 0), 0)
        let c = try write("Documents/c.bin", d)
        let groups = finder.find(in: [entry(a), entry(b), entry(c)])
        XCTAssertEqual(groups.count, 1)
        let suggested = groups[0].suggested(keeping: entry(a).id)
        XCTAssertEqual(suggested.map(\.entry.url.lastPathComponent), ["c.bin"])
        XCTAssertGreaterThan(groups[0].reclaimable(keeping: entry(a).id), 1_000_000)
    }

    func testKeepPrefersOutsideDownloads() throws {
        let d = randomData(2_000_000)
        let old = Date(timeIntervalSince1970: 1_600_000_000)
        let dl = try write("Downloads/a.pdf", d, modified: old)
        let doc = try write("Documents/a.pdf", d)
        XCTAssertEqual(finder.chooseKeep([entry(dl), entry(doc)]), entry(doc).id)

        let newer = try write("Documents/x/b.pdf", d)
        let older = try write("Documents/y/b.pdf", d, modified: old)
        XCTAssertEqual(finder.chooseKeep([entry(newer), entry(older)]), entry(older).id)
    }

    func testRemovingPathsDropsSingletonGroups() throws {
        let d = randomData()
        let a = try write("Documents/a.bin", d)
        let b = try write("Documents/b.bin", d)
        let two = finder.find(in: [entry(a), entry(b)])
        XCTAssertTrue(two.removing(paths: [b.path]).isEmpty)

        let c = try write("Documents/c.bin", d)
        let three = finder.find(in: [entry(a), entry(b), entry(c)])
        XCTAssertEqual(three.removing(paths: [c.path]).first?.files.count, 2)
    }

    func testRemovingTheKeptFilePicksANewOne() throws {
        let d = randomData()
        let a = try write("Documents/a.bin", d, modified: Date(timeIntervalSince1970: 1_600_000_000))
        let b = try write("Documents/b.bin", d)
        let c = try write("Documents/c.bin", d)
        let groups = finder.find(in: [entry(a), entry(b), entry(c)])
        XCTAssertEqual(groups.first?.suggestedKeep, entry(a).id)
        let left = try XCTUnwrap(groups.removing(paths: [a.path]).first)
        XCTAssertTrue(left.files.contains { $0.id == left.suggestedKeep })
        XCTAssertEqual(left.suggested(keeping: left.suggestedKeep).count, 1)
    }

    func testUnreadableFilesAreSkipped() throws {
        let d = randomData()
        let a = try write("Documents/a.bin", d)
        let b = try write("Documents/b.bin", d)
        let gone = entry(try write("Documents/gone.bin", d))
        try fm.removeItem(at: gone.url)
        let groups = finder.find(in: [entry(a), entry(b), gone])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].files.count, 2)
    }

    func testSkipsAppsAndPackages() throws {
        let d = randomData()
        let a = try write("Documents/a.bin", d)
        let app = try write("Documents/b.bin", d)
        let pkg = root.appendingPathComponent("Documents/Sunum.key")
        try fm.createDirectory(at: pkg, withIntermediateDirectories: true)
        try d.write(to: pkg.appendingPathComponent("index"))
        let pkgEntry = DiskEntry(url: pkg, name: "Sunum.key", kind: .document, size: Int64(d.count),
                                 modified: nil, lastUsed: nil, bundleID: nil, protected: false)
        XCTAssertTrue(finder.find(in: [entry(a), entry(app, kind: .app), pkgEntry]).isEmpty)
    }
}
