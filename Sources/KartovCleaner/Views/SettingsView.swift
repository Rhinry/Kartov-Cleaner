import SwiftUI
import KartovCore

/// Everything adjustable in one place, in plain cards: general, cleaning, permissions, data, about.
struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var profiles = ProfileStore.shared
    @ObservedObject private var guardian = Guardian.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(L("Ayarlar")).font(.system(size: 26, weight: .bold))
                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 16) {
                        UpdateSettingsCard()
                        generalCard
                        profileCard
                        cleaningCard
                    }
                    VStack(spacing: 16) {
                        guardianCard
                        permissionsCard
                        dataCard
                        aboutCard
                    }
                }
            }
            .padding(.horizontal, 28).padding(.vertical, 20)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .onAppear { model.refreshPermissions() }
    }

    // MARK: work profile

    private var profileCard: some View {
        let active = profiles.active
        let settings = profiles.settings(for: active)
        return SettingsCard(title: L("Çalışma profili"), symbol: "person.crop.rectangle.stack") {
            Picker("", selection: Binding(get: { profiles.active }, set: { profiles.active = $0 })) {
                ForEach(WorkspaceProfile.allCases) { p in Text(p.title).tag(p) }
            }
            .pickerStyle(.segmented).labelsHidden()
            Text(active.summary).font(.system(size: 12)).foregroundStyle(KColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            Text(L("Korunan önbellekler")).font(.system(size: 12, weight: .semibold)).padding(.top, 4)
            Text(L("Bu profilde temizlikte varsayılan olarak korunur; otomatik bakım ve hızlı temizlik dokunmaz. Bulunanlar ekranında tek tek yine temizleyebilirsin."))
                .font(.system(size: 11)).foregroundStyle(KColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            ForEach([CategoryGroup.creative, .developer, .browsers, .apps, .logs], id: \.self) { g in
                SettingsRow(g.title) {
                    Toggle("", isOn: Binding(get: { settings.protected.contains(g) }, set: { on in
                        profiles.update(active) { if on { $0.protected.insert(g) } else { $0.protected.remove(g) } }
                    })).labelsHidden()
                }
            }
            Divider().overlay(KColor.border)
            SettingsRow(L("Yoğun programlar için uyarma"), note: L("Profilin ağır programları (render, derleme, oyun) işlemciyi yorsa da Gözetim uyarı vermez.")) {
                Toggle("", isOn: Binding(get: { settings.quietHeavy }, set: { on in profiles.update(active) { $0.quietHeavy = on } }))
                    .labelsHidden()
            }
            SettingsRow(L("Oyun açıkken bildirim gönderme"), note: L("Uyarılar yine Gözetim'de birikir.")) {
                Toggle("", isOn: Binding(get: { settings.quietWhilePlaying }, set: { on in profiles.update(active) { $0.quietWhilePlaying = on } }))
                    .labelsHidden()
            }
            Button(L("Bu profili varsayılana döndür")) { profiles.reset(active) }
                .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(KColor.accentSoft)
        }
    }

    // MARK: guardian

    private var guardianCard: some View {
        SettingsCard(title: L("Gözetim"), symbol: "shield.lefthalf.filled") {
            SettingsRow(L("Mac'ime göz kulak ol"), note: L("Dakikada bir bakar; yalnızca okur, hiçbir şey silmez.")) {
                Toggle("", isOn: Binding(get: { guardian.enabled }, set: { guardian.enabled = $0 })).labelsHidden()
            }
            SettingsRow(L("Bildirim gönder")) {
                Toggle("", isOn: Binding(get: { guardian.notify }, set: { guardian.notify = $0 })).labelsHidden()
            }
            .disabled(!guardian.enabled)
            Divider().overlay(KColor.border)
            SettingsRow(L("İşlemciyi uzun süre yoran programlar")) {
                Toggle("", isOn: Binding(get: { guardian.watchCPU }, set: { guardian.watchCPU = $0 })).labelsHidden()
            }
            SettingsRow(L("Dolmak üzere olan bellek")) {
                Toggle("", isOn: Binding(get: { guardian.watchMemory }, set: { guardian.watchMemory = $0 })).labelsHidden()
            }
            SettingsRow(L("Dolan ya da hızla dolan disk")) {
                Toggle("", isOn: Binding(get: { guardian.watchDisk }, set: { guardian.watchDisk = $0 })).labelsHidden()
            }
            SettingsRow(L("Aniden büyüyen programlar"), note: L("Programların Library dosyaları altı saatte bir ölçülür.")) {
                Toggle("", isOn: Binding(get: { guardian.watchGrowth }, set: { guardian.watchGrowth = $0 })).labelsHidden()
            }
            Button(L("Gözetim ölçümlerini sıfırla")) { guardian.resetData() }
                .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(KColor.accentSoft)
        }
    }

    // MARK: general

    private var generalCard: some View {
        SettingsCard(title: L("Genel"), symbol: "slider.horizontal.3") {
            SettingsRow(L("Dil"), note: L("Uygulamanın dili. Değiştirince Kartov yeniden başlar.")) {
                Picker("", selection: Binding(get: { model.language }, set: { model.language = $0 })) {
                    ForEach(AppLanguage.allCases) { l in Text(l.nativeName).tag(l) }
                }
                .labelsHidden().fixedSize()
            }
            if model.languageNeedsRestart {
                HStack {
                    Image(systemName: "arrow.clockwise.circle.fill").foregroundStyle(KColor.accent)
                    Text(L("Yeni dil, Kartov yeniden başlayınca geçerli olur.")).font(.system(size: 12))
                    Spacer()
                    Button(L("Şimdi yeniden başlat")) { Permissions.relaunch() }.buttonStyle(PrimaryButtonStyle())
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(KColor.accent.opacity(0.1)))
            }
            Divider().overlay(KColor.border)
            SettingsRow(L("Mac açılınca başlat")) {
                Toggle("", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) })).labelsHidden()
            }
            SettingsRow(L("Arka planda çalış"), note: L("Pencereyi kapatınca Kartov menü çubuğunda açık kalır.")) {
                Toggle("", isOn: Binding(get: { model.runInBackground }, set: { model.runInBackground = $0 })).labelsHidden()
            }
            SettingsRow(L("Menü çubuğu simgesi")) {
                Toggle("", isOn: Binding(get: { model.showMenuBarIcon }, set: { model.showMenuBarIcon = $0 })).labelsHidden()
            }
            SettingsRow(L("Simgeye tıklayınca")) {
                Picker("", selection: Binding(get: { model.menuBarAction }, set: { model.menuBarAction = $0 })) {
                    ForEach(MenuBarAction.allCases) { a in Text(a.title).tag(a) }
                }
                .labelsHidden().fixedSize()
            }
            .disabled(!model.showMenuBarIcon)
        }
    }

    // MARK: cleaning

    private var cleaningCard: some View {
        SettingsCard(title: L("Temizlik"), symbol: "sparkles") {
            SettingsRow(L("Açılışta tara"), note: L("Ana sayfa açılınca dünyanın ne kadar kirlendiğine bakar. Hiçbir şey silmez.")) {
                Toggle("", isOn: Binding(get: { model.scanOnLaunch }, set: { model.scanOnLaunch = $0 })).labelsHidden()
            }
            SettingsRow(L("Temizlik bitince ses çal")) {
                Toggle("", isOn: Binding(get: { model.cleanSound }, set: { model.cleanSound = $0 })).labelsHidden()
            }
            SettingsRow(L("Otomatik bakım"), note: model.autoEnabled ? model.autoScheduleText : L("Kapalı")) {
                Button(L("Düzenle")) { model.section = .maintenance }.buttonStyle(SecondaryButtonStyle())
            }
            Divider().overlay(KColor.border)
            VStack(alignment: .leading, spacing: 8) {
                guarantee(L("Kişisel dosyalar kalıcı olarak silinmez, çöp kutusuna gider."))
                guarantee(L("Tarama geçmişi silinmeden önce her zaman sorulur."))
                guarantee(L("Açık olan programların önbelleğine dokunulmaz."))
            }
        }
    }

    private func guarantee(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "checkmark.shield.fill").font(.system(size: 11)).foregroundStyle(KColor.success)
            Text(text).font(.system(size: 12)).foregroundStyle(KColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: permissions

    private var permissionsCard: some View {
        SettingsCard(title: L("İzinler"), symbol: "lock.shield") {
            SettingsRow(L("Tam Disk Erişimi"),
                        note: model.hasFullDiskAccess ? L("Verildi. Kartov tam performansla çalışıyor.")
                                                      : L("Verilmedi. Bazı klasörlere bakılamıyor.")) {
                if model.hasFullDiskAccess {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(KColor.success).font(.system(size: 16))
                } else {
                    Button(L("İzin ver")) { Permissions.openFullDiskAccessSettings() }.buttonStyle(PrimaryButtonStyle())
                }
            }
            SettingsRow(L("Yönetici izni"), note: L("Belleği boşaltmak ve Sistem Verisi'ni temizlemek için macOS her seferinde şifreni sorar. Kartov şifreni saklamaz.")) {
                EmptyView()
            }
        }
    }

    // MARK: data

    private var dataCard: some View {
        SettingsCard(title: L("Veriler"), symbol: "externaldrive") {
            SettingsRow(L("Temizlik geçmişi"), note: L("{0} kayıt", model.history.count)) {
                Button(L("Geçmişi sil")) { model.clearHistory() }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(model.history.isEmpty)
            }
            SettingsRow(L("Korunan öğeler"), note: L("{0} öğe korunuyor", model.kept.count)) {
                Button(L("Sıfırla")) { model.resetChoices() }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(model.kept.isEmpty)
            }
            SettingsRow(L("Tanıtım turu")) {
                Button(L("Turu başlat")) { model.openTutorial() }.buttonStyle(SecondaryButtonStyle())
            }
            Divider().overlay(KColor.border)
            if model.confirmResetAll {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("Bütün ayarlar, geçmiş ve korunan öğeler silinir; Kartov ilk günkü haline döner ve yeniden başlar. Dosyalarına dokunulmaz."))
                        .font(.system(size: 12)).foregroundStyle(KColor.heat)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Spacer()
                        Button(L("Vazgeç")) { model.confirmResetAll = false }.buttonStyle(SecondaryButtonStyle())
                        Button(L("Evet, sıfırla")) { model.resetAllSettings() }.buttonStyle(PrimaryButtonStyle())
                    }
                }
            } else {
                SettingsRow(L("Her şeyi sıfırla")) {
                    Button(L("Sıfırla…")) { model.confirmResetAll = true }.buttonStyle(SecondaryButtonStyle())
                }
            }
        }
    }

    // MARK: about

    private var aboutCard: some View {
        HStack(spacing: 14) {
            KartovLogo(size: 52)
            VStack(alignment: .leading, spacing: 3) {
                KartovBrand()
                Text(L("Sürüm {0}", Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.2"))
                    .font(.system(size: 12)).foregroundStyle(KColor.textMuted)
                Text(L("Umut Kartov tarafından tasarlandı. Kartov hiçbir veriyi internete göndermez."))
                    .font(.system(size: 12)).foregroundStyle(KColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .kCard(padding: 18, radius: 18)
    }
}

struct SettingsCard<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(KColor.textMuted)
            content()
        }
        .kCard(padding: 18, radius: 18)
    }
}

struct SettingsRow<Control: View>: View {
    let title: String
    var note: String? = nil
    @ViewBuilder var control: () -> Control

    init(_ title: String, note: String? = nil, @ViewBuilder control: @escaping () -> Control) {
        self.title = title
        self.note = note
        self.control = control
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                if let note {
                    Text(note).font(.system(size: 11)).foregroundStyle(KColor.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            control()
        }
        .frame(minHeight: 30)
    }
}
