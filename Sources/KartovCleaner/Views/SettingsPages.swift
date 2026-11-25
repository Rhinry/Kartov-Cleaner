import SwiftUI
import AppKit
import KartovCore

// One struct per Settings topic. Titles say what happens, notes say what it means for the user;
// options that depend on a switch appear only while that switch is on.

// MARK: general

struct GeneralSettingsPage: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        SettingsPageBody(title: SettingsPage.general.title,
                         intro: L("Kartov'un dili, ne zaman açıldığı ve menü çubuğunda nasıl davrandığı.")) {
            SettingsGroup {
                SettingsChoice(title: L("Dil"), options: AppLanguage.allCases, name: { $0.nativeName },
                               selection: model.language) { model.language = $0 }
                if model.languageNeedsRestart {
                    SettingsDivider()
                    SettingsStatus(tone: .neutral, title: L("Yeniden başlatma gerekiyor"),
                                   note: L("Yeni dil, Kartov yeniden başlayınca geçerli olur.")) {
                        Button(L("Şimdi yeniden başlat")) { Permissions.relaunch() }.buttonStyle(PrimaryButtonStyle())
                    }
                }
            }

            SettingsGroup(title: L("Açılış ve kapanış")) {
                SettingsToggle(L("Arka planda çalış"),
                               note: L("Pencereyi kapatsan da çalışır. Bunu değiştirince aşağıdaki ayar da birlikte değişir."),
                               isOn: model.runInBackground) { model.runInBackground = $0 }
                SettingsDivider()
                SettingsToggle(L("Mac açılınca başlat"), note: L("Mac'i açtığında Kartov'u senin açman gerekmez."),
                               isOn: model.launchAtLogin) { model.setLaunchAtLogin($0) }
            }

            SettingsGroup(title: L("Menü çubuğu")) {
                SettingsToggle(L("Menü çubuğu simgesi"), note: L("Ekranın en üstünde, saatin yanında küçük bir Kartov simgesi durur."),
                               isOn: model.showMenuBarIcon) { model.showMenuBarIcon = $0 }
                if model.showMenuBarIcon {
                    SettingsDivider()
                    SettingsChoice(title: L("Simgeye tıklayınca"), note: clickNote, options: MenuBarAction.allCases,
                                   name: { $0.title }, selection: model.menuBarAction) { model.menuBarAction = $0 }
                }
            }
        }
    }

    /// A single click can clean, so the note says exactly what that click does.
    private var clickNote: String {
        switch model.menuBarAction {
        case .panel:
            return L("Küçük bir pencere açılır. Sen seçmeden bir şey yapılmaz.")
        case .optimize:
            return AdminAccess.shared.enabled ? L("Bellek boşaltılır.") : L("Bellek boşaltılır. macOS şifreni sorabilir.")
        case .clean:
            return L("Tek tıkla, sormadan önbellekleri ve Bakım'da seçtiğin türleri temizler. Çöp kutusuna dokunmaz.")
        case .both:
            return L("Tek tıkla, sormadan Bakım'da seçtiğin türleri temizler ve belleği boşaltır. Çöp kutusuna dokunmaz.")
        }
    }
}

// MARK: cleaning

struct CleaningSettingsPage: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        SettingsPageBody(title: SettingsPage.cleaning.title,
                         intro: L("Taramanın ne zaman başladığı ve temizliğin nasıl bittiği.")) {
            SettingsGroup {
                SettingsToggle(L("Açılışta tara"), note: L("Kartov açılınca ne kadar yer açılabileceğine bakar. Hiçbir şey silmez."),
                               isOn: model.scanOnLaunch) { model.scanOnLaunch = $0 }
                SettingsDivider()
                SettingsToggle(L("Temizlik bitince ses çal"), note: L("Temizliğin bittiğini kısa bir sesle duyarsın."),
                               isOn: model.cleanSound) { model.cleanSound = $0 }
            }

            SettingsGroup(title: L("Kendiliğinden temizlik")) {
                SettingsNavRow(title: L("Otomatik bakım"), note: L("Gününü, saatini ve neyin temizleneceğini Bakım'da seçersin."),
                               value: model.autoEnabled ? model.autoScheduleText : L("Kapalı")) { model.section = .maintenance }
            }

            SettingsGroup(title: L("Değişmeyen kurallar")) {
                promise(L("Büyük kişisel dosyalar kalıcı olarak silinmez, çöp kutusuna gider."))
                promise(L("Tarama geçmişi silinmeden önce her zaman sorulur."))
                promise(L("Açık olan programların önbelleğine dokunulmaz."))
            }
        }
    }

    private func promise(_ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(KColor.success)
                .frame(width: 16).accessibilityHidden(true)
            Text(text).font(.system(size: 13)).foregroundStyle(KColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, SettingsMetrics.rowInset).padding(.vertical, 12)
    }
}

// MARK: profiles

struct ProfilesSettingsPage: View {
    @ObservedObject private var profiles = ProfileStore.shared
    @ObservedObject private var nav = SettingsNav.shared

    var body: some View {
        SettingsPageBody(title: SettingsPage.profiles.title,
                         intro: L("Mac'ini şu an ne için kullanıyorsun? Kartov neyi koruyacağını ve ne zaman susacağını buna göre ayarlar.")) {
            SettingsGroup(footer: L("Emin değilsen Günlük'te kal. Bir profili seçmeden de özelleştirebilirsin.")) {
                ForEach(WorkspaceProfile.allCases) { p in
                    if p != WorkspaceProfile.allCases.first { SettingsDivider() }
                    row(p)
                }
            }
        }
    }

    private func row(_ p: WorkspaceProfile) -> some View {
        let on = profiles.active == p
        let changed = profiles.settings(for: p) != p.defaults
        return HStack(spacing: 0) {
            Button { profiles.active = p } label: {
                HStack(spacing: 16) {
                    Image(systemName: on ? "largecircle.fill.circle" : "circle").font(.system(size: 18))
                        .foregroundStyle(on ? KColor.accent : KColor.textMuted)
                    Image(systemName: p.symbol).font(.system(size: 16)).foregroundStyle(KColor.textMuted)
                        .frame(width: 40, height: 40)
                        .background(RoundedRectangle(cornerRadius: KRadius.md).fill(KColor.surface2))
                    // Once customized, the built-in sentence may no longer be true.
                    SettingsLabel(title: p.title, note: changed ? L("Sen özelleştirdin.") : p.summary)
                    Spacer(minLength: 8)
                }
                .padding(.leading, SettingsMetrics.rowInset).padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: 76)
                .contentShape(Rectangle())
            }
            .buttonStyle(SettingsPressStyle())
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(on ? .isSelected : [])

            Button(L("Özelleştir")) { nav.open(.profiles, profile: p) }
                .buttonStyle(SecondaryButtonStyle())
                .padding(.horizontal, SettingsMetrics.rowInset)
        }
    }
}

struct ProfileDetailPage: View {
    let profile: WorkspaceProfile
    @ObservedObject private var profiles = ProfileStore.shared
    @ObservedObject private var nav = SettingsNav.shared

    private let groups: [CategoryGroup] = [.creative, .developer, .browsers, .apps, .logs]

    var body: some View {
        let settings = profiles.settings(for: profile)
        let active = profiles.active == profile
        VStack(alignment: .leading, spacing: 16) {
            Button { nav.open(.profiles) } label: {
                Label(L("Bütün profiller"), systemImage: "chevron.left").font(.system(size: 13, weight: .medium))
                    .foregroundStyle(KColor.accentSoft).frame(height: 32).contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            SettingsPageBody(title: L("{0} profili", profile.title),
                             intro: active ? L("Şu an bu profili kullanıyorsun. Değişiklikler hemen geçerli olur.")
                                           : L("Bu profili şu an kullanmıyorsun. Değişiklikler onu seçtiğinde geçerli olur.")) {
                SettingsGroup(title: L("Temizlenmesin"),
                              footer: L("Açık olanlar temizlikte seçili gelmez; otomatik bakım ve hızlı temizlik de dokunmaz.")) {
                    ForEach(groups, id: \.self) { g in
                        if g != groups.first { SettingsDivider() }
                        SettingsToggle(g.title, isOn: settings.protected.contains(g)) { on in
                            profiles.update(profile) { if on { $0.protected.insert(g) } else { $0.protected.remove(g) } }
                        }
                    }
                }

                SettingsGroup(title: L("Rahatsız etme")) {
                    SettingsToggle(L("Ağır işlerde uyarıları sustur"),
                                   note: L("Render, derleme ya da oyun işlemciyi yorarken Gözetim uyarmaz."),
                                   isOn: settings.quietHeavy) { on in profiles.update(profile) { $0.quietHeavy = on } }
                    SettingsDivider()
                    SettingsToggle(L("Oyun açıkken uyarıları sustur"),
                                   note: L("Uyarılar bildirim olarak gelmez, Gözetim'de seni bekler."),
                                   isOn: settings.quietWhilePlaying) { on in profiles.update(profile) { $0.quietWhilePlaying = on } }
                }

                if settings != profile.defaults {
                    Button(L("Bu profili varsayılana döndür")) { nav.confirm = .profile(profile) }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
        }
        .frame(maxWidth: SettingsMetrics.page, alignment: .leading)
    }
}

// MARK: notifications

struct AlertsSettingsPage: View {
    @ObservedObject private var guardian = Guardian.shared
    @ObservedObject private var announcements = AnnouncementCenter.shared
    @ObservedObject private var updater = Updater.shared
    @ObservedObject private var permission = NotificationPermission.shared
    @ObservedObject private var nav = SettingsNav.shared

    var body: some View {
        SettingsPageBody(title: SettingsPage.alerts.title,
                         intro: L("Kartov'un neye dikkat edeceği ve sana ne zaman haber vereceği.")) {
            if permission.denied {
                SettingsGroup {
                    SettingsStatus(tone: .attention, title: L("macOS bildirimleri kapalı"),
                                   note: L("Duyurular ve uyarılar yalnızca Kartov'un içinde görünür.")) {
                        Button(L("Bildirimleri aç")) { permission.openSettings() }.buttonStyle(PrimaryButtonStyle())
                    }
                }
            }

            SettingsGroup(title: L("Gözetim")) {
                SettingsToggle(L("Mac'ime göz kulak ol"), note: L("Dakikada bir bakar; yalnızca okur, hiçbir şey silmez."),
                               isOn: guardian.enabled) { guardian.enabled = $0 }
                if guardian.enabled {
                    SettingsDivider()
                    SettingsToggle(L("Uyarıları bildirim olarak gönder"), note: L("Kapalıyken uyarılar yalnızca Gözetim sekmesinde birikir."),
                                   isOn: guardian.notify) { guardian.notify = $0 }
                }
            }

            if guardian.enabled {
                SettingsGroup(title: L("Şu durumlarda uyar")) {
                    SettingsToggle(L("Disk doluyor"), note: L("Yer azaldığında ya da hızla azalmaya başladığında."),
                                   isOn: guardian.watchDisk) { guardian.watchDisk = $0 }
                    SettingsDivider()
                    SettingsToggle(L("Bellek yetmiyor"), note: L("Açık programlar Mac'i yavaşlatmaya başladığında."),
                                   isOn: guardian.watchMemory) { guardian.watchMemory = $0 }
                    SettingsDivider()
                    SettingsToggle(L("Bir program Mac'i yoruyor"), note: L("İşlemciyi uzun süre meşgul ettiğinde."),
                                   isOn: guardian.watchCPU) { guardian.watchCPU = $0 }
                    SettingsDivider()
                    SettingsToggle(L("Bir program aniden büyüyor"), note: L("Diskte kapladığı yer kısa sürede çok arttığında."),
                                   isOn: guardian.watchGrowth) { guardian.watchGrowth = $0 }
                }
            }

            SettingsGroup(title: L("Haberler")) {
                if guardian.enabled {
                    SettingsToggle(L("Haftalık özet"), note: L("Pazartesi günleri Mac'inde o hafta ne olduğunun kısa özeti."),
                                   isOn: guardian.weeklySummary) { guardian.weeklySummary = $0 }
                    SettingsDivider()
                }
                if updater.repo != nil {
                    SettingsToggle(L("Duyurular"), note: L("Geliştiriciden kısa haberler. Kapatırsan uygulamanın içinde de gösterilmez."),
                                   isOn: announcements.enabled) { announcements.enabled = $0 }
                    SettingsDivider()
                }
                SettingsNavRow(title: L("Yeni sürüm haberleri"), note: L("Güncellemeler sayfasından ayarlanır."),
                               value: updater.autoCheck ? L("Açık") : L("Kapalı")) { nav.open(.updates) }
            }
        }
    }
}

// MARK: permissions and privacy

struct PrivacySettingsPage: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var admin = AdminAccess.shared

    var body: some View {
        SettingsPageBody(title: SettingsPage.privacy.title,
                         intro: L("Kartov'un neye erişebildiği ve bilgilerinle ne yaptığı.")) {
            SettingsGroup(title: L("İzinler"),
                          footer: model.hasFullDiskAccess ? nil
                          : L("Açılan listede Kartov Cleaner'ın anahtarını aç, sonra buraya dönüp yeniden başlat.")) {
                if model.hasFullDiskAccess {
                    SettingsStatus(tone: .good, title: L("Tam Disk Erişimi"),
                                   note: L("Verildi. Kartov bütün önbellek klasörlerini görebiliyor.")) { EmptyView() }
                } else {
                    SettingsStatus(tone: .attention, title: L("Tam Disk Erişimi"),
                                   note: L("Verilmedi. Kartov bazı klasörleri göremediği için daha az yer buluyor.")) {
                        HStack(spacing: 8) {
                            Button(L("Yeniden başlat")) { Permissions.relaunch() }.buttonStyle(SecondaryButtonStyle())
                            Button(L("İzin ver")) { Permissions.openFullDiskAccessSettings() }.buttonStyle(PrimaryButtonStyle())
                        }
                    }
                }
            }

            SettingsGroup(title: L("Mac şifren"), footer: adminFooter) {
                SettingsToggle(L("Şifre sormadan yap"), note: adminNote, isOn: admin.enabled) { on in
                    if on { admin.enable() } else { admin.disable() }
                }
                .disabled(admin.busy)
                .opacity(admin.busy ? 0.5 : 1)
                if let m = admin.message {
                    SettingsDivider()
                    SettingsStatus(tone: .attention, title: m, note: L("İstersen yeniden deneyebilirsin.")) { EmptyView() }
                }
            }

            SettingsGroup(title: L("Gizlilik")) {
                SettingsStatus(tone: .good, title: L("Dosyaların Mac'inde kalır"),
                               note: L("Dosyaların ve ölçümlerin hiçbir yere gönderilmez. Kartov internete yalnızca güncelleme ve duyurular için bağlanır.")) { EmptyView() }
            }
        }
    }
}

extension PrivacySettingsPage {
    fileprivate var adminNote: String {
        if admin.busy { return L("macOS'un penceresi bekleniyor…") }
        return admin.enabled
            ? L("Belleği boşaltma, internet önbelleğini yenileme ve Sistem Verisi temizliği şifre sormadan yapılır. Kapatırken macOS bir kez daha sorar.")
            : L("Bu üç iş için macOS her seferinde şifreni sorar. Açarsan son bir kez sorar, sonra sormaz.")
    }

    fileprivate var adminFooter: String {
        L("Kartov şifreni görmez ve saklamaz; izni macOS verir. Açıkken Mac'indeki başka programlar da bu üç işi şifresiz yapabilir. Kişisel dosyalarına hiçbiri dokunmaz, Sistem Verisi temizliği Kartov'da yine önce sorar.")
    }
}

// MARK: updates and about

struct UpdatesSettingsPage: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var updater = Updater.shared

    var body: some View {
        SettingsPageBody(title: SettingsPage.updates.title,
                         intro: L("Yeni sürümler ve Kartov hakkında.")) {
            SettingsGroup {
                SettingsRowLayout {
                    HStack(spacing: 16) {
                        KartovLogo(size: 64)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Kartov Cleaner").font(.system(size: 20, weight: .medium))
                            Text(L("Sürüm {0}", updater.currentVersion))
                                .font(.system(size: 13).monospacedDigit()).foregroundStyle(KColor.textMuted)
                            Text(status.text).font(.system(size: 12)).foregroundStyle(status.color)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 8)
                } trailing: { action }
            }

            if updater.repo != nil {
                SettingsGroup {
                    SettingsToggle(L("Güncellemeleri kendiliğinden denetle"), note: L("Yeni sürüm varsa haber verir, sen onaylamadan kurmaz."),
                                   isOn: updater.autoCheck) { updater.autoCheck = $0 }
                    if updater.autoCheck {
                        SettingsDivider()
                        SettingsChoice(title: L("Ne sıklıkla"), options: Updater.intervals, name: intervalTitle,
                                       selection: updater.interval) { updater.interval = $0 }
                    }
                }
            }

            SettingsGroup(title: L("Kartov'u tanı"), footer: L("Umut Kartov tarafından tasarlandı. Ücretsiz ve açık kaynak.")) {
                SettingsNavRow(title: L("Son yenilikler"), note: L("Her sürümde neyin değiştiği")) { updater.openWhatsNew() }
                SettingsDivider()
                SettingsNavRow(title: L("Tanıtım turu"), note: L("Kartov'un bölümlerini adım adım gösterir.")) { model.openTutorial() }
                if let repo = updater.repo, let url = URL(string: "https://github.com/\(repo)") {
                    SettingsDivider()
                    SettingsNavRow(title: L("GitHub sayfası"), note: "github.com/\(repo)") { NSWorkspace.shared.open(url) }
                }
            }
        }
    }

    private var status: (text: String, color: Color) {
        switch updater.phase {
        case .checking: return (L("Yeni sürüm aranıyor…"), KColor.textMuted)
        case .downloading(let f): return (L("İndiriliyor… %{0}", Int(f * 100)), KColor.textMuted)
        case .installing: return (L("Doğrulanıyor ve kuruluyor; Kartov birazdan yeniden açılacak…"), KColor.textMuted)
        case .failed(let m): return (m, KColor.warning)
        case .upToDate: return (L("En son sürümü kullanıyorsun."), KColor.success)
        default: break
        }
        if let r = updater.release { return (L("{0} sürümü hazır.", r.version), KColor.text) }
        if updater.repo == nil { return (L("Güncelleme deposu ayarlanmamış."), KColor.textMuted) }
        if let d = updater.lastCheck { return (L("Son denetim: {0}", relativeDay(d)), KColor.textMuted) }
        return (L("Henüz denetlenmedi."), KColor.textMuted)
    }

    @ViewBuilder private var action: some View {
        switch updater.phase {
        case .checking, .downloading, .installing:
            ProgressView().controlSize(.small)
        default:
            if updater.release != nil {
                Button(L("Güncelle")) { updater.showSheet = true }.buttonStyle(PrimaryButtonStyle())
            } else if updater.repo != nil {
                Button(L("Şimdi denetle")) { Task { await updater.check(userInitiated: true) } }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    private func intervalTitle(_ minutes: Int) -> String {
        switch minutes {
        case 10: return L("Her 10 dakikada")
        case 60: return L("Saatte bir")
        default: return L("Günde bir")
        }
    }
}

// MARK: reset

struct ResetSettingsPage: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var nav = SettingsNav.shared

    var body: some View {
        SettingsPageBody(title: SettingsPage.reset.title,
                         intro: L("Buradakilerin hiçbiri dosyalarını silmez. Her biri önce onayını ister.")) {
            SettingsGroup(title: L("Tek tek")) {
                SettingsRow(L("Temizlik geçmişi"),
                            note: model.history.isEmpty ? L("Geçmiş boş.")
                            : L("{0} kayıt. Silersen eski temizlikleri geri alamazsın.", model.history.count)) {
                    Button(L("Sil…")) { nav.confirm = .history }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(model.history.isEmpty).opacity(model.history.isEmpty ? 0.4 : 1)
                }
                SettingsDivider()
                let noChoices = model.kept.isEmpty && model.optedIn.isEmpty
                SettingsRow(L("Temizlik seçimleri"),
                            note: noChoices ? L("Kartov'un önerilerini değiştirmedin.")
                            : L("Korumaya aldığın ya da temizlenmesi için seçtiğin öğeler.")) {
                    Button(L("Sıfırla…")) { nav.confirm = .choices }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(noChoices).opacity(noChoices ? 0.4 : 1)
                }
                SettingsDivider()
                SettingsRow(L("Gözetim kayıtları"), note: L("Uyarılar, disk ve enerji ölçümleri.")) {
                    Button(L("Sil…")) { nav.confirm = .guardian }.buttonStyle(SecondaryButtonStyle())
                }
            }

            SettingsGroup(title: L("Baştan başla")) {
                SettingsRow(L("Her şeyi sıfırla"), note: L("Kartov yeni kurulmuş gibi olur ve yeniden başlar.")) {
                    Button(L("Sıfırla…")) { nav.confirm = .everything }.buttonStyle(SecondaryButtonStyle())
                }
            }
        }
    }
}
