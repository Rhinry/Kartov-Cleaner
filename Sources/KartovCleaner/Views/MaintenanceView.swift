import SwiftUI
import KartovCore

/// Automatic maintenance, kept simple: one status card, then three small cards
/// (when · what · rules) and one line about what is never touched.
struct MaintenanceView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                statusCard
                HStack(alignment: .top, spacing: 16) {
                    whenCard
                    whatCard
                    rulesCard
                }
                .fixedSize(horizontal: false, vertical: true)
                .disabled(!model.autoEnabled)
                .opacity(model.autoEnabled ? 1 : 0.45)
                backgroundCard
                neverLine
            }
            .padding(.horizontal, 28).padding(.vertical, 22)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: status

    private var statusCard: some View {
        HStack(spacing: 18) {
            Globe(dirt: 0, speed: model.autoRunning ? 1.4 : (model.autoEnabled ? 0.3 : 0), size: 52)
                .frame(width: 80, height: 80)
                .saturation(model.autoEnabled ? 1 : 0)
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Otomatik bakım")).font(.system(size: 20, weight: .bold))
                Text(subtitle).font(.system(size: 13)).foregroundStyle(KColor.textMuted)
                if let m = model.autoMessage {
                    Text(m).font(.system(size: 12, weight: .medium)).foregroundStyle(KColor.success)
                }
            }
            Spacer(minLength: 12)
            if model.autoEnabled {
                Button(model.autoRunning ? L("Çalışıyor…") : L("Şimdi çalıştır")) { model.runAutoMaintenance() }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(model.autoRunning || model.phase == .scanning || model.phase == .cleaning || model.autoGroups.isEmpty)
            }
            Button(model.autoEnabled ? L("Durdur") : L("Aktif et")) { model.autoEnabled.toggle() }
                .buttonStyle(model.autoEnabled ? AnyButtonStyle(SecondaryButtonStyle()) : AnyButtonStyle(PrimaryButtonStyle()))
        }
        .kCard(padding: 20, radius: 18)
    }

    private var subtitle: String {
        guard model.autoEnabled else { return L("Kapalı. Aç, Kartov önbellekleri seçtiğin zamanda kendisi temizlesin.") }
        var parts = [model.autoScheduleText]
        if let last = model.lastAutoRun { parts.append(L("son: {0}", relativeDay(last))) }
        return parts.joined(separator: " · ")
    }

    // MARK: when

    private var whenCard: some View {
        SmallCard(title: L("Ne zaman"), symbol: "calendar") {
            Picker("", selection: Binding(get: { model.autoFrequency }, set: { model.autoFrequency = $0 })) {
                ForEach(AutoFrequency.allCases) { f in Text(f.title).tag(f) }
            }
            .pickerStyle(.segmented).labelsHidden()

            if model.autoFrequency == .weekly {
                row(L("Gün")) {
                    Picker("", selection: Binding(get: { model.autoWeekday }, set: { model.autoWeekday = $0 })) {
                        ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { d in Text(AppModel.weekdayNames[d - 1]).tag(d) }
                    }
                    .labelsHidden().fixedSize()
                }
            }
            if model.autoFrequency == .monthly {
                row(L("Gün")) {
                    Picker("", selection: Binding(get: { model.autoMonthDay }, set: { model.autoMonthDay = $0 })) {
                        ForEach(1...28, id: \.self) { d in Text("\(d).").tag(d) }
                    }
                    .labelsHidden().fixedSize()
                }
            }
            row(L("Saat")) {
                Picker("", selection: Binding(get: { model.autoHour }, set: { model.autoHour = $0 })) {
                    ForEach(0..<24, id: \.self) { h in Text(String(format: "%02d:00", h)).tag(h) }
                }
                .labelsHidden().fixedSize()
            }
            row(L("Sadece şarjdayken")) {
                Toggle("", isOn: Binding(get: { model.autoOnlyOnPower }, set: { model.autoOnlyOnPower = $0 }))
                    .labelsHidden()
            }
        }
    }

    // MARK: what

    private var whatCard: some View {
        SmallCard(title: L("Ne temizlensin"), symbol: "checklist") {
            ForEach(AppModel.autoAllowedGroups, id: \.self) { g in
                row(g.title, symbol: g.symbol) {
                    HStack(spacing: 8) {
                        if let p = model.autoPreview, model.autoGroups.contains(g) {
                            Text(KBytes.format(p[g] ?? 0)).font(.system(size: 11).monospacedDigit())
                                .foregroundStyle(KColor.textMuted)
                        }
                        Toggle("", isOn: Binding(get: { model.autoGroups.contains(g) }, set: { v in
                            if v { model.autoGroups.insert(g) } else { model.autoGroups.remove(g) }
                            model.autoPreview = nil
                        }))
                        .labelsHidden()
                    }
                }
            }
            Button {
                model.previewAutoMaintenance()
            } label: {
                Text(model.autoPreviewing ? L("Bakılıyor…")
                     : (model.autoPreview.map { L("Şu an {0} açar", KBytes.format($0.values.reduce(0, +))) } ?? L("Ne kadar yer açar?")))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(model.autoPreviewing)
            .padding(.top, 4)
        }
    }

    // MARK: rules

    private static let thresholds: [Int64] = [0, 500_000_000, 1_000_000_000, 5_000_000_000]
    private static let ages: [Int] = [0, 3, 7, 30]

    private var rulesCard: some View {
        SmallCard(title: L("Kurallar"), symbol: "slider.horizontal.3") {
            row(L("Ne kadar birikince")) {
                Picker("", selection: Binding(get: { model.autoMinBytes }, set: { model.autoMinBytes = $0 })) {
                    ForEach(Self.thresholds, id: \.self) { t in Text(t == 0 ? L("Her zaman") : KBytes.format(t)).tag(t) }
                }
                .labelsHidden().fixedSize()
            }
            row(L("Dosya yaşı")) {
                Picker("", selection: Binding(get: { model.autoMinAgeDays }, set: { model.autoMinAgeDays = $0 })) {
                    ForEach(Self.ages, id: \.self) { a in Text(a == 0 ? L("Hepsi") : L("{0}+ gün", a)).tag(a) }
                }
                .labelsHidden().fixedSize()
            }
            row(L("Bitince ses")) {
                Toggle("", isOn: Binding(get: { model.autoSound }, set: { model.autoSound = $0 })).labelsHidden()
            }
            row(L("Korunanlar")) {
                Button(model.kept.isEmpty ? L("Yok") : L("{0} öğe", model.kept.count)) {
                    model.section = model.items.isEmpty ? .scan : .results
                }
                .buttonStyle(.plain).foregroundStyle(KColor.accentSoft)
            }
        }
    }

    // MARK: background and menu bar

    private var backgroundCard: some View {
        HStack(spacing: 24) {
            Label(L("Arka plan"), systemImage: "menubar.rectangle")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(KColor.textMuted)
            row(L("Arka planda çalış")) {
                Toggle("", isOn: Binding(get: { model.runInBackground }, set: { model.runInBackground = $0 })).labelsHidden()
            }
            .frame(maxWidth: 220)
            row(L("Menü çubuğu simgesi")) {
                Toggle("", isOn: Binding(get: { model.showMenuBarIcon }, set: { model.showMenuBarIcon = $0 })).labelsHidden()
            }
            .frame(maxWidth: 230)
            row(L("Tıklayınca")) {
                Picker("", selection: Binding(get: { model.menuBarAction }, set: { model.menuBarAction = $0 })) {
                    ForEach(MenuBarAction.allCases) { a in Text(a.title).tag(a) }
                }
                .labelsHidden().fixedSize()
            }
            .disabled(!model.showMenuBarIcon)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .kCard(padding: 16, radius: 18)
    }

    // MARK: never

    private var neverLine: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.fill").foregroundStyle(KColor.keep)
            Text(L("Hiç dokunmaz: fotoğraflar, videolar, belgeler, tarama geçmişi, cihaz yedekleri, açık programlar ve \"Koru\" dediklerin."))
                .font(.system(size: 12)).foregroundStyle(KColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
    }

    private func row<C: View>(_ label: String, symbol: String? = nil, @ViewBuilder _ control: () -> C) -> some View {
        HStack(spacing: 10) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(KColor.textMuted).frame(width: 18)
            }
            Text(label).font(.system(size: 13)).lineLimit(1)
            Spacer(minLength: 8)
            control()
        }
        .frame(minHeight: 28)
    }
}

/// A plain card with a small title, used three times side by side.
struct SmallCard<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(KColor.textMuted)
                .padding(.bottom, 2)
            content()
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .frame(maxHeight: .infinity, alignment: .top)
        .kCard(padding: 18, radius: 18)
    }
}

/// Lets one button switch between the two Kartov button styles.
struct AnyButtonStyle: ButtonStyle {
    private let make: (Configuration) -> AnyView
    init<S: ButtonStyle>(_ style: S) { make = { AnyView(style.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}

/// How a personal file comes back: shown wherever the user's own files can be chosen.
struct TrashInfo: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.uturn.backward.circle.fill").foregroundStyle(KColor.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Kalıcı olarak silinmez, çöp kutusuna gider"))
                    .font(.system(size: 13, weight: .semibold))
                Text(L("Kartov hiçbir fotoğraf, video ya da kişisel dosyayı kendiliğinden seçmez. Seçtiklerin çöp kutusuna taşınır. Geri almak için Kartov'da Geçmiş › Geri al düğmesine bas ya da Finder'da Çöp Kutusu'nu açıp dosyaya sağ tıkla ve Geri Koy'u seç. Çöp kutusunu boşalttığında yer açılır."))
                    .font(.system(size: 12)).foregroundStyle(KColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(KColor.accent.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(KColor.accent.opacity(0.3)))
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        content().kCard()
    }
}
