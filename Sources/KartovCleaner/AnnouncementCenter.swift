import Foundation
import AppKit
import KartovCore

/// Fetches `announcements.json` from the GitHub repository every 10 minutes and shows each new
/// announcement once: as a notification and in Gözetim's alert list. Nothing else is sent or read.
@MainActor
final class AnnouncementCenter: ObservableObject {
    static let shared = AnnouncementCenter()

    @Published var enabled: Bool {
        didSet { defaults.set(enabled, forKey: "announcementsEnabled"); enabled ? start() : stop() }
    }

    private let defaults = UserDefaults.standard
    private var timer: Timer?
    private var fetching = false

    private var seen: Set<String> {
        get { Set(defaults.stringArray(forKey: "announcementsSeen") ?? []) }
        set { defaults.set(Array(newValue).sorted(), forKey: "announcementsSeen") }
    }

    private init() {
        enabled = UserDefaults.standard.object(forKey: "announcementsEnabled") as? Bool ?? true
    }

    func start() {
        guard enabled, timer == nil, Updater.shared.repo != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in self?.fetch() }
        timer = Timer.scheduledTimer(withTimeInterval: 10 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.fetch() }
        }
        timer?.tolerance = 60
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private var feedURL: URL? {
        guard let repo = Updater.shared.repo else { return nil }
        return URL(string: "https://raw.githubusercontent.com/\(repo)/main/announcements.json")
    }

    func fetch() {
        guard enabled, !fetching, let url = feedURL else { return }
        fetching = true
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        req.setValue("KartovCleaner/\(Updater.shared.currentVersion)", forHTTPHeaderField: "User-Agent")
        Task {
            defer { fetching = false }
            guard let (data, response) = try? await URLSession.shared.data(for: req),
                  (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            let all = AnnouncementFeed.parse(data)
            let new = AnnouncementFeed.toShow(all, seen: seen, version: Updater.shared.currentVersion, language: I18n.code)
            guard !new.isEmpty else { return }
            seen = seen.union(new.map(\.id))
            for a in new {
                Guardian.shared.announce(id: a.id, title: a.title(in: I18n.code), detail: a.body(in: I18n.code),
                                         link: a.link?.absoluteString)
            }
            klog("duyuru: \(new.map(\.id).joined(separator: ", "))")
        }
    }
}
