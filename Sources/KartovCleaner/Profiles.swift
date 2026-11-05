import Foundation
import AppKit
import KartovCore

/// How the Mac is used right now. A profile decides which caches are protected from cleaning
/// and which busy programs Gözetim should not warn about.
enum WorkspaceProfile: String, CaseIterable, Identifiable, Codable {
    case everyday, editing, development, gaming
    var id: Self { self }

    var title: String {
        switch self {
        case .everyday: return L("Günlük")
        case .editing: return L("Montaj")
        case .development: return L("Yazılım")
        case .gaming: return L("Oyun")
        }
    }

    var symbol: String {
        switch self {
        case .everyday: return "sun.max.fill"
        case .editing: return "film.stack.fill"
        case .development: return "chevron.left.forwardslash.chevron.right"
        case .gaming: return "gamecontroller.fill"
        }
    }

    var summary: String {
        switch self {
        case .everyday: return L("Her şey temizlenebilir, her uyarı açık.")
        case .editing: return L("Video ve tasarım programlarının önbellekleri korunur; render sırasında işlemci uyarısı gelmez.")
        case .development: return L("Derleme önbellekleri korunur; derlerken işlemci uyarısı gelmez.")
        case .gaming: return L("Oyun açıkken bildirim gelmez; oyunların yoğunluğu uyarı sayılmaz.")
        }
    }

    var defaults: ProfileSettings {
        switch self {
        case .everyday: return ProfileSettings(protected: [], quietHeavy: false, quietWhilePlaying: false)
        case .editing: return ProfileSettings(protected: [.creative], quietHeavy: true, quietWhilePlaying: false)
        case .development: return ProfileSettings(protected: [.developer], quietHeavy: true, quietWhilePlaying: false)
        case .gaming: return ProfileSettings(protected: [], quietHeavy: true, quietWhilePlaying: true)
        }
    }

    /// Programs that are expected to work hard in this profile.
    var heavyBundlePrefixes: [String] {
        switch self {
        case .everyday: return []
        case .editing: return ["com.adobe.", "com.apple.FinalCut", "com.apple.motionapp", "com.apple.Compressor",
                               "com.blackmagic-design.", "com.maxon.", "org.blenderfoundation.", "com.apple.logic",
                               "com.figma.", "com.bohemiancoding.sketch3", "com.seriflabs."]
        case .development: return ["com.apple.dt.", "com.microsoft.VSCode", "com.jetbrains.", "com.docker.",
                                   "com.todesktop.", "com.google.android.studio", "dev.zed.", "com.sublimetext."]
        case .gaming: return ["com.valvesoftware.", "com.epicgames.", "com.blizzard.", "com.riotgames.", "net.battle."]
        }
    }

    var heavyProcessNames: [String] {
        switch self {
        case .everyday: return []
        case .editing: return ["After Effects", "aerender", "Adobe Premiere", "Adobe Media Encoder", "Photoshop",
                               "DaVinci Resolve", "Blender", "Cinema 4D", "Final Cut Pro", "Compressor", "ffmpeg", "Redshift"]
        case .development: return ["swift-frontend", "swift-build", "clang", "ld", "xcodebuild", "XCBBuildService", "node",
                                   "java", "gradle", "docker", "com.docker.backend", "qemu-system-aarch64", "cargo", "rustc",
                                   "go", "python3", "ruby", "webpack", "esbuild", "SourceKitService"]
        case .gaming: return ["steam_osx", "Steam Helper"]
        }
    }
}

struct ProfileSettings: Codable, Equatable {
    /// Cleanup groups kept by default (still cleanable by hand, one switch at a time).
    var protected: Set<CategoryGroup>
    /// No processor warnings for the profile's own heavy programs.
    var quietHeavy: Bool
    /// No notifications while a game is in front.
    var quietWhilePlaying: Bool
}

@MainActor
final class ProfileStore: ObservableObject {
    static let shared = ProfileStore()

    @Published var active: WorkspaceProfile {
        didSet { UserDefaults.standard.set(active.rawValue, forKey: "workspaceProfile") }
    }
    @Published private(set) var settings: [WorkspaceProfile: ProfileSettings]

    private init() {
        active = WorkspaceProfile(rawValue: UserDefaults.standard.string(forKey: "workspaceProfile") ?? "") ?? .everyday
        var s: [WorkspaceProfile: ProfileSettings] = [:]
        if let data = UserDefaults.standard.data(forKey: "workspaceProfiles.v1"),
           let saved = try? JSONDecoder().decode([String: ProfileSettings].self, from: data) {
            for (k, v) in saved { if let p = WorkspaceProfile(rawValue: k) { s[p] = v } }
        }
        for p in WorkspaceProfile.allCases where s[p] == nil { s[p] = p.defaults }
        settings = s
    }

    var current: ProfileSettings { settings[active] ?? active.defaults }

    func settings(for p: WorkspaceProfile) -> ProfileSettings { settings[p] ?? p.defaults }

    func update(_ p: WorkspaceProfile, _ change: (inout ProfileSettings) -> Void) {
        var s = settings(for: p)
        change(&s)
        settings[p] = s
        var plain: [String: ProfileSettings] = [:]
        for (k, v) in settings { plain[k.rawValue] = v }
        if let data = try? JSONEncoder().encode(plain) { UserDefaults.standard.set(data, forKey: "workspaceProfiles.v1") }
    }

    func reset(_ p: WorkspaceProfile) { update(p) { $0 = p.defaults } }

    func protects(_ group: CategoryGroup) -> Bool { current.protected.contains(group) }

    /// A program the active profile expects to be busy.
    func isExpectedHeavy(name: String, bundleID: String?) -> Bool {
        guard current.quietHeavy else { return false }
        if let id = bundleID, active.heavyBundlePrefixes.contains(where: { id.hasPrefix($0) }) { return true }
        if active == .gaming, isGame(bundleID: bundleID) { return true }
        let n = name.lowercased()
        return active.heavyProcessNames.contains { n == $0.lowercased() || n.hasPrefix($0.lowercased()) }
    }

    /// Notifications are held back while a game is in front (Oyun profile).
    var holdNotifications: Bool {
        guard current.quietWhilePlaying, let front = NSWorkspace.shared.frontmostApplication else { return false }
        return isGame(bundleID: front.bundleIdentifier, url: front.bundleURL)
    }

    func isGame(bundleID: String?, url: URL? = nil) -> Bool {
        var u = url
        if u == nil, let id = bundleID { u = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) }
        guard let u, let category = Bundle(url: u)?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String else {
            return false
        }
        return category.contains("games")
    }
}
