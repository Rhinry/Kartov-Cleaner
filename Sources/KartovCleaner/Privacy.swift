import Foundation
import AppKit
import CoreServices
import SQLite3
import KartovCore

/// A kind of access macOS asks the user about (camera, microphone…).
enum PrivacyService: String, CaseIterable, Identifiable {
    case camera, microphone, screen, accessibility, fullDisk, files, input, contacts, calendar, photos, automation
    var id: Self { self }

    /// Names in macOS's permission database.
    var tccNames: [String] {
        switch self {
        case .camera: return ["kTCCServiceCamera"]
        case .microphone: return ["kTCCServiceMicrophone"]
        case .screen: return ["kTCCServiceScreenCapture"]
        case .accessibility: return ["kTCCServiceAccessibility"]
        case .fullDisk: return ["kTCCServiceSystemPolicyAllFiles"]
        case .files: return ["kTCCServiceSystemPolicyDesktopFolder", "kTCCServiceSystemPolicyDocumentsFolder",
                             "kTCCServiceSystemPolicyDownloadsFolder", "kTCCServiceSystemPolicyNetworkVolumes",
                             "kTCCServiceSystemPolicyRemovableVolumes"]
        case .input: return ["kTCCServiceListenEvent", "kTCCServicePostEvent"]
        case .contacts: return ["kTCCServiceAddressBook"]
        case .calendar: return ["kTCCServiceCalendar", "kTCCServiceReminders"]
        case .photos: return ["kTCCServicePhotos", "kTCCServicePhotosAdd"]
        case .automation: return ["kTCCServiceAppleEvents"]
        }
    }

    var title: String {
        switch self {
        case .camera: return L("Kamera")
        case .microphone: return L("Mikrofon")
        case .screen: return L("Ekran kaydı")
        case .accessibility: return L("Erişilebilirlik")
        case .fullDisk: return L("Tam Disk Erişimi")
        case .files: return L("Dosyalar ve klasörler")
        case .input: return L("Klavye izleme")
        case .contacts: return L("Kişiler")
        case .calendar: return L("Takvim ve anımsatıcılar")
        case .photos: return L("Fotoğraflar")
        case .automation: return L("Otomasyon")
        }
    }

    var symbol: String {
        switch self {
        case .camera: return "camera.fill"
        case .microphone: return "mic.fill"
        case .screen: return "rectangle.dashed.badge.record"
        case .accessibility: return "accessibility"
        case .fullDisk: return "internaldrive.fill"
        case .files: return "folder.fill"
        case .input: return "keyboard.fill"
        case .contacts: return "person.crop.circle.fill"
        case .calendar: return "calendar"
        case .photos: return "photo.fill"
        case .automation: return "gearshape.2.fill"
        }
    }

    /// Can see or control a lot: shown first and marked.
    var sensitive: Bool { [.camera, .microphone, .screen, .accessibility, .fullDisk, .input].contains(self) }

    /// The matching pane in System Settings › Privacy & Security.
    var settingsURL: URL? {
        let anchor: String
        switch self {
        case .camera: anchor = "Privacy_Camera"
        case .microphone: anchor = "Privacy_Microphone"
        case .screen: anchor = "Privacy_ScreenCapture"
        case .accessibility: anchor = "Privacy_Accessibility"
        case .fullDisk: anchor = "Privacy_AllFiles"
        case .files: anchor = "Privacy_FilesAndFolders"
        case .input: anchor = "Privacy_ListenEvent"
        case .contacts: anchor = "Privacy_Contacts"
        case .calendar: anchor = "Privacy_Calendars"
        case .photos: anchor = "Privacy_Photos"
        case .automation: anchor = "Privacy_Automation"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?" + anchor)
    }

    static func from(tcc name: String) -> PrivacyService? { allCases.first { $0.tccNames.contains(name) } }

    static let locationSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")
}

/// One program and the access it has been given.
struct PrivacyApp: Identifiable {
    let id: String
    let name: String
    let bundleID: String?
    let url: URL?
    let icon: NSImage?
    /// Still on this Mac.
    let installed: Bool
    let lastUsed: Date?
    var allowed: [PrivacyService]
    var denied: [PrivacyService]
    var lastChanged: Date?

    var sensitiveCount: Int { allowed.filter(\.sensitive).count }

    /// Has sensitive access but has not been opened for three months.
    var dormant: Bool {
        guard installed, sensitiveCount > 0, let d = lastUsed else { return false }
        return Date().timeIntervalSince(d) > 90 * 86_400
    }
}

/// Reads (never writes) macOS's permission database. Needs Full Disk Access.
/// Location access is kept elsewhere by macOS (readable only by the system), so it is not listed.
enum PrivacyInspector {
    private struct Row { let service: String; let client: String; let clientType: Int; let auth: Int; let modified: Double }

    static func read() -> (apps: [PrivacyApp], readable: Bool) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let paths = [home.appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db").path,
                     "/Library/Application Support/com.apple.TCC/TCC.db"]
        var rows: [Row] = []
        var readable = false
        for p in paths {
            if let r = readRows(at: p) { rows += r; readable = true }
        }
        var byClient: [String: PrivacyApp] = [:]
        for r in rows {
            guard let service = PrivacyService.from(tcc: r.service) else { continue }
            if byClient[r.client] == nil {
                byClient[r.client] = makeApp(client: r.client, type: r.clientType)
            }
            guard var app = byClient[r.client] else { continue }
            let allowed = r.auth == 2 || r.auth == 3
            if allowed { if !app.allowed.contains(service) { app.allowed.append(service) } }
            else if r.auth == 0, !app.denied.contains(service) { app.denied.append(service) }
            if r.modified > 0 {
                let d = Date(timeIntervalSince1970: r.modified)
                if app.lastChanged.map({ d > $0 }) ?? true { app.lastChanged = d }
            }
            byClient[r.client] = app
        }
        let apps = byClient.values
            // Leftover records of deleted scripts (by path) cannot be reset by name: skip them.
            .filter { ($0.installed && !$0.allowed.isEmpty) || (!$0.installed && $0.bundleID != nil) }
            .map { a -> PrivacyApp in
                var a = a
                a.allowed.sort { ($0.sensitive ? 0 : 1, $0.title) < ($1.sensitive ? 0 : 1, $1.title) }
                return a
            }
            .sorted { a, b in
                if a.installed != b.installed { return !a.installed }
                if a.dormant != b.dormant { return a.dormant }
                if a.sensitiveCount != b.sensitiveCount { return a.sensitiveCount > b.sensitiveCount }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
        return (apps, readable)
    }

    private static func makeApp(client: String, type: Int) -> PrivacyApp {
        let ws = NSWorkspace.shared
        var url: URL?
        var bundleID: String?
        if type == 0 {
            bundleID = client
            url = ws.urlForApplication(withBundleIdentifier: client)
        } else if FileManager.default.fileExists(atPath: client) {
            url = URL(fileURLWithPath: client)
        }
        var name = url.map { FileManager.default.displayName(atPath: $0.path) } ?? (client as NSString).lastPathComponent
        if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
        var lastUsed: Date?
        if let u = url, let item = MDItemCreateWithURL(nil, u as CFURL) {
            lastUsed = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
        }
        return PrivacyApp(id: client, name: name, bundleID: bundleID, url: url,
                          icon: url.map { ws.icon(forFile: $0.path) }, installed: url != nil, lastUsed: lastUsed,
                          allowed: [], denied: [], lastChanged: nil)
    }

    /// Reads the `access` table. Tries a normal read-only open first, then an "immutable" one
    /// (needed when the database's lock files cannot be opened).
    private static func readRows(at path: String) -> [Row]? {
        guard FileManager.default.isReadableFile(atPath: path) else { return nil }
        if let r = query(path: path, flags: SQLITE_OPEN_READONLY) { return r }
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        return query(path: "file:" + encoded + "?immutable=1", flags: SQLITE_OPEN_READONLY | SQLITE_OPEN_URI)
    }

    private static func query(path: String, flags: Int32) -> [Row]? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK, let handle = db else {
            sqlite3_close(db)
            return nil
        }
        defer { sqlite3_close(handle) }
        // macOS 11 and later use `auth_value`; older systems used `allowed`.
        for (sql, modern) in [("SELECT service, client, client_type, auth_value, last_modified FROM access", true),
                              ("SELECT service, client, client_type, allowed, last_modified FROM access", false)] {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let st = stmt else {
                sqlite3_finalize(stmt)
                continue
            }
            var out: [Row] = []
            var failed = false
            while true {
                let rc = sqlite3_step(st)
                if rc == SQLITE_ROW {
                    let service = sqlite3_column_text(st, 0).map { String(cString: $0) } ?? ""
                    let client = sqlite3_column_text(st, 1).map { String(cString: $0) } ?? ""
                    let type = Int(sqlite3_column_int(st, 2))
                    var auth = Int(sqlite3_column_int(st, 3))
                    if !modern { auth = auth == 1 ? 2 : 0 }
                    let modified = sqlite3_column_double(st, 4)
                    if !client.isEmpty { out.append(Row(service: service, client: client, clientType: type, auth: auth, modified: modified)) }
                } else {
                    failed = rc != SQLITE_DONE
                    break
                }
            }
            sqlite3_finalize(st)
            return failed ? nil : out
        }
        return nil
    }

    /// Removes every permission macOS remembers for a program that is no longer installed.
    static func reset(bundleID: String) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        p.arguments = ["reset", "All", bundleID]
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }
}
