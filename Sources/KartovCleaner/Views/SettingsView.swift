import SwiftUI
import KartovCore

/// Settings: topics on the left, one topic at a time on the right. Each topic says how it stands
/// in its second line, so most questions are answered without opening it.
struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var nav = SettingsNav.shared

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar()
            Rectangle().fill(KColor.border.opacity(0.6)).frame(width: 1)
            ScrollView {
                page
                    .padding(.horizontal, 32).padding(.vertical, 32)
                    .frame(maxWidth: .infinity)
            }
            // A new page starts at its top.
            .id(nav.position)
        }
        .onAppear {
            model.refreshPermissions()
            NotificationPermission.shared.refresh()
        }
        .confirmationDialog(nav.confirm?.title ?? "", isPresented: confirmShown,
                            titleVisibility: .visible, presenting: nav.confirm) { what in
            Button(what.button, role: .destructive) { what.perform(model) }
            Button(L("Vazgeç"), role: .cancel) {}
        } message: { what in
            Text(what.message)
        }
    }

    private var confirmShown: Binding<Bool> {
        Binding(get: { nav.confirm != nil }, set: { if !$0 { nav.confirm = nil } })
    }

    @ViewBuilder private var page: some View {
        switch nav.page {
        case .general: GeneralSettingsPage()
        case .cleaning: CleaningSettingsPage()
        case .profiles:
            if let profile = nav.profile { ProfileDetailPage(profile: profile) } else { ProfilesSettingsPage() }
        case .alerts: AlertsSettingsPage()
        case .privacy: PrivacySettingsPage()
        case .updates: UpdatesSettingsPage()
        case .reset: ResetSettingsPage()
        }
    }
}

// MARK: where we are

enum SettingsPage: String, CaseIterable, Identifiable {
    case general, cleaning, profiles, alerts, privacy, updates, reset
    var id: Self { self }

    var title: String {
        switch self {
        case .general: return L("Genel")
        case .cleaning: return L("Temizlik")
        case .profiles: return L("Çalışma profili")
        case .alerts: return L("Bildirimler")
        case .privacy: return L("İzinler ve gizlilik")
        case .updates: return L("Güncellemeler")
        case .reset: return L("Sıfırlama")
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .cleaning: return "sparkles"
        case .profiles: return "person.crop.circle"
        case .alerts: return "bell"
        case .privacy: return "lock.shield"
        case .updates: return "arrow.down.circle"
        case .reset: return "arrow.counterclockwise"
        }
    }
}

@MainActor
final class SettingsNav: ObservableObject {
    static let shared = SettingsNav()

    @Published private(set) var page: SettingsPage = .general
    /// The profile being edited. Looking at a profile does not switch to it.
    @Published private(set) var profile: WorkspaceProfile?
    @Published var confirm: SettingsConfirm?

    var position: String { page.rawValue + (profile?.rawValue ?? "") }

    func open(_ page: SettingsPage, profile: WorkspaceProfile? = nil) {
        self.page = page
        self.profile = profile
    }
}

/// Whatever cannot be taken back asks first.
enum SettingsConfirm {
    case history, choices, guardian, profile(WorkspaceProfile), everything

    var title: String {
        switch self {
        case .history: return L("Temizlik geçmişi silinsin mi?")
        case .choices: return L("Temizlik seçimlerin sıfırlansın mı?")
        case .guardian: return L("Gözetim kayıtları silinsin mi?")
        case .profile(let p): return L("{0} profili varsayılana dönsün mü?", p.title)
        case .everything: return L("Kartov ilk günkü haline dönsün mü?")
        }
    }

    var message: String {
        switch self {
        case .history: return L("Dosyalarına dokunulmaz ama eski temizlikleri Kartov'dan geri alamazsın. Çöp kutusundakileri Finder'dan geri koyabilirsin.")
        case .choices: return L("Korumaya aldığın ve temizlenmesi için seçtiğin öğeler unutulur. Dosyalarına dokunulmaz.")
        case .guardian: return L("Uyarılar, disk ve enerji ölçümleri silinir. Ayarların kalır.")
        case .profile: return L("Bu profilde değiştirdiklerin geri alınır. Diğer profiller değişmez.")
        case .everything: return L("Bütün ayarlar, geçmiş ve korunan öğeler silinir; Kartov ilk günkü haline döner ve yeniden başlar. Dosyalarına dokunulmaz.")
        }
    }

    var button: String {
        switch self {
        case .history: return L("Geçmişi sil")
        case .choices, .profile: return L("Sıfırla")
        case .guardian: return L("Kayıtları sil")
        case .everything: return L("Evet, sıfırla")
        }
    }

    @MainActor func perform(_ model: AppModel) {
        switch self {
        case .history: model.clearHistory()
        case .choices: model.resetChoices()
        case .guardian: Guardian.shared.resetData()
        case .profile(let p): ProfileStore.shared.reset(p)
        case .everything: model.resetAllSettings()
        }
    }
}

// MARK: sidebar

struct SettingsSidebar: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var nav = SettingsNav.shared
    @ObservedObject private var profiles = ProfileStore.shared
    @ObservedObject private var guardian = Guardian.shared
    @ObservedObject private var updater = Updater.shared
    @ObservedObject private var permission = NotificationPermission.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Ayarlar")).font(.system(size: 20, weight: .medium))
                    .padding(.horizontal, 12).padding(.bottom, 12)
                    .accessibilityAddTraits(.isHeader)
                ForEach(SettingsPage.allCases) { page in
                    SettingsSidebarRow(page: page, summary: summary(page), attention: attention(page),
                                       selected: nav.page == page) { nav.open(page) }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 24)
        }
        .frame(width: SettingsMetrics.sidebar)
        .background(KColor.chrome)
    }

    private func summary(_ page: SettingsPage) -> String {
        switch page {
        case .general: return L("Dil, açılış, menü çubuğu")
        case .cleaning: return model.autoEnabled ? L("Otomatik bakım açık") : L("Otomatik bakım kapalı")
        case .profiles: return profiles.active.title
        case .alerts:
            if permission.denied { return L("macOS'ta kapalı") }
            if !guardian.enabled { return L("Gözetim kapalı") }
            return guardian.notify ? L("Açık") : L("Uyarılar sessiz")
        case .privacy: return model.hasFullDiskAccess ? L("Gereken izin verildi") : L("İzin gerekiyor")
        case .updates:
            if let r = updater.release { return L("{0} sürümü hazır.", r.version) }
            return L("Sürüm {0}", updater.currentVersion)
        case .reset: return L("Geçmiş, seçimler, ayarlar")
        }
    }

    private func attention(_ page: SettingsPage) -> Bool {
        switch page {
        case .alerts: return permission.denied
        case .privacy: return !model.hasFullDiskAccess
        default: return false
        }
    }
}

struct SettingsSidebarRow: View {
    let page: SettingsPage
    let summary: String
    let attention: Bool
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: page.symbol).font(.system(size: 16))
                    .foregroundStyle(selected ? KColor.onAccent : KColor.textMuted)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(page.title).font(.system(size: 14, weight: .medium))
                        .foregroundStyle(selected ? KColor.onAccent : KColor.text)
                    Text(summary).font(.system(size: 12))
                        .foregroundStyle(selected ? KColor.onAccent : KColor.textMuted)
                }
                .lineLimit(1)
                Spacer(minLength: 4)
                if attention {
                    Circle().fill(selected ? KColor.onAccent : KColor.warning).frame(width: 8, height: 8)
                }
            }
            .padding(.horizontal, 12).frame(height: 52)
            .background(RoundedRectangle(cornerRadius: KRadius.md).fill(selected ? KColor.accent : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
