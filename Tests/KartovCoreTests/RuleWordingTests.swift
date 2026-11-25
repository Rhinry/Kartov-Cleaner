import XCTest
@testable import KartovCore

/// What a found item's row promises must match what cleaning it really does.
final class RuleWordingTests: XCTestCase {
    func testTrashIsNotUndoable() throws {
        let rules = try RuleSet.bundled().rules
        let trash = try XCTUnwrap(rules.first { $0.id == "trash.user" })
        XCTAssertEqual(trash.outcome, .permanentAfterAsking)
        let installers = try XCTUnwrap(rules.first { $0.id == "updates.macos.installers" })
        XCTAssertEqual(installers.outcome, .undoable)
    }

    /// A rule that deletes for good and is not a regenerating cache must ask first.
    func testEveryPermanentNonCacheRuleAsks() throws {
        for r in try RuleSet.bundled().rules where r.safety != .safe && r.mode == .delete {
            XCTAssertEqual(r.confirm, true, r.id)
            XCTAssertEqual(r.outcome, .permanentAfterAsking, r.id)
        }
    }
}
