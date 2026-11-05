import SwiftUI
import KartovCore

/// Every program at a glance: what is open and what it uses right now (memory, processor, disk),
/// what you use most, what takes the most space, and what you have not opened in a long time.
struct AnalysisView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                stats
                if let m = model.analysisMessage {
                    Label(m, systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(KColor.success)
                }
                runningCard
                HStack(alignment: .top, spacing: 16) {
                    mostUsedCard
                    largestCard
                }
                forgottenCard
            }
            .padding(.horizontal, 28).padding(.vertical, 20)
            .frame(maxWidth: 1180, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .onAppear { model.startAnalysis() }
        .onDisappear { model.stopAnalysis() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Analiz")).font(.system(size: 26, weight: .bold))
                Text(L("Programların ne kadar bellek, işlemci ve disk kullandığını, hangilerini çok kullandığını gör; istediğine buradan müdahale et."))
                    .font(.system(size: 13)).foregroundStyle(KColor.textMuted)
            }
            Spacer()
            Text(L("Her 2 saniyede yenilenir")).font(.system(size: 11)).foregroundStyle(KColor.textMuted)
        }
    }

    // MARK: four numbers on top

    private var stats: some View {
        let mem = model.runningApps.reduce(UInt64(0)) { $0 + $1.memory }
        let cpu = model.runningApps.reduce(0.0) { $0 + $1.cpu }
        let installedBytes = model.installedApps.reduce(Int64(0)) { $0 + ($1.size ?? 0) }
        return HStack(spacing: 12) {
            StatTile(symbol: "app.badge", tint: KColor.accent, value: "\(model.runningApps.count)", label: L("açık program"))
            StatTile(symbol: "memorychip", tint: Color.purple, value: KBytes.format(Int64(mem)), label: L("programların belleği"))
            StatTile(symbol: "cpu", tint: KColor.success, value: "%\(Int(cpu * 100))", label: L("işlemci (tek çekirdek = %100)"))
            StatTile(symbol: "internaldrive", tint: KColor.warning,
                     value: model.installedApps.isEmpty ? "…" : KBytes.format(installedBytes),
                     label: L("{0} yüklü program", model.installedApps.count))
        }
    }

    // MARK: open programs

    private var runningCard: some View {
        let list = model.sortedRunning
        let maxMem = Double(list.map(\.memory).max() ?? 1)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(L("Şu an açık olanlar"), systemImage: "play.circle").font(.system(size: 14, weight: .semibold))
                Spacer()
                Picker("", selection: Binding(get: { model.runningSort }, set: { model.runningSort = $0 })) {
                    ForEach(AppModel.RunningSort.allCases) { s in Text(s.title).tag(s) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 240)
            }
            HStack(spacing: 10) {
                Text(L("Program")).frame(maxWidth: .infinity, alignment: .leading)
                Text(L("Bellek")).frame(width: 170, alignment: .leading)
                Text(L("İşlemci")).frame(width: 80, alignment: .trailing)
                Text(L("Disk")).frame(width: 90, alignment: .trailing)
                Text(L("Süre")).frame(width: 90, alignment: .trailing)
                Color.clear.frame(width: 120, height: 1)
            }
            .font(.system(size: 11, weight: .medium)).foregroundStyle(KColor.textMuted)
            .padding(.horizontal, 8)
            if list.isEmpty {
                Text(L("Okunuyor…")).font(.system(size: 12)).foregroundStyle(KColor.textMuted).padding(8)
            }
            ForEach(list) { a in
                HStack(spacing: 10) {
                    HStack(spacing: 10) {
                        if let icon = a.icon { Image(nsImage: icon).resizable().frame(width: 24, height: 24) }
                        Text(a.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 8) {
                        Bar(fraction: Double(a.memory) / maxMem, tint: Color.purple).frame(width: 80)
                        Text(KBytes.format(Int64(a.memory))).font(.system(size: 12).monospacedDigit())
                    }
                    .frame(width: 170, alignment: .leading)
                    Text("%\(Int(a.cpu * 100))").font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(a.cpu > 0.8 ? KColor.heat : KColor.text)
                        .frame(width: 80, alignment: .trailing)
                    Text(a.diskRate >= 1_000 ? L("{0}/sn", KBytes.format(Int64(a.diskRate))) : "–")
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(KColor.textMuted)
                        .frame(width: 90, alignment: .trailing)
                        .help(L("Açıldığından beri {0} okudu ve yazdı", KBytes.format(Int64(a.diskTotal))))
                    Text(a.launched.map { shortDuration(since: $0) } ?? "–")
                        .font(.system(size: 12)).foregroundStyle(KColor.textMuted)
                        .frame(width: 90, alignment: .trailing)
                    HStack(spacing: 6) {
                        Button(L("Kapat")) { model.quitApp(pid: a.id) }
                            .buttonStyle(SecondaryButtonStyle())
                            .help(L("{0} kapanır; kaydedilmemiş işin varsa sorar.", a.name))
                        Menu {
                            Button(L("Zorla kapat")) { model.forceQuit(pid: a.id) }
                            if let id = a.bundleID {
                                Button(L("Bağlantılı dosyalar")) { AppMap.shared.open(bundleID: id, name: a.name, url: a.url) }
                            }
                            if let url = a.url { Button(L("Finder'da göster")) { Finder.reveal(url.path) } }
                        } label: { Image(systemName: "ellipsis.circle") }
                        .menuStyle(.borderlessButton).fixedSize()
                    }
                    .frame(width: 120, alignment: .trailing)
                }
                .padding(.horizontal, 8).frame(height: 38)
                .background(RoundedRectangle(cornerRadius: 8).fill(KColor.surface2.opacity(0.5)))
            }
        }
        .kCard(padding: 18, radius: 18)
    }

    // MARK: most used

    private var mostUsedCard: some View {
        AppListCard(title: L("En çok kullandıkların"), symbol: "star.fill",
                    loading: model.installedApps.isEmpty,
                    empty: L("macOS kullanım sayılarını henüz bilmiyor."),
                    apps: Array(model.mostUsedApps.prefix(7))) { app in
            Text(L("{0} kez açıldı", app.useCount ?? 0)).font(.system(size: 12, weight: .semibold).monospacedDigit())
            Button(L("Aç")) { model.openApp(app.url) }.buttonStyle(SecondaryButtonStyle())
        }
    }

    // MARK: largest

    private var largestCard: some View {
        AppListCard(title: L("Diskte en çok yer kaplayanlar"), symbol: "internaldrive.fill",
                    loading: model.largestApps.isEmpty,
                    empty: "",
                    apps: Array(model.largestApps.prefix(7))) { app in
            Text(KBytes.format(app.size ?? 0)).font(.system(size: 12, weight: .semibold).monospacedDigit())
            RemoveButton(app: app)
        }
    }

    // MARK: forgotten

    private var forgottenCard: some View {
        AppListCard(title: L("Uzun süredir açmadıkların"), symbol: "moon.zzz.fill",
                    subtitle: L("Son 3 ayda açılmamış programlar. Kaldırırsan ayarları ve önbellekleriyle birlikte çöp kutusuna gider; Geçmiş'ten geri alabilirsin."),
                    loading: model.installedApps.isEmpty,
                    empty: L("Hepsini yakın zamanda kullanmışsın."),
                    apps: Array(model.forgottenApps.prefix(8))) { app in
            Text(app.size.map { KBytes.format($0) } ?? "…").font(.system(size: 12, weight: .semibold).monospacedDigit())
            RemoveButton(app: app)
        }
    }

    private func shortDuration(since d: Date) -> String {
        let s = Int(Date().timeIntervalSince(d))
        if s < 3600 { return L("{0} dk", max(1, s / 60)) }
        if s < 86_400 { return L("{0} sa", s / 3600) }
        return L("{0} gün", s / 86_400)
    }
}

/// Small number tile.
struct StatTile: View {
    let symbol: String
    let tint: Color
    let value: String
    let label: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: 10).fill(tint.opacity(0.14)))
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(.system(size: 20, weight: .bold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
                Text(label).font(.system(size: 11)).foregroundStyle(KColor.textMuted).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .kCard(padding: 14, radius: 16)
    }
}

/// A thin horizontal bar.
struct Bar: View {
    let fraction: Double
    let tint: Color
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(KColor.surface2)
                Capsule().fill(tint).frame(width: max(3, g.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: 6)
    }
}

/// A card listing programs, each row: icon, name, last opened, then the given trailing views.
struct AppListCard<Trailing: View>: View {
    let title: String
    let symbol: String
    var subtitle: String? = nil
    let loading: Bool
    let empty: String
    let apps: [InstalledAppInfo]
    @ViewBuilder var trailing: (InstalledAppInfo) -> Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol).font(.system(size: 14, weight: .semibold))
            if let subtitle {
                Text(subtitle).font(.system(size: 12)).foregroundStyle(KColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if loading {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text(L("Programlar okunuyor…")).font(.system(size: 12)) }
                    .foregroundStyle(KColor.textMuted)
            } else if apps.isEmpty {
                if !empty.isEmpty { Text(empty).font(.system(size: 12)).foregroundStyle(KColor.textMuted) }
            }
            ForEach(apps) { app in
                HStack(spacing: 10) {
                    Image(nsImage: app.icon).resizable().frame(width: 24, height: 24)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(app.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                        Text(app.lastUsed.map { L("son açılış {0}", relativeDay($0)) } ?? L("hiç açılmamış"))
                            .font(.system(size: 11)).foregroundStyle(KColor.textMuted)
                    }
                    Spacer(minLength: 8)
                    trailing(app)
                }
                .frame(height: 36)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .kCard(padding: 18, radius: 18)
    }
}

/// "Kaldır" that asks once more inline before moving the program to the Trash.
struct RemoveButton: View {
    @EnvironmentObject var model: AppModel
    let app: InstalledAppInfo
    var body: some View {
        if app.protected {
            Text(L("macOS'un")).font(.system(size: 11)).foregroundStyle(KColor.textMuted)
                .help(L("macOS ile gelen bu program kaldırılamaz."))
        } else if model.removeCandidate == app.id {
            HStack(spacing: 4) {
                Button(L("Vazgeç")) { model.removeCandidate = nil }.buttonStyle(SecondaryButtonStyle())
                Button(L("Çöpe taşı")) { model.removeApp(app) }.buttonStyle(PrimaryButtonStyle())
            }
        } else {
            Menu {
                Button(L("Kaldır…")) { model.removeCandidate = app.id }
                if let id = app.bundleID {
                    Button(L("Bağlantılı dosyalar")) { AppMap.shared.open(bundleID: id, name: app.name, url: app.url) }
                }
                Button(L("Finder'da göster")) { Finder.reveal(app.url.path) }
            } label: { Image(systemName: "ellipsis.circle") }
            .menuStyle(.borderlessButton).fixedSize()
        }
    }
}
