import XCTest
@testable import KartovCore

/// One click from the menu bar cleans without asking, so it must never empty the Trash.
final class QuickCleanTests: XCTestCase {
    private func rule(_ id: String, _ group: CategoryGroup, safety: Safety = .safe, mode: CleanMode = .delete) -> CleanRule {
        CleanRule(id: id, name: id, group: group, safety: safety, roots: ["~/x"], itemLevel: .children, mode: mode)
    }

    private lazy var apps = rule("apps", .apps)
    private lazy var logs = rule("logs", .logs)
    private lazy var trash = rule("trash.user", .trash, safety: .caution)
    private lazy var installers = rule("updates.installers", .updates, safety: .caution, mode: .trash)
    private lazy var all = [apps, logs, trash, installers]

    func testNeverTheTrash() {
        let picked = QuickClean.rules(chosen: [apps, trash, installers], all: all, isProtected: { _ in false })
        XCTAssertEqual(picked.map(\.id), ["apps", "updates.installers"])
    }

    func testOnlyTrashChosenCleansNothing() {
        // Not the fallback: the user chose something, it just isn't allowed here.
        XCTAssertTrue(QuickClean.rules(chosen: [trash], all: all, isProtected: { _ in false }).isEmpty)
    }

    func testNothingChosenUsesSafeCaches() {
        let picked = QuickClean.rules(chosen: [], all: all, isProtected: { _ in false })
        XCTAssertEqual(picked.map(\.id), ["apps", "logs"])
        let kept = QuickClean.rules(chosen: [], all: all, isProtected: { $0 == .logs })
        XCTAssertEqual(kept.map(\.id), ["apps"])
    }
}
