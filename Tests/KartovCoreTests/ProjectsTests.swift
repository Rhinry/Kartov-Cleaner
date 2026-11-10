import XCTest
@testable import KartovCore

final class ProjectsTests: XCTestCase {
    final class TrashSpy: FileRemoving, @unchecked Sendable {
        var trashed: [String] = []
        func trash(_ url: URL) throws -> URL? { trashed.append(url.lastPathComponent); return nil }
        func remove(_ url: URL) throws {}
        func restore(from trashed: URL, to original: URL) throws {}
    }

    private func makeTree() throws -> URL {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("kartov-projects-\(UUID().uuidString)")
        func file(_ path: String, bytes: Int = 4096) throws {
            let url = root.appendingPathComponent(path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 1, count: bytes).write(to: url)
        }
        // A real project folder with caches next to the project file and deeper.
        try file("Reklam/Reklam.prproj")
        try file("Reklam/Adobe Premiere Pro Video Previews/a.mxf", bytes: 20_000)
        try file("Reklam/Adobe Premiere Pro Auto-Save/Reklam-1.prproj")
        try file("Reklam/Footage/Proxies/clip_Proxy.mov", bytes: 9000)
        try file("Reklam/Footage/clip.mov", bytes: 50_000)
        try file("Reklam/Footage/clip.wav.pek")
        // A project nested inside another owns its own subtree.
        try file("Reklam/AE/Logo.aep")
        try file("Reklam/AE/Adobe After Effects Auto-Save/Logo auto-save 1.aep")
        try file("Reklam/AE/tmpAEtoAMEProject-Logo1.aep")
        // A project file lying loose in the root: only folders with the program's name count.
        try file("Tek.aep")
        try file("Adobe After Effects Auto-Save/Tek auto-save 1.aep")
        try file("Proxies/someone-elses.mov")
        // Caches with no project anywhere near are ignored.
        try file("Baska/Proxies/x.mov")
        return root
    }

    func testFindsProjectsAndTheirCaches() throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let found = ProjectScanner().scan(roots: [root])
        let byName = Dictionary(uniqueKeysWithValues: found.map { ($0.name, $0) })
        XCTAssertEqual(Set(byName.keys), ["Reklam", "AE", root.lastPathComponent])

        let reklam = try XCTUnwrap(byName["Reklam"])
        XCTAssertEqual(reklam.apps, [.premiere])
        XCTAssertEqual(Set(reklam.kinds), [.previews, .autoSave, .proxies, .mediaCache])
        XCTAssertFalse(reklam.items.contains { $0.url.lastPathComponent == "clip.mov" })
        XCTAssertGreaterThan(reklam.regenerableBytes, 0)

        let ae = try XCTUnwrap(byName["AE"])
        XCTAssertEqual(ae.apps, [.afterEffects])
        XCTAssertEqual(Set(ae.kinds), [.autoSave, .renderTemp])
        XCTAssertEqual(ae.projectFiles, ["Logo.aep"])

        let loose = try XCTUnwrap(byName[root.lastPathComponent])
        XCTAssertEqual(loose.kinds, [.autoSave])
    }

    func testIdleDays() {
        let now = Date()
        let p = ProjectInfo(folder: URL(fileURLWithPath: "/tmp/x"), name: "x", apps: [.premiere], projectFiles: ["x.prproj"],
                            lastModified: now.addingTimeInterval(-61 * 86_400), items: [])
        XCTAssertEqual(p.idleDays(now: now), 61)
    }

    func testRemoverOnlyTakesCachesInsideTheRoots() throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let spy = TrashSpy()
        let remover = ProjectCacheRemover(roots: [root], remover: spy)
        let previews = ProjectCacheItem(url: root.appendingPathComponent("Reklam/Adobe Premiere Pro Video Previews"), kind: .previews, size: 10)
        let media = ProjectCacheItem(url: root.appendingPathComponent("Reklam/Footage/clip.mov"), kind: .mediaCache, size: 10)
        let project = ProjectCacheItem(url: root.appendingPathComponent("Reklam/Reklam.prproj"), kind: .renderTemp, size: 10)
        let outside = ProjectCacheItem(url: URL(fileURLWithPath: "/Library/Proxies"), kind: .proxies, size: 10)
        let gone = ProjectCacheItem(url: root.appendingPathComponent("Reklam/Proxies"), kind: .proxies, size: 10)
        XCTAssertTrue(remover.canRemove(previews))
        XCTAssertFalse(remover.canRemove(media))
        XCTAssertFalse(remover.canRemove(project))
        XCTAssertFalse(remover.canRemove(outside))
        XCTAssertFalse(remover.canRemove(gone))

        let record = remover.trash([previews, media, project].map { ProjectPick(project: "Reklam", item: $0) })
        XCTAssertEqual(spy.trashed, ["Adobe Premiere Pro Video Previews"])
        XCTAssertEqual(record.bytesInTrash, 10)
        XCTAssertEqual(record.items.filter { $0.status == .skipped }.count, 2)
        XCTAssertEqual(record.items.first?.ruleID, "projects.previews")
    }

    func testWeeklyDigest() {
        let now = Date()
        let gb: Int64 = 1_000_000_000
        let samples = (0..<8).map { d in DiskSample(date: now.addingTimeInterval(Double(d - 7) * 86_400), used: (40 + Int64(d)) * gb, total: 100 * gb) }
        XCTAssertEqual(WeeklyDigest.diskChange(samples, now: now), 7 * gb)
        XCTAssertNil(WeeklyDigest.diskChange(Array(samples.suffix(2)), now: now))

        let digest = WeeklyDigest(diskDelta: 7 * gb, cleaned: 2 * gb, alerts: 1, crashes: 3, idleProjects: 2, idleProjectBytes: 5 * gb)
        let text = digest.text { "\($0 / gb) GB" }
        XCTAssertTrue(text.contains("7 GB"))
        XCTAssertTrue(text.contains("2 GB"))
        XCTAssertTrue(text.contains("5 GB"))
    }
}
