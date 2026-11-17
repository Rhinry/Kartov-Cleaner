import SwiftUI
import AppKit
import UserNotifications
import KartovCore

/// Whether macOS lets Kartov show notifications, and asking for it.
/// macOS shows its own permission prompt only once; after a "no" the switch lives in System Settings,
/// so Kartov then explains it and opens the right page.
@MainActor
final class NotificationPermission: ObservableObject {
    static let shared = NotificationPermission()

    @Published private(set) var status: UNAuthorizationStatus = .notDetermined
    @Published private(set) var checked = false
    /// "Not now" hides the banner for two weeks.
    @Published private(set) var snoozedUntil: Date? {
        didSet { UserDefaults.standard.set(snoozedUntil, forKey: "notificationBannerSnoozed") }
    }

    private var observer: NSObjectProtocol?

    private init() {
        snoozedUntil = UserDefaults.standard.object(forKey: "notificationBannerSnoozed") as? Date
        // Coming back from System Settings: read the switch again.
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                                          object: nil, queue: .main) { _ in
            Task { @MainActor in NotificationPermission.shared.refresh() }
        }
        refresh()
    }

    var allowed: Bool { status == .authorized || status == .provisional }
    var denied: Bool { checked && status == .denied }

    var showBanner: Bool {
        guard denied else { return false }
        if let until = snoozedUntil, until > Date() { return false }
        return true
    }

    func refresh() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let s = settings.authorizationStatus
            Task { @MainActor in
                let p = NotificationPermission.shared
                p.status = s
                p.checked = true
            }
        }
    }

    /// Shows macOS's own prompt when Kartov has never asked. Does nothing after a yes or a no.
    func requestIfNeeded() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else {
                Task { @MainActor in NotificationPermission.shared.refresh() }
                return
            }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
                Task { @MainActor in NotificationPermission.shared.refresh() }
            }
        }
    }

    /// System Settings › Notifications › Kartov Cleaner.
    func openSettings() {
        let id = Bundle.main.bundleIdentifier ?? "com.kartov.cleaner"
        let urls = ["x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)",
                    "x-apple.systempreferences:com.apple.Notifications-Settings.extension",
                    "x-apple.systempreferences:com.apple.preference.notifications"]
        for s in urls {
            if let url = URL(string: s), NSWorkspace.shared.open(url) { return }
        }
    }

    func snooze() {
        snoozedUntil = Date().addingTimeInterval(14 * 86_400)
    }
}

/// Strip under the tabs when macOS blocks Kartov's notifications.
struct NotificationBanner: View {
    @ObservedObject private var permission = NotificationPermission.shared

    var body: some View {
        if permission.showBanner {
            HStack(spacing: 12) {
                Image(systemName: "bell.slash").foregroundStyle(KColor.textMuted)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Kartov sana haber veremiyor")).font(.system(size: 13, weight: .semibold))
                    Text(L("macOS'ta Kartov Cleaner'ın bildirimleri kapalı. Gözetim uyarıları, haftalık özet, duyurular ve güncellemeler ekrana gelmiyor."))
                        .font(.system(size: 12)).foregroundStyle(KColor.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button(L("Şimdi değil")) { permission.snooze() }
                    .buttonStyle(SecondaryButtonStyle())
                Button(L("Bildirimleri aç")) { permission.openSettings() }
                    .buttonStyle(PrimaryButtonStyle())
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(KColor.surface)
            .overlay(alignment: .bottom) { Rectangle().fill(KColor.border).frame(height: 1) }
        }
    }
}
