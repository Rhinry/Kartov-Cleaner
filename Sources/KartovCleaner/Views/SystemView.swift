import SwiftUI
import KartovCore

/// "Sistem durumu": how the Mac is doing right now, and a few one-click fixes.
struct SystemView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: L("Sistem durumu")) {
                Text(L("Her 2 saniyede yenilenir")).font(.system(size: 11)).foregroundStyle(KColor.textMuted)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    summary
                    gauges
                    HStack(alignment: .top, spacing: 18) {
                        optimize.frame(maxWidth: .infinity)
                        apps.frame(maxWidth: .infinity)
                    }
                    startup
                }
                .padding(24)
                .frame(maxWidth: 1080, alignment: .leading)
            }
        }
        .onAppear { model.startMonitoring() }
        .onDisappear { model.stopMonitoring() }
    }

    // MARK: one sentence about the state

    private var health: (String, String, Color, Double) {
        let mem = model.memory?.pressure ?? 0
        let disk = DiskInfo.read()
        let diskFull = disk.total > 0 ? Double(disk.used) / Double(disk.total) : 0
        if mem > 0.9 || diskFull > 0.92 || model.cpu > 0.9 {
            return (L("Mac'in zorlanıyor"), diskFull > 0.92 ? L("Disk neredeyse dolu. Temizlik ve Tam tarama yer açar.") :
                    (mem > 0.9 ? L("Bellek dolmak üzere. Belleği rahatlat ya da çok kullanan programları kapat.") :
                     L("İşlemci tam yükte çalışıyor.")), KColor.heat, 0.7)
        }
        if mem > 0.75 || diskFull > 0.8 || model.cpu > 0.7 {
            return (L("Biraz yorgun"), L("Birkaç küçük dokunuş iyi gelir."), KColor.warning, 0.35)
        }
        return (L("Her şey yolunda"), L("Mac'in rahat çalışıyor."), KColor.success, 0)
    }

    private var summary: some View {
        let h = health
        return HStack(spacing: 18) {
            Globe(dirt: h.3, speed: 0.3, size: 56)
                .frame(width: 84, height: 84)
            VStack(alignment: .leading, spacing: 4) {
                Text(h.0).font(.system(size: 24, weight: .bold))
                Text(h.1).font(.system(size: 13)).foregroundStyle(KColor.textMuted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Label(uptimeText, systemImage: "clock").font(.system(size: 12)).foregroundStyle(KColor.textMuted)
                Label(L("Sıcaklık: {0}", SystemMonitor.thermal.0), systemImage: "thermometer.medium").font(.system(size: 12))
                    .foregroundStyle(KColor.textMuted)
            }
        }
        .kCard(padding: 18, glow: h.2)
    }

    private var uptimeText: String {
        let t = Int(SystemMonitor.uptime)
        let d = t / 86_400, h = (t % 86_400) / 3600
        return d > 0 ? L("{0} gün {1} saattir açık", d, h) : L("{0} saat {1} dakikadır açık", h, (t % 3600) / 60)
    }

    // MARK: gauges

    private var gauges: some View {
        let disk = DiskInfo.read()
        let diskFrac = disk.total > 0 ? Double(disk.used) / Double(disk.total) : 0
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
            GaugeCard(title: L("İşlemci"), value: model.cpu, big: "%\(Int(model.cpu * 100))",
                      detail: L("şu an kullanılıyor"), gradient: KGradient.accent, history: model.cpuHistory)
            GaugeCard(title: L("Bellek"), value: model.memory?.pressure ?? 0,
                      big: model.memory.map { KBytes.format(Int64($0.used)) } ?? "—",
                      detail: model.memory.map { L("{0} belleğin", KBytes.format(Int64($0.total))) } ?? "",
                      gradient: KGradient.violet, history: nil)
            GaugeCard(title: L("Disk"), value: diskFrac, big: KBytes.format(disk.free),
                      detail: L("boş · toplam {0}", KBytes.format(disk.total)), gradient: diskFrac > 0.85 ? KGradient.heat : KGradient.success,
                      history: nil)
            if let b = model.battery {
                GaugeCard(title: L("Pil"), value: Double(b.percent) / 100, big: "%\(b.percent)",
                          detail: batteryDetail(b), gradient: b.percent < 20 ? KGradient.heat : KGradient.success, history: nil)
            }
        }
    }

    private func batteryDetail(_ b: SystemMonitor.Battery) -> String {
        var parts: [String] = [b.charging ? L("şarj oluyor") : L("pilde")]
        if let h = b.health { parts.append(L("sağlık %{0}", h)) }
        if let c = b.cycles { parts.append(L("{0} döngü", c)) }
        return parts.joined(separator: " · ")
    }

    // MARK: optimize

    private var optimize: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Hızlandır")).font(.system(size: 15, weight: .semibold))
            OptimizeRow(id: "ram", symbol: "memorychip", gradient: KGradient.violet,
                        title: L("Belleği rahatlat"), text: L("Kullanılmayan belleği boşaltır. Mac şifreni ister."))
            OptimizeRow(id: "dns", symbol: "network", gradient: KGradient.accent,
                        title: L("İnternet bağlantısını tazele"), text: L("Açılmayan siteler için adres önbelleğini yeniler."))
            OptimizeRow(id: "clean", symbol: "sparkles", gradient: KGradient.success,
                        title: L("Önbellekleri temizle"), text: L("Tara, seç ve temizle ekranına gider."))
            if let m = model.optimizeMessage {
                Label(m, systemImage: "checkmark.circle.fill").font(.system(size: 12)).foregroundStyle(KColor.success)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .kCard()
    }

    private var apps: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L("En çok bellek kullananlar")).font(.system(size: 15, weight: .semibold))
                Spacer()
                Button(L("Tümü Analiz'de")) { model.section = .analysis }
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(KColor.accentSoft)
            }
            if model.topApps.isEmpty {
                Text(L("Okunuyor…")).font(.system(size: 12)).foregroundStyle(KColor.textMuted)
            }
            ForEach(model.topApps.prefix(4)) { a in
                HStack(spacing: 10) {
                    if let icon = a.icon { Image(nsImage: icon).resizable().frame(width: 22, height: 22) }
                    Text(a.name).font(.system(size: 13)).lineLimit(1)
                    Spacer()
                    Text(KBytes.format(Int64(a.bytes))).font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(KColor.textMuted)
                    Button(L("Kapat")) { model.quitApp(pid: a.id) }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(KColor.accentSoft)
                        .help(L("{0} kapanır; kaydedilmemiş işin varsa sorar.", a.name))
                }
                .frame(height: 30)
            }
        }
        .kCard()
    }

    private var startup: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Açılışta kendiliğinden çalışanlar")).font(.system(size: 15, weight: .semibold))
                    Text(L("Mac'i açınca arka planda başlayan yardımcı programlar. Ne kadar azsa açılış o kadar hızlı."))
                        .font(.system(size: 12)).foregroundStyle(KColor.textMuted)
                }
                Spacer()
                Button(L("Giriş öğelerini aç")) {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            if model.startupItems.isEmpty {
                Label(L("Açılışta çalışan ek bir yardımcı yok."), systemImage: "checkmark.circle")
                    .font(.system(size: 12)).foregroundStyle(KColor.success)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 8)], spacing: 8) {
                ForEach(model.startupItems) { item in
                    HStack(spacing: 10) {
                        Image(systemName: "bolt.horizontal.circle").foregroundStyle(KColor.warning)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                            Text(item.systemWide ? L("Tüm kullanıcılar için · yönetici gerekir") : L("Yalnızca senin hesabın"))
                                .font(.system(size: 10)).foregroundStyle(KColor.textMuted)
                        }
                        Spacer()
                        if !item.systemWide {
                            Button(L("Kaldır")) { model.removeStartupItem(item) }
                                .buttonStyle(.plain).font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(KColor.heatSoft)
                                .help(L("Açılışta başlamasını durdurur. Dosyası çöp kutusuna gider; geri koyabilirsin."))
                        }
                    }
                    .padding(.horizontal, 12).frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: 10).fill(KColor.surface2.opacity(0.6)))
                }
            }
        }
        .kCard()
    }
}

/// A ring gauge in a card, with an optional small history line.
struct GaugeCard<G: ShapeStyle>: View {
    let title: String
    let value: Double
    let big: String
    let detail: String
    let gradient: G
    let history: [Double]?

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().stroke(KColor.surface2, lineWidth: 10)
                Circle().trim(from: 0, to: max(0.01, min(1, value)))
                    .stroke(gradient, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(KMotion.base, value: value)
                Text("%\(Int(min(1, value) * 100))").font(.system(size: 13, weight: .bold).monospacedDigit())
            }
            .frame(width: 74, height: 74)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(KColor.textMuted)
                Text(big).font(.system(size: 22, weight: .bold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
                Text(detail).font(.system(size: 11)).foregroundStyle(KColor.textMuted).lineLimit(2)
                if let history, history.count > 1 { Sparkline(values: history).frame(height: 18) }
            }
        }
        .kCard(padding: 16)
        .accessibilityElement(children: .combine)
    }
}

struct Sparkline: View {
    let values: [Double]
    var body: some View {
        GeometryReader { geo in
            Path { p in
                for (i, v) in values.enumerated() {
                    let x = geo.size.width * CGFloat(i) / CGFloat(max(values.count - 1, 1))
                    let y = geo.size.height * CGFloat(1 - min(1, max(0, v)))
                    if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(KGradient.accent, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

struct OptimizeRow: View {
    @EnvironmentObject var model: AppModel
    let id: String
    let symbol: String
    let gradient: LinearGradient
    let title: String
    let text: String

    var body: some View {
        Button {
            if id == "clean" { model.section = model.items.isEmpty ? .scan : .results; if model.items.isEmpty { model.startScan() } }
            else { model.runOptimize(id) }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(gradient).frame(width: 38, height: 38)
                    Image(systemName: symbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(KColor.text)
                    Text(text).font(.system(size: 11)).foregroundStyle(KColor.textMuted).lineLimit(2)
                }
                Spacer()
                if model.optimizeBusy == id { ProgressView().controlSize(.small) }
                else { Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(KColor.textMuted) }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12).fill(KColor.surface2.opacity(0.5)))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(model.optimizeBusy != nil)
    }
}
