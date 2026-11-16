import Foundation
import AppKit
import UserNotifications
import KartovCore

/// An announcement waiting to be shown in the app.
struct PendingAnnouncement: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let body: String
    let link: String?
    let date: Date

    var url: URL? { link.flatMap(URL.init(string:)).flatMap { $0.scheme == "https" ? $0 : nil } }
}

/// Fetches `announcements.json` from the GitHub repository every 10 minutes. A new announcement opens
/// as a card inside the app; when Kartov is not in front, macOS first says "you have a new announcement"
/// and the card waits for the next time the window is opened. Each one also stays in Gözetim's list.
@MainActor
final class AnnouncementCenter: ObservableObject {
    static let shared = AnnouncementCenter()

    @Published var enabled: Bool {
        didSet { defaults.set(enabled, forKey: "announcementsEnabled"); enabled ? start() : stop() }
    }
    /// Cards still to show, oldest first. Kept across launches.
    @Published private(set) var queue: [PendingAnnouncement] = [] {
        didSet { if let data = try? JSONEncoder().encode(queue) { defaults.set(data, forKey: "announcementsQueue") } }
    }

    var current: PendingAnnouncement? { queue.first }

    private let defaults = UserDefaults.standard
    private var timer: Timer?
    private var fetching = false

    private var seen: Set<String> {
        get { Set(defaults.stringArray(forKey: "announcementsSeen") ?? []) }
        set { defaults.set(Array(newValue).sorted(), forKey: "announcementsSeen") }
    }

    private init() {
        let d = UserDefaults.standard
        enabled = d.object(forKey: "announcementsEnabled") as? Bool ?? true
        if let data = d.data(forKey: "announcementsQueue"),
           let saved = try? JSONDecoder().decode([PendingAnnouncement].self, from: data) { queue = saved }
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
            let lang = I18n.code
            for a in new {
                let p = PendingAnnouncement(id: a.id, title: a.title(in: lang), body: a.body(in: lang),
                                            link: a.link?.absoluteString, date: Date())
                Guardian.shared.announce(id: a.id, title: p.title, detail: p.body, link: p.link)
                queue.append(p)
            }
            klog("duyuru: \(new.map(\.id).joined(separator: ", "))")
            // In front: the card is enough. Otherwise a short macOS notification points to it.
            if !NSApp.isActive { notify(first: new[0].title(in: lang), count: new.count) }
        }
    }

    private func notify(first title: String, count: Int) {
        guard !ProfileStore.shared.holdNotifications else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = count > 1 ? L("{0} yeni duyurunuz var", count) : L("Yeni bir duyurunuz var")
            content.body = title
            content.sound = .default
            center.add(UNNotificationRequest(identifier: "kartov-announce-\(UUID().uuidString)", content: content, trigger: nil))
        }
    }

    // MARK: the card

    func dismiss() {
        guard !queue.isEmpty else { return }
        queue.removeFirst()
    }

    func openLink() {
        if let url = current?.url { NSWorkspace.shared.open(url) }
        dismiss()
    }

    /// Shows an announcement again from Gözetim's list.
    func reopen(_ alert: GuardianAlert) {
        let p = PendingAnnouncement(id: alert.id.uuidString, title: alert.title, body: alert.detail,
                                    link: alert.link, date: alert.date)
        queue.removeAll { $0.id == p.id }
        queue.insert(p, at: 0)
    }
}
