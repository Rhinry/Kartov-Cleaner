import AppKit
import CryptoKit
import UserNotifications
import KartovCore

/// Checks GitHub Releases for a newer Kartov Cleaner, tells the user, and installs it only when asked.
///
/// How a release must look (yayinla.sh makes it this way):
/// - tag `v0.3` (or `0.3`), newer than CFBundleShortVersionString
/// - an asset ending in `.dmg` that contains `Kartov Cleaner.app`
/// - optionally an asset `<dmg name>.sha256` with the DMG's SHA-256; if present it must match
/// - the release text is shown to the user as "what's new"
@MainActor
final class Updater: NSObject, ObservableObject {
    static let shared = Updater()

    struct Release: Equatable {
        let version: String
        let notes: String
        let dmgURL: URL
        let checksumURL: URL?
        let pageURL: URL?
        let size: Int64
    }

    enum Phase: Equatable {
        case idle, checking, upToDate, available, downloading(Double), installing, failed(String)
    }

    @Published var phase: Phase = .idle
    @Published var release: Release?
    @Published var showSheet = false
    @Published var bannerDismissed = false
    @Published var autoCheck: Bool { didSet { UserDefaults.standard.set(autoCheck, forKey: "updateAutoCheck"); schedule() } }
    @Published var lastCheck: Date? { didSet { UserDefaults.standard.set(lastCheck, forKey: "updateLastCheck") } }

    private var timer: Timer?
    private var downloadTask: URLSessionDownloadTask?
    private var progressObservation: NSKeyValueObservation?

    /// "owner/repo", written into Info.plist by kur.sh from Paketleme/github-repo.txt.
    var repo: String? {
        let r = (Bundle.main.object(forInfoDictionaryKey: "KartovUpdateRepo") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let r, r.contains("/"), !r.hasPrefix("KULLANICI") else { return nil }
        return r
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    var skippedVersion: String? {
        get { UserDefaults.standard.string(forKey: "updateSkipped") }
        set { UserDefaults.standard.set(newValue, forKey: "updateSkipped") }
    }

    /// The banner shows when a newer version exists and the user has not set it aside.
    var hasUpdate: Bool { release != nil && phase != .upToDate }

    private override init() {
        autoCheck = UserDefaults.standard.object(forKey: "updateAutoCheck") as? Bool ?? true
        lastCheck = UserDefaults.standard.object(forKey: "updateLastCheck") as? Date
        super.init()
    }

    // MARK: checking

    /// Called once at launch: first look after 15 seconds, then once a day.
    func start() {
        UNUserNotificationCenter.current().delegate = self
        schedule()
    }

    private func schedule() {
        timer?.invalidate()
        timer = nil
        guard autoCheck, repo != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in self?.checkIfDue() }
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkIfDue() }
        }
    }

    private func checkIfDue() {
        guard autoCheck else { return }
        if let last = lastCheck, Date().timeIntervalSince(last) < 20 * 3600 { return }
        Task { await check(userInitiated: false) }
    }

    /// Asks GitHub for the latest release. `userInitiated` shows "you're up to date" and ignores a skipped version.
    func check(userInitiated: Bool) async {
        guard let repo else {
            phase = .failed(L("Güncelleme deposu ayarlanmamış."))
            return
        }
        if case .downloading = phase { return }
        phase = .checking
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("KartovCleaner/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 20
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            lastCheck = Date()
            if code == 404 { phase = .upToDate; release = nil; return }   // no release published yet
            guard code == 200, let found = Self.parse(data) else {
                phase = userInitiated ? .failed(L("GitHub'a ulaşılamadı. Biraz sonra yeniden dene.")) : .idle
                return
            }
            guard Self.isNewer(found.version, than: currentVersion) else {
                release = nil
                phase = .upToDate
                return
            }
            if !userInitiated, found.version == skippedVersion { phase = .idle; return }
            let isNew = release?.version != found.version
            release = found
            phase = .available
            bannerDismissed = false
            if userInitiated { showSheet = true } else if isNew { notify(found) }
        } catch {
            phase = userInitiated ? .failed(L("GitHub'a ulaşılamadı. Biraz sonra yeniden dene.")) : .idle
        }
    }

    static func parse(_ data: Data) -> Release? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              (json["draft"] as? Bool) != true, (json["prerelease"] as? Bool) != true,
              let assets = json["assets"] as? [[String: Any]] else { return nil }
        let dmg = assets.first { ($0["name"] as? String)?.lowercased().hasSuffix(".dmg") == true }
        guard let dmg, let dmgName = dmg["name"] as? String,
              let urlString = dmg["browser_download_url"] as? String, let url = URL(string: urlString) else { return nil }
        let sum = assets.first { ($0["name"] as? String) == dmgName + ".sha256" }
            .flatMap { $0["browser_download_url"] as? String }.flatMap(URL.init(string:))
        let version = tag.hasPrefix("v") || tag.hasPrefix("V") ? String(tag.dropFirst()) : tag
        return Release(version: version,
                       notes: (json["body"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                       dmgURL: url, checksumURL: sum,
                       pageURL: (json["html_url"] as? String).flatMap(URL.init(string:)),
                       size: (dmg["size"] as? NSNumber)?.int64Value ?? 0)
    }

    /// "0.10" > "0.9", "1.0" == "1".
    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: telling the user

    private func notify(_ r: Release) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = L("Kartov Cleaner {0} hazır", r.version)
            content.body = L("Yenilikleri görmek ve güncellemek için tıkla.")
            content.sound = .default
            center.add(UNNotificationRequest(identifier: "kartov-update-\(r.version)", content: content, trigger: nil))
        }
    }

    func later() {
        bannerDismissed = true
        showSheet = false
    }

    func skipThisVersion() {
        skippedVersion = release?.version
        release = nil
        phase = .idle
        showSheet = false
    }

    // MARK: installing

    func install() {
        guard let r = release else { return }
        phase = .downloading(0)
        let task = URLSession.shared.downloadTask(with: r.dmgURL) { [weak self] tmp, response, error in
            // Move the file before this handler returns; URLSession deletes it afterwards.
            var saved: URL?
            if let tmp, error == nil, (response as? HTTPURLResponse)?.statusCode ?? 200 < 400 {
                let dest = FileManager.default.temporaryDirectory.appendingPathComponent("KartovCleaner-\(r.version).dmg")
                try? FileManager.default.removeItem(at: dest)
                if (try? FileManager.default.moveItem(at: tmp, to: dest)) != nil { saved = dest }
            }
            Task { @MainActor in
                guard let self else { return }
                if let saved { await self.verifyAndInstall(dmg: saved, release: r) }
                else { self.phase = .failed(L("İndirme tamamlanamadı.")) }
            }
        }
        progressObservation = task.progress.observe(\.fractionCompleted) { [weak self] p, _ in
            let f = p.fractionCompleted
            Task { @MainActor in
                if case .downloading = self?.phase { self?.phase = .downloading(f) }
            }
        }
        downloadTask = task
        task.resume()
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        phase = .available
    }

    private func verifyAndInstall(dmg: URL, release r: Release) async {
        phase = .installing
        // 1. Checksum, when the release has one.
        if let sumURL = r.checksumURL {
            guard let (data, _) = try? await URLSession.shared.data(from: sumURL),
                  let expected = String(data: data, encoding: .utf8)?.split(whereSeparator: { $0 == " " || $0 == "\n" }).first,
                  let fileData = try? Data(contentsOf: dmg, options: .mappedIfSafe) else {
                phase = .failed(L("Doğrulama dosyası okunamadı.")); return
            }
            let actual = SHA256.hash(data: fileData).map { String(format: "%02x", $0) }.joined()
            guard actual == expected.lowercased() else {
                try? FileManager.default.removeItem(at: dmg)
                phase = .failed(L("İndirilen dosya doğrulanamadı; güncelleme yapılmadı.")); return
            }
        }
        // 2. Mount, find the app, check its signature matches this one.
        let result = await Task.detached { () -> Result<(String, String), UpdateError> in
            Self.prepare(dmg: dmg)
        }.value
        switch result {
        case .failure(let e):
            phase = .failed(e.message)
        case .success(let (mount, newApp)):
            launchReplacer(mount: mount, newApp: newApp, dmg: dmg)
        }
    }

    struct UpdateError: Error { let message: String }

    nonisolated static func prepare(dmg: URL) -> Result<(String, String), UpdateError> {
        let attach = run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-noverify", "-noautoopen", "-plist"])
        guard attach.status == 0,
              let plist = try? PropertyListSerialization.propertyList(from: Data(attach.out.utf8), format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]],
              let mount = entities.compactMap({ $0["mount-point"] as? String }).first else {
            return .failure(UpdateError(message: L("Güncelleme dosyası açılamadı.")))
        }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: mount)) ?? []
        guard let appName = names.first(where: { $0.hasSuffix(".app") }) else {
            _ = run("/usr/bin/hdiutil", ["detach", mount, "-quiet"])
            return .failure(UpdateError(message: L("Güncelleme dosyasında uygulama bulunamadı.")))
        }
        let newApp = (mount as NSString).appendingPathComponent(appName)
        // The new app must be validly signed; if this copy has a Developer ID team, the new one must have the same.
        let verify = run("/usr/bin/codesign", ["--verify", "--deep", "--strict", newApp])
        let mine = teamID(Bundle.main.bundlePath)
        if verify.status != 0 || (mine != nil && teamID(newApp) != mine) {
            _ = run("/usr/bin/hdiutil", ["detach", mount, "-quiet"])
            return .failure(UpdateError(message: L("Yeni sürümün imzası bu sürümle eşleşmiyor; güvenlik için kurulmadı.")))
        }
        return .success((mount, newApp))
    }

    nonisolated static func teamID(_ path: String) -> String? {
        let r = run("/usr/bin/codesign", ["-dv", "--verbose=2", path])
        let text = r.out + r.err
        guard let line = text.split(separator: "\n").first(where: { $0.hasPrefix("TeamIdentifier=") }) else { return nil }
        let id = String(line.dropFirst("TeamIdentifier=".count))
        return id == "not set" ? nil : id
    }

    nonisolated static func run(_ tool: String, _ args: [String]) -> (status: Int32, out: String, err: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let o = Pipe(), e = Pipe()
        p.standardOutput = o
        p.standardError = e
        do { try p.run() } catch { return (-1, "", error.localizedDescription) }
        let out = o.fileHandleForReading.readDataToEndOfFile()
        let err = e.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: out, as: UTF8.self), String(decoding: err, as: UTF8.self))
    }

    /// A small script waits for Kartov to quit, swaps the app (keeping the old one if anything fails),
    /// unmounts the DMG and opens the new version.
    private func launchReplacer(mount: String, newApp: String, dmg: URL) {
        let dest = Bundle.main.bundlePath
        let parent = (dest as NSString).deletingLastPathComponent
        guard FileManager.default.isWritableFile(atPath: parent) else {
            // Cannot write there (e.g. installed by another user): open the DMG so the user can drag it.
            NSWorkspace.shared.open(URL(fileURLWithPath: mount))
            phase = .failed(L("Bu klasöre yazılamıyor. Açılan pencereden Kartov Cleaner'ı Applications'a sürükle."))
            return
        }
        let script = """
        #!/bin/bash
        PID=\(ProcessInfo.processInfo.processIdentifier)
        for i in $(seq 1 120); do kill -0 $PID 2>/dev/null || break; sleep 0.5; done
        DEST=\(Self.quote(dest))
        NEW=\(Self.quote(newApp))
        rm -rf "$DEST.eski"
        if mv "$DEST" "$DEST.eski" && /usr/bin/ditto "$NEW" "$DEST"; then
          rm -rf "$DEST.eski"
        else
          rm -rf "$DEST"; mv "$DEST.eski" "$DEST"
        fi
        /usr/bin/xattr -dr com.apple.quarantine "$DEST" 2>/dev/null
        /usr/bin/hdiutil detach \(Self.quote(mount)) -quiet -force
        rm -f \(Self.quote(dmg.path))
        /usr/bin/open "$DEST"
        rm -f "$0"
        """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("kartov-guncelle.sh")
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/bash")
            p.arguments = [url.path]
            try p.run()
        } catch {
            phase = .failed(L("Güncelleme başlatılamadı."))
            return
        }
        // Make sure a "run in background" setting doesn't keep us alive.
        NSApp.terminate(nil)
    }

    nonisolated static func quote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}

extension Updater: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            StatusBar.shared.openApp()
            Updater.shared.showSheet = true
            completionHandler()
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
