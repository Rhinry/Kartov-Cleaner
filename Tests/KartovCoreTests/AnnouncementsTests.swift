import XCTest
@testable import KartovCore

final class AnnouncementsTests: XCTestCase {
    private let json = """
    { "announcements": [
      { "id": "a", "title": { "en": "Hello", "tr": "Merhaba" }, "body": { "en": "Body" }, "url": "https://umutkartov.com" },
      { "id": "old", "title": { "en": "Old" }, "body": {}, "expires": "2026-01-01" },
      { "id": "new-only", "title": { "en": "New" }, "body": {}, "minVersion": "0.9" },
      { "id": "", "title": { "en": "No id" }, "body": {} },
      { "id": "bad-link", "title": { "de": "Nur Deutsch" }, "body": {}, "url": "http://example.com" }
    ] }
    """.data(using: .utf8)!

    func testParseAndPick() {
        let all = AnnouncementFeed.parse(json)
        XCTAssertEqual(all.map(\.id), ["a", "old", "new-only", "bad-link"])
        XCTAssertEqual(all[0].title(in: "tr"), "Merhaba")
        XCTAssertEqual(all[0].title(in: "es"), "Hello")
        XCTAssertEqual(all[0].body(in: "tr"), "Body")
        XCTAssertEqual(all[3].title(in: "tr"), "Nur Deutsch")
        XCTAssertNotNil(all[0].link)
        XCTAssertNil(all[3].link)
        XCTAssertTrue(AnnouncementFeed.parse(Data("not json".utf8)).isEmpty)
    }

    func testWhatToShow() {
        let all = AnnouncementFeed.parse(json)
        let now = ISO8601DateFormatter().date(from: "2026-11-16T10:00:00Z")!
        let shown = AnnouncementFeed.toShow(all, seen: [], version: "0.8.1", language: "tr", now: now)
        XCTAssertEqual(shown.map(\.id), ["a", "bad-link"])
        XCTAssertEqual(AnnouncementFeed.toShow(all, seen: ["a"], version: "0.8.1", language: "tr", now: now).map(\.id), ["bad-link"])
        XCTAssertEqual(AnnouncementFeed.toShow(all, seen: [], version: "0.9", language: "tr", now: now, limit: 5).map(\.id),
                       ["a", "new-only", "bad-link"])
    }

    func testNotesDisplay() {
        let notes = "## Kartov Cleaner 0.8.1\n\n- **Projects:** new tab\n  - sub item\n### Fixes\n- one\n\n\nInstall: drag it."
        XCTAssertEqual(ReleaseNotes.display(notes),
                       "• **Projects:** new tab\n    • sub item\n**Fixes**\n• one\n\nInstall: drag it.")
    }

    func testExpiryIsInclusive() {
        let a = Announcement(id: "x", title: ["en": "x"], body: [:], expires: "2026-11-16")
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"
        XCTAssertTrue(a.isActive(version: "1", now: f.date(from: "2026-11-16 23:00")!))
        XCTAssertFalse(a.isActive(version: "1", now: f.date(from: "2026-11-17 00:30")!))
    }
}
