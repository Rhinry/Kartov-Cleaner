import XCTest
@testable import KartovCore

/// Every test works inside a throwaway fake home folder. Nothing outside it is read or touched.
final class KartovCoreTests: XCTestCase {
    var home: URL!
    var paths: Paths!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("kartov-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let tmp = home.appendingPathComponent("tmp", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        paths = Paths(home: home, temp: tmp)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    // MARK: helpers

    @discardableResult
    func makeFile(_ relative: String, bytes: Int = 4096, age days: Double = 0) throws -> URL {
        let url = home.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 7, count: bytes).write(to: url)
        if days > 0 {
            let date = Date().addingTimeInterval(-days * 86_400)
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        }
        return url
    }

    func cachesRule(exclude: [String]? = nil, mode: CleanMode = .delete) -> CleanRule {
        CleanRule(id: "user.caches", name: "Uygulama önbellekleri", group: .apps, safety: .safe,
                  roots: ["~/Library/Caches"], itemLevel: .children, exclude: exclude,
                  childIsBundleID: true, mode: mode)
    }

    func scan(_ rules: [CleanRule], running: Set<String> = []) -> [FoundItem] {
        struct R: RunningAppsProviding { let ids: Set<String>; func runningBundleIDs() -> Set<String> { ids } }
        var items: [FoundItem] = []
        CacheScanner(rules: rules, paths: paths, running: R(ids: running)).run { event in
            if case .found(let item) = event { items.append(item) }
        }
        return items
    }

    /// Records calls instead of using the real Trash.
    final class FakeRemover: FileRemoving, @unchecked Sendable {
        let trashDir: URL
        init(trashDir: URL) { self.trashDir = trashDir }
        func trash(_ url: URL) throws -> URL? {
            try FileManager.default.createDirectory(at: trashDir, withIntermediateDirectories: true)
            let dest = trashDir.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: dest)
            return dest
        }
        func remove(_ url: URL) throws { try FileManager.default.removeItem(at: url) }
        func restore(from trashed: URL, to original: URL) throws {
            try FileManager.default.moveItem(at: trashed, to: original)
        }
    }

    // MARK: rules

    func testBundledRulesLoadAndPassSafetyReview() throws {
        let set = try RuleSet.bundled()
        XCTAssertFalse(set.rules.isEmpty)
        XCTAssertEqual(Set(set.rules.map(\.id)).count, set.rules.count, "rule ids must be unique")
        let policy = SafetyPolicy(paths: paths)
        for rule in set.rules {
            for root in rule.roots {
                let p = paths.expand(root).path
                if rule.itemLevel == .root {
                    XCTAssertFalse(policy.forbidden.contains(p), "\(rule.id) would clean a forbidden folder: \(p)")
                }
                XCTAssertNotEqual(p, home.path, "\(rule.id) targets the home folder")
                if !rule.group.isUserData {
                    XCTAssertFalse(p.hasPrefix(home.path + "/Documents"), "\(rule.id) reaches into Documents")
                    XCTAssertFalse(p.hasPrefix(home.path + "/Desktop"), "\(rule.id) reaches into Desktop")
                }
                XCTAssertFalse(p.hasPrefix(home.path + "/Library/Mobile Documents"), "\(rule.id) reaches into iCloud Drive")
            }
            if rule.safety == .caution && rule.confirm != true {
                XCTAssertEqual(rule.mode, .trash, "\(rule.id): caution rules must go to the Trash")
            }
            if rule.mode == .delete && rule.safety == .caution {
                XCTAssertEqual(rule.confirm, true, "\(rule.id): permanent deletion of user-adjacent data needs confirmation")
            }
            if rule.group.isUserData {
                XCTAssertFalse(rule.defaultOn, "\(rule.id): the user's own files are never preselected")
                XCTAssertEqual(rule.mode, .trash, "\(rule.id): the user's own files always go to the Trash")
            }
            if rule.group == .privacy {
                if rule.id.contains("cookies") { XCTAssertFalse(rule.defaultOn, "\(rule.id): cookies are opt-in") }
                XCTAssertTrue(rule.confirm == true || !rule.defaultOn, "\(rule.id): history is cleaned only after a warning")
                XCTAssertEqual(rule.mode, .trash, "\(rule.id): history and cookies go to the Trash")
            }
        }
    }

    func testWildcard() {
        XCTAssertTrue(Wildcard.matches(pattern: "com.apple.*", "com.apple.Safari"))
        XCTAssertFalse(Wildcard.matches(pattern: "com.apple.*", "com.spotify.client"))
        XCTAssertTrue(Wildcard.matches(pattern: "Install macOS*.app", "Install macOS Sequoia.app"))
        XCTAssertFalse(Wildcard.matches(pattern: "Install macOS*.app", "Install macOS Sequoia.zip"))
        XCTAssertTrue(Wildcard.matches(pattern: "*.ipsw", "iPhone_17_Restore.ipsw"))
        XCTAssertTrue(Wildcard.matches(pattern: "Adobe", "Adobe"))
        XCTAssertFalse(Wildcard.matches(pattern: "Adobe", "AdobeX"))
    }

    // MARK: scanning

    func testScanFindsEachAppCacheAndMeasuresIt() throws {
        try makeFile("Library/Caches/com.spotify.client/a.bin", bytes: 50_000)
        try makeFile("Library/Caches/com.spotify.client/sub/b.bin", bytes: 50_000)
        try makeFile("Library/Caches/com.tinyspeck.slackmacgap/c.bin", bytes: 20_000)
        try makeFile("Library/Caches/com.apple.something/d.bin", bytes: 20_000)

        let items = scan([cachesRule(exclude: ["com.apple.*"])])
        XCTAssertEqual(Set(items.map(\.appKey)), ["com.spotify.client", "com.tinyspeck.slackmacgap"])
        let spotify = try XCTUnwrap(items.first { $0.appKey == "com.spotify.client" })
        XCTAssertEqual(spotify.fileCount, 2)
        XCTAssertGreaterThanOrEqual(spotify.size, 100_000)
    }

    func testScanReportsEveryLocation() throws {
        try makeFile("Library/Caches/com.example.app/a.bin")
        let missing = CleanRule(id: "missing", name: "Yok", group: .apps, safety: .safe,
                                roots: ["~/Library/NotThere"], itemLevel: .children)
        var started: [String] = [], finished: [String] = [], skipped: [String: SkipReason] = [:]
        var sawProgressPath = false
        CacheScanner(rules: [cachesRule(), missing], paths: paths).run { e in
            switch e {
            case .locationStarted(let id): started.append(id)
            case .locationFinished(let id, _, _): finished.append(id)
            case .locationSkipped(let id, let r): skipped[id] = r
            case .progress(_, let p, _): if p.contains("com.example.app") { sawProgressPath = true }
            default: break
            }
        }
        XCTAssertEqual(started, ["user.caches", "missing"])
        XCTAssertEqual(finished, ["user.caches"])
        XCTAssertEqual(skipped["missing"], .notFound)
        XCTAssertTrue(sawProgressPath, "scan screen must be told which folder is being read")
    }

    func testMinimumAgeKeepsRecentLogs() throws {
        try makeFile("Library/Logs/OldApp/old.log", age: 30)
        try makeFile("Library/Logs/NewApp/new.log", age: 1)
        let logs = CleanRule(id: "logs.user", name: "Loglar", group: .logs, safety: .safe,
                             roots: ["~/Library/Logs"], itemLevel: .children, minAgeDays: 7)
        XCTAssertEqual(scan([logs]).map(\.name), ["OldApp"])
    }

    func testRunningAppLocksItsCache() throws {
        try makeFile("Library/Caches/com.spotify.client/a.bin")
        let items = scan([cachesRule()], running: ["com.spotify.client"])
        XCTAssertEqual(items.first?.locked, true)
    }

    func testIncludeFilterOnlyMatchesInstallers() throws {
        try makeFile("Apps/Install macOS Sequoia.app/Contents/x", bytes: 10_000)
        try makeFile("Apps/Final Cut Pro.app/Contents/x", bytes: 10_000)
        let rule = CleanRule(id: "updates.macos.installers", name: "Yükleyiciler", group: .updates,
                             safety: .caution, roots: ["~/Apps"], itemLevel: .children,
                             include: ["Install macOS*.app"], mode: .trash)
        XCTAssertEqual(scan([rule]).map(\.name), ["Install macOS Sequoia.app"])
    }

    // MARK: safety

    func testSafetyRejectsForbiddenAndUnrelatedPaths() throws {
        let policy = SafetyPolicy(paths: paths)
        let rule = cachesRule()
        try makeFile("Documents/thesis.docx")
        try makeFile("Library/Caches/com.ok.app/a.bin")
        XCTAssertEqual(policy.check(home.appendingPathComponent("Documents/thesis.docx"), rule: rule), .forbidden)
        XCTAssertEqual(policy.check(home, rule: rule), .forbidden)
        XCTAssertEqual(policy.check(home.appendingPathComponent("Library/Caches"), rule: rule), .forbidden)
        XCTAssertEqual(policy.check(home.appendingPathComponent("Library/Caches/com.ok.app/a.bin"), rule: rule),
                       .notMatchingRule, "only immediate children of a root are items")
        XCTAssertEqual(policy.check(home.appendingPathComponent("Library/Caches/com.ok.app"), rule: rule), .ok)
        XCTAssertEqual(policy.check(home.appendingPathComponent("Library/Caches/../Caches/com.ok.app"), rule: rule), .ok)
    }

    func testSafetyRejectsSymlinksIntoUserFiles() throws {
        let precious = try makeFile("Documents/Projects/final.aep", bytes: 1000)
        let caches = home.appendingPathComponent("Library/Caches", isDirectory: true)
        try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        let link = caches.appendingPathComponent("com.evil.link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: precious.deletingLastPathComponent())

        let policy = SafetyPolicy(paths: paths)
        XCTAssertEqual(policy.check(link, rule: cachesRule()), .symlink)
        XCTAssertTrue(scan([cachesRule()]).isEmpty, "a symlinked cache folder must not even be listed")

        let fake = FoundItem(ruleID: "user.caches", url: link, name: "com.evil.link", appKey: "com.evil.link",
                             size: 1000, fileCount: 1, newestModification: nil, locked: false)
        let record = Cleaner(rules: [cachesRule()], paths: paths).clean([fake])
        XCTAssertEqual(record.items.first?.status, .skipped)
        XCTAssertTrue(FileManager.default.fileExists(atPath: precious.path), "the real file must survive")
    }

    // MARK: cleaning and undo

    func testDeleteRemovesCacheAndRecordsBytes() throws {
        try makeFile("Library/Caches/com.spotify.client/a.bin", bytes: 30_000)
        let items = scan([cachesRule()])
        let record = Cleaner(rules: [cachesRule()], paths: paths).clean(items)
        XCTAssertEqual(record.items.first?.status, .deleted)
        XCTAssertEqual(record.bytesDeleted, items[0].size)
        XCTAssertEqual(record.bytesInTrash, 0)
        XCTAssertFalse(record.canUndo)
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent("Library/Caches/com.spotify.client").path))
    }

    func testCleanerSkipsLockedAndRunningApps() throws {
        try makeFile("Library/Caches/com.spotify.client/a.bin")
        struct R: RunningAppsProviding { func runningBundleIDs() -> Set<String> { ["com.spotify.client"] } }
        let items = scan([cachesRule()]) // scanned while closed
        let record = Cleaner(rules: [cachesRule()], paths: paths, running: R()).clean(items) // opened before cleaning
        XCTAssertEqual(record.items.first?.status, .skipped)
        XCTAssertEqual(record.items.first?.reason, "Uygulama açık")
        XCTAssertTrue(FileManager.default.fileExists(atPath: items[0].url.path))
    }

    func testTrashAndUndoRestoresOriginal() throws {
        let file = try makeFile("Library/iTunes/iPhone Software Updates/iPhone_Restore.ipsw", bytes: 80_000)
        let rule = CleanRule(id: "updates.ios.ipsw", name: "IPSW", group: .updates, safety: .caution,
                             roots: ["~/Library/iTunes/iPhone Software Updates"], itemLevel: .children,
                             include: ["*.ipsw"], mode: .trash)
        let remover = FakeRemover(trashDir: home.appendingPathComponent(".FakeTrash"))
        let cleaner = Cleaner(rules: [rule], paths: paths, remover: remover)
        let record = cleaner.clean(scan([rule]))
        XCTAssertEqual(record.items.first?.status, .trashed)
        XCTAssertTrue(record.canUndo)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))

        let undone = cleaner.undo(record)
        XCTAssertEqual(undone.items.first?.status, .restored)
        XCTAssertNotNil(undone.undoneAt)
        XCTAssertFalse(undone.canUndo)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    // MARK: wider coverage

    func testGlobRootsGiveOneRowPerApp() throws {
        try makeFile("Library/Containers/com.tdesktop.Telegram/Data/Library/Caches/a.bin", bytes: 30_000)
        try makeFile("Library/Containers/net.whatsapp.WhatsApp/Data/Library/Caches/b.bin", bytes: 20_000)
        try makeFile("Library/Containers/net.whatsapp.WhatsApp/Data/Documents/chat.db", bytes: 20_000)
        let rule = CleanRule(id: "apps.sandbox.caches", name: "Önbellek", group: .apps, safety: .safe,
                             roots: ["~/Library/Containers/*/Data/Library/Caches"], itemLevel: .root,
                             appKeyFromGlob: true, appKeyIsBundleID: true)
        let items = scan([rule], running: ["com.tdesktop.Telegram"])
        XCTAssertEqual(Set(items.map(\.appKey)), ["com.tdesktop.Telegram", "net.whatsapp.WhatsApp"])
        XCTAssertTrue(items.allSatisfy { $0.url.lastPathComponent == "Caches" }, "only the Caches folder, never Documents")
        XCTAssertEqual(items.first { $0.appKey == "com.tdesktop.Telegram" }?.locked, true, "a running app's cache is locked")
    }

    func testOverlappingRulesNeverCountTwice() throws {
        try makeFile("Library/Caches/Google/Chrome/x.bin", bytes: 10_000)
        try makeFile("Library/Caches/Google/AndroidStudio/y.bin", bytes: 10_000)
        let chrome = CleanRule(id: "browser.chrome", name: "Önbellek", group: .browsers, safety: .safe,
                               roots: ["~/Library/Caches/Google/Chrome"], itemLevel: .root, appGroup: "Google Chrome")
        let google = CleanRule(id: "dev.google.caches", name: "Google", group: .developer, safety: .safe,
                               roots: ["~/Library/Caches/Google"], itemLevel: .children)
        let items = scan([chrome, google])
        XCTAssertEqual(items.map(\.name).sorted(), ["AndroidStudio", "Chrome"])
    }

    func testLargeFilesSkipPackagesAndHiddenFolders() throws {
        try makeFile("Movies/render_final.mov", bytes: 3_000_000)
        try makeFile("Movies/small.mov", bytes: 100_000)
        try makeFile("Pictures/Photos Library.photoslibrary/originals/IMG.heic", bytes: 3_000_000)
        try makeFile("Movies/Edit.fcpbundle/Render Files/r.mov", bytes: 3_000_000)
        try makeFile("Documents/.hidden/big.bin", bytes: 3_000_000)
        let rule = CleanRule(id: "user.largefiles", name: "Büyük", group: .userFiles, safety: .caution,
                             roots: ["~/Movies", "~/Pictures", "~/Documents"], itemLevel: .largeFiles,
                             minSizeMB: 1, defaultOn: false, mode: .trash)
        let items = scan([rule])
        XCTAssertEqual(items.map(\.name), ["render_final.mov"])
        XCTAssertEqual(items.first?.appKey, items.first?.url.path, "each user file is its own row")
    }

    func testPersonalFoldersOnlyForOfferRules() throws {
        let old = try makeFile("Downloads/old-video.mp4", bytes: 5000, age: 60)
        let policy = SafetyPolicy(paths: paths)
        let offer = CleanRule(id: "user.downloads.old", name: "Eski", group: .userFiles, safety: .caution,
                              roots: ["~/Downloads"], itemLevel: .children, minAgeDays: 30, defaultOn: false, mode: .trash)
        let greedy = CleanRule(id: "bad", name: "Kötü", group: .apps, safety: .safe,
                               roots: ["~/Downloads"], itemLevel: .children, defaultOn: true, mode: .delete)
        XCTAssertEqual(policy.check(old, rule: offer), .ok)
        XCTAssertEqual(policy.check(old, rule: greedy), .forbidden, "a preselected or permanent rule can never reach personal folders")
        XCTAssertTrue(scan([greedy]).isEmpty)
    }

    func testICloudDriveIsNeverReachable() throws {
        let doc = try makeFile("Library/Mobile Documents/com~apple~CloudDocs/big.mov", bytes: 3_000_000)
        let rule = CleanRule(id: "user.largefiles", name: "Büyük", group: .userFiles, safety: .caution,
                             roots: ["~/Library/Mobile Documents"], itemLevel: .largeFiles,
                             minSizeMB: 1, defaultOn: false, mode: .trash)
        XCTAssertEqual(SafetyPolicy(paths: paths).check(doc, rule: rule), .forbidden)
        XCTAssertTrue(scan([rule]).isEmpty)
    }

    func testTempDirectoryExpansion() throws {
        try makeFile("tmp/stale-export/x.bin", bytes: 5000, age: 10)
        try makeFile("tmp/fresh/x.bin", bytes: 5000)
        let rule = CleanRule(id: "temp.user", name: "Geçici", group: .logs, safety: .safe,
                             roots: ["$TMPDIR"], itemLevel: .children, minAgeDays: 3)
        XCTAssertEqual(scan([rule]).map(\.name), ["stale-export"])
    }

    // MARK: full scan

    func testFullScanListsFilesByKindAndSkipsLibraries() throws {
        try makeFile("Movies/trip.mov", bytes: 3_000_000)
        try makeFile("Pictures/photo.HEIC", bytes: 2_000_000)
        try makeFile("Downloads/setup.dmg", bytes: 2_000_000)
        try makeFile("Documents/tiny.txt", bytes: 100)
        try makeFile("Pictures/Photos Library.photoslibrary/originals/a.heic", bytes: 2_000_000)
        let result = DiskAnalyzer(paths: paths, minimumListedBytes: 1_000_000).run { _, _ in }
        let byName = Dictionary(uniqueKeysWithValues: result.entries.filter { $0.kind != .app }.map { ($0.name, $0) })
        XCTAssertEqual(byName["trip.mov"]?.kind, .video)
        XCTAssertEqual(byName["photo.HEIC"]?.kind, .image)
        XCTAssertEqual(byName["setup.dmg"]?.kind, .archive)
        XCTAssertNil(byName["tiny.txt"], "small files are counted, not listed")
        XCTAssertNil(byName["a.heic"], "never list files inside a photo library")
        XCTAssertEqual(byName["Photos Library.photoslibrary"]?.protected, true)
    }

    func testFullScanRemovalRules() throws {
        let movie = try makeFile("Movies/trip.mov", bytes: 1000)
        let lib = try makeFile("Library/Preferences/x.plist", bytes: 10)
        let icloud = try makeFile("Library/Mobile Documents/com~apple~CloudDocs/doc.pdf", bytes: 10)
        let photos = home.appendingPathComponent("Pictures/Photos Library.photoslibrary")
        try FileManager.default.createDirectory(at: photos, withIntermediateDirectories: true)
        let r = DiskRemover(paths: paths)
        XCTAssertTrue(r.canRemove(movie))
        XCTAssertFalse(r.canRemove(lib), "Library is never removed from the full scan")
        XCTAssertFalse(r.canRemove(icloud))
        XCTAssertFalse(r.canRemove(photos), "photo libraries are managed by Photos")
        XCTAssertFalse(r.canRemove(home))
    }

    func testFullScanTrashAndLeftovers() throws {
        let movie = try makeFile("Movies/trip.mov", bytes: 5000)
        try makeFile("Library/Caches/com.example.editor/c.bin", bytes: 100)
        try makeFile("Library/Preferences/com.example.editor.plist", bytes: 100)
        try makeFile("Library/Caches/com.example.editorpro/keep.bin", bytes: 100)
        let remover = FakeRemover(trashDir: home.appendingPathComponent(".FakeTrash"))
        let r = DiskRemover(paths: paths, remover: remover)
        let leftovers = r.leftovers(for: "com.example.editor", appName: "Editor").map(\.lastPathComponent).sorted()
        XCTAssertEqual(leftovers, ["com.example.editor", "com.example.editor.plist"], "exact bundle id only")
        XCTAssertTrue(r.leftovers(for: "com.apple.Safari", appName: "Safari").isEmpty)

        let entry = DiskEntry(url: movie, name: "trip.mov", kind: .video, size: 5000, modified: nil,
                              lastUsed: nil, bundleID: nil, protected: false)
        let record = r.trash([entry])
        XCTAssertEqual(record.items.first?.status, .trashed)
        XCTAssertEqual(record.bytesInTrash, 5000)
        XCTAssertFalse(FileManager.default.fileExists(atPath: movie.path))
        let undone = Cleaner(rules: [], paths: paths, remover: remover).undo(record)
        XCTAssertEqual(undone.items.first?.status, .restored)
        XCTAssertTrue(FileManager.default.fileExists(atPath: movie.path))
    }

    // MARK: history

    func testHistoryStoreRoundTrip() throws {
        let store = HistoryStore(directory: home.appendingPathComponent("Support"))
        store.update { $0.kept.insert("creative.adobe.mediacache.files|Adobe Media Cache") }
        let fresh = HistoryStore(directory: home.appendingPathComponent("Support"))
        XCTAssertEqual(fresh.load().kept, ["creative.adobe.mediacache.files|Adobe Media Cache"])
    }
}
