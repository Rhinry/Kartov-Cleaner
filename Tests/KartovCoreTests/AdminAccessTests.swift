import XCTest
@testable import KartovCore

final class AdminAccessTests: XCTestCase {
    private func run(_ tool: String, _ args: [String]) -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = out
        try? p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    private func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("kartov-admin-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testUserNames() {
        XCTAssertTrue(AdminAccessFiles.isValidUser("kartov"))
        XCTAssertTrue(AdminAccessFiles.isValidUser("umut.kartov_2"))
        for bad in ["", "root", "a b", "x;rm", "\"q\"", "ALL", "-n", String(repeating: "a", count: 40)] {
            XCTAssertFalse(AdminAccessFiles.isValidUser(bad), bad)
        }
        XCTAssertNil(AdminAccessFiles.installScript(user: "x;rm"))
    }

    func testSudoersRulePassesVisudo() throws {
        let file = try tempDir().appendingPathComponent("rule")
        try AdminAccessFiles.sudoersRule(user: "kartov").write(to: file, atomically: true, encoding: .utf8)
        let r = run("/usr/sbin/visudo", ["-cf", file.path])
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertTrue(AdminAccessFiles.sudoersRule(user: "kartov")
            .contains("kartov ALL=(root) NOPASSWD: /Library/PrivilegedHelperTools/kartov-admin"))
    }

    func testHelperOnlyKnowsItsOwnTasks() throws {
        let file = try tempDir().appendingPathComponent("kartov-admin")
        try AdminAccessFiles.helperScript.write(to: file, atomically: true, encoding: .utf8)
        XCTAssertEqual(run("/bin/sh", ["-n", file.path]).status, 0)
        XCTAssertEqual(run("/bin/sh", [file.path, "check"]).status, 0)
        for bad in ["", "rm", "memory2", "/bin/sh", "check; id"] {
            XCTAssertEqual(run("/bin/sh", [file.path, bad]).status, 64, bad)
        }
        XCTAssertEqual(Set(AdminTask.allCases.map(\.rawValue)), ["memory", "dns", "snapshots", "installdata"])
        for task in AdminTask.allCases {
            XCTAssertTrue(AdminAccessFiles.helperScript.contains("  \(task.rawValue))"), task.rawValue)
        }
    }

    /// Runs the real install and remove steps inside a temporary folder (without changing owners).
    func testInstallAndRemoveInAFolder() throws {
        let root = try tempDir()
        let script = try XCTUnwrap(AdminAccessFiles.installScript(user: "kartov", root: root.path, setOwner: false))
        // It travels inside an AppleScript string: no quotes or backslashes allowed.
        XCTAssertFalse(script.contains("\"") || script.contains("\\"))
        let r = run("/bin/sh", ["-c", script])
        XCTAssertEqual(r.status, 0, r.output)
        let helper = root.appendingPathComponent("Library/PrivilegedHelperTools/kartov-admin")
        let rule = root.appendingPathComponent("etc/sudoers.d/kartov-cleaner")
        XCTAssertEqual(try String(contentsOf: helper, encoding: .utf8), AdminAccessFiles.helperScript)
        XCTAssertEqual(try String(contentsOf: rule, encoding: .utf8), AdminAccessFiles.sudoersRule(user: "kartov"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: rule.path + ".tmp"))
        let attrs = try FileManager.default.attributesOfItem(atPath: rule.path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o440)

        XCTAssertEqual(run("/bin/sh", ["-c", AdminAccessFiles.removeScript(root: root.path)]).status, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: helper.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: rule.path))
    }

    func testProductionScriptsUseSystemPaths() throws {
        let script = try XCTUnwrap(AdminAccessFiles.installScript(user: "kartov"))
        XCTAssertTrue(script.contains("/usr/sbin/visudo -cf /etc/sudoers.d/kartov-cleaner.tmp"))
        XCTAssertTrue(script.contains("/usr/sbin/chown root:wheel"))
        XCTAssertEqual(AdminAccessFiles.removeScript(),
                       "/bin/rm -f /etc/sudoers.d/kartov-cleaner /Library/PrivilegedHelperTools/kartov-admin")
    }
}
