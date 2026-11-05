import XCTest
@testable import KartovCore

final class InsightsTests: XCTestCase {
    func testForecastNeedsHistory() {
        let now = Date()
        let s = [DiskSample(date: now.addingTimeInterval(-3600), used: 100, total: 1000),
                 DiskSample(date: now, used: 110, total: 1000)]
        if case .collecting = StorageForecast.make(s, now: now).kind {} else { XCTFail("expected collecting") }
    }

    func testForecastFillsAtSteadyGrowth() {
        let now = Date()
        let gb: Int64 = 1_000_000_000
        // 1 GB a day on a 100 GB disk that is 50 GB used: 98 - 50 = 48 days left.
        let s = (0..<10).map { d in DiskSample(date: now.addingTimeInterval(Double(d - 9) * 86_400), used: (41 + Int64(d)) * gb, total: 100 * gb) }
        let f = StorageForecast.make(s, now: now)
        guard case .fills(let days) = f.kind else { return XCTFail("expected fills, got \(f.kind)") }
        XCTAssertEqual(days, 48, accuracy: 0.5)
    }

    func testForecastSteadyWhenFlat() {
        let now = Date()
        let s = (0..<6).map { d in DiskSample(date: now.addingTimeInterval(Double(d - 5) * 86_400), used: 50_000_000_000, total: 100_000_000_000) }
        XCTAssertEqual(StorageForecast.make(s, now: now).kind, .steady)
    }

    func testCrashFileNames() {
        XCTAssertEqual(CrashReportParser.appName(fromFileName: "Google Chrome_2026-11-04-101522_MacBook.ips"), "Google Chrome")
        XCTAssertEqual(CrashReportParser.appName(fromFileName: "Slack-2026-11-04-101522.ips"), "Slack")
        XCTAssertEqual(CrashReportParser.kindFor(bugType: "", fileName: "x.cpu_resource.diag"), .resource)
        XCTAssertEqual(CrashReportParser.kindFor(bugType: "309", fileName: "x.ips"), .crash)
    }

    func testParsesIPS() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("kartov-ips-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("Demo_2026-11-04-101522_Mac.ips")
        let text = #"{"app_name":"Demo","bundleID":"com.example.demo","app_version":"2.1","bug_type":"309","timestamp":"2026-11-04 10:15:22.00 +0300"}"# + "\n" +
            #"{"exception":{"type":"EXC_BAD_ACCESS","signal":"SIGSEGV"}}"#
        try text.write(to: url, atomically: true, encoding: .utf8)
        let r = try XCTUnwrap(CrashReportParser.parse(url, modified: Date()))
        XCTAssertEqual(r.app, "Demo")
        XCTAssertEqual(r.bundleID, "com.example.demo")
        XCTAssertEqual(r.kind, .crash)
        XCTAssertEqual(r.reason, "EXC_BAD_ACCESS (SIGSEGV)")
    }

    func testFootprintMatchesOnlyExactNames() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("kartov-fp-\(UUID().uuidString)")
        let fm = FileManager.default
        defer { try? fm.removeItem(at: home) }
        let lib = home.appendingPathComponent("Library")
        try fm.createDirectory(at: lib.appendingPathComponent("Caches/com.example.demo"), withIntermediateDirectories: true)
        try fm.createDirectory(at: lib.appendingPathComponent("Caches/com.example.demo2"), withIntermediateDirectories: true)
        try fm.createDirectory(at: lib.appendingPathComponent("Preferences"), withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: lib.appendingPathComponent("Preferences/com.example.demo.plist"))
        let nodes = AppFootprint.scan(bundleID: "com.example.demo", appName: "Demo App", home: home)
        XCTAssertEqual(Set(nodes.map(\.kind)), [.cache, .preferences])
        XCTAssertEqual(nodes.first { $0.kind == .cache }?.urls.count, 1)
        XCTAssertTrue(AppFootprint.scan(bundleID: "com.apple.Safari", appName: "Safari", home: home).isEmpty)
    }
}
