import SwiftUI
import AppKit
import KartovCore

/// "Gözetim": what Kartov notices while it watches the Mac, plus energy, crashes and permissions.
struct GuardianView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var guardian = Guardian.shared

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: L("Gözetim")) {
                GuardianTabs()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch guardian.page {
                    case .overview: GuardianOverviewPage()
                    case .energy: EnergyPage()
                    case .crashes: CrashPage()
                    case .privacy: PrivacyPage()
                    }
                }
                .padding(24)
                .frame(maxWidth: 1080, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

/// The four Gözetim pages as pill tabs, drawn like the main tab bar.
struct GuardianTabs: View {
    @ObservedObject private var guardian = Guardian.shared

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Guardian.Page.allCases) { p in
                let selected = guardian.page == p
                Button { guardian.page = p } label: {
                    HStack(spacing: 6) {
                        Image(systemName: p.symbol).font(.system(size: 11, weight: .semibold))
                        Text(p.title).font(.system(size: 12, weight: selected ? .semibold : .medium))
                        if p == .overview && guardian.unread > 0 {
                            Text("\(guardian.unread)").font(.system(size: 10, weight: .bold).monospacedDigit())
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(Capsule().fill(selected ? Color.white.opacity(0.22) : KColor.heat.opacity(0.18)))
                                .foregroundStyle(selected ? Color.white : KColor.heatSoft)
                        }
                    }
                    .foregroundStyle(selected ? Color.white : KColor.textMuted)
                    .padding(.horizontal, 12).frame(height: 28)
                    .background(Capsule().fill(selected ? AnyShapeStyle(KGradient.accent) : AnyShapeStyle(Color.clear)))
                    .shadow(color: KColor.accent.opacity(selected ? 0.4 : 0), radius: 6, y: 2)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(KColor.surface.opacity(0.8)))
        .overlay(Capsule().strokeBorder(KGradient.rim))
        .fixedSize()
    }
}

// MARK: - overview

struct GuardianOverviewPage: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var guardian = Guardian.shared
    @ObservedObject private var profiles = ProfileStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            status
            HStack(alignment: .top, spacing: 18) {
                ForecastCard().frame(maxWidth: .infinity)
                growthCard.frame(maxWidth: .infinity)
            }
            alertsCard
        }
        .onDisappear { guardian.markAllRead() }
    }

    private var status: some View {
        HStack(spacing: 16) {
            Image(systemName: guardian.enabled ? "checkmark.shield.fill" : "shield.slash")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(guardian.enabled ? KColor.success : KColor.textMuted)
                .frame(width: 54, height: 54)
                .background(Circle().fill((guardian.enabled ? KColor.success : KColor.textMuted).opacity(0.14)))
            VStack(alignment: .leading, spacing: 4) {
                Text(guardian.enabled ? L("Gözetim açık") : L("Gözetim kapalı")).font(.system(size: 22, weight: .bold))
                Text(statusLine).font(.system(size: 13)).foregroundStyle(KColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Label(L("Profil: {0}", profiles.active.title), systemImage: profiles.active.symbol)
                .font(.system(size: 12, weight: .medium)).foregroundStyle(KColor.textMuted)
                .padding(.horizontal, 10).frame(height: 26)
                .background(Capsule().fill(KColor.surface2))
                .help(profiles.active.summary)
            Toggle("", isOn: Binding(get: { guardian.enabled }, set: { guardian.enabled = $0 }))
                .toggleStyle(.switch).labelsHidden()
        }
        .kCard(padding: 18)
    }

    private var statusLine: String {
        guard guardian.enabled else { return L("Açınca Kartov Mac'ine dakikada bir bakar ve bir sorun görürse haber verir.") }
        let last = guardian.lastCheck.map { relativeDay($0) } ?? L("az önce başladı")
        let alerts24 = guardian.alerts.filter { Date().timeIntervalSince($0.date) < 86_400 }.count
        return L("Dakikada bir bakılıyor · son kontrol {0} · son 24 saatte {1} uyarı. Yalnızca okur, hiçbir şey silmez.", last, alerts24)
    }

    private var growthCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L("Büyüyen uygulamalar"), systemImage: "chart.line.uptrend.xyaxis").font(.system(size: 14, weight: .semibold))
            Text(L("Son 7 günde Library'deki dosyaları en çok büyüyen programlar. Altı saatte bir ölçülür."))
                .font(.system(size: 12)).foregroundStyle(KColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            if guardian.growth.isEmpty {
                HStack(spacing: 8) {
                    if guardian.measuringApps { ProgressView().controlSize(.small) }
                    Text(growthEmpty).font(.system(size: 12)).foregroundStyle(KColor.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 4)
            }
            ForEach(guardian.growth) { g in
                HStack(spacing: 10) {
                    AppIconImage(bundleID: g.bundleID).frame(width: 24, height: 24)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(g.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                        Text(L("şimdi {0}", KBytes.format(g.bytes))).font(.system(size: 11)).foregroundStyle(KColor.textMuted)
                    }
                    Spacer(minLength: 8)
                    Text("+" + KBytes.format(g.delta)).font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(g.delta >= 1_000_000_000 ? KColor.heat : KColor.warning)
                    Button(L("Dosyalar")) { AppMap.shared.open(bundleID: g.bundleID, name: g.name) }
                        .buttonStyle(SecondaryButtonStyle())
                }
                .frame(height: 36)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .kCard(padding: 18)
    }

    private var growthEmpty: String {
        if guardian.measuringApps { return L("Programlar ölçülüyor…") }
        if guardian.footprintSince == nil { return L("İlk ölçüm birazdan yapılacak; büyüme birkaç ölçümden sonra görünür.") }
        return L("Son günlerde hızla büyüyen bir program yok.")
    }

    private var alertsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(L("Uyarılar"), systemImage: "bell.badge").font(.system(size: 14, weight: .semibold))
                Spacer()
                if !guardian.alerts.isEmpty {
                    Button(L("Tümünü temizle")) { guardian.clearAlerts() }
                        .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(KColor.textMuted)
                }
            }
            if guardian.alerts.isEmpty {
                Text(L("Her şey sakin. Bir şey fark edersem burada ve bildirimle haber veririm."))
                    .font(.system(size: 12)).foregroundStyle(KColor.textMuted)
            }
            ForEach(guardian.alerts.prefix(30)) { a in AlertRow(alert: a) }
        }
        .kCard(padding: 18)
    }
}

struct AlertRow: View {
    @EnvironmentObject var model: AppModel
    let alert: GuardianAlert

    private var tint: Color {
        switch alert.kind {
        case .diskLow, .memory: return KColor.heat
        case .cpu, .thermal, .diskBurst: return KColor.warning
        case .appGrowth: return KColor.accent
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: alert.symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 9).fill(tint.opacity(0.14)))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if !alert.read { Circle().fill(KColor.accent).frame(width: 7, height: 7) }
                    Text(alert.title).font(.system(size: 13, weight: .semibold))
                    Text(relativeDay(alert.date)).font(.system(size: 11)).foregroundStyle(KColor.textMuted)
                }
                Text(alert.detail).font(.system(size: 12)).foregroundStyle(KColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            action
            Button { Guardian.shared.dismiss(alert) } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(KColor.textMuted)
                    .frame(width: 22, height: 22).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L("Kaldır"))
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(KColor.surface2.opacity(alert.read ? 0.35 : 0.7)))
    }

    @ViewBuilder private var action: some View {
        switch alert.kind {
        case .appGrowth:
            if let id = alert.bundleID {
                Button(L("Dosyalar")) { AppMap.shared.open(bundleID: id, name: alert.appName ?? id) }
                    .buttonStyle(SecondaryButtonStyle())
            }
        case .cpu, .memory, .thermal:
            Button(L("Analiz'de aç")) { model.section = .analysis }.buttonStyle(SecondaryButtonStyle())
        case .diskLow, .diskBurst:
            Button(L("Tam tarama")) { model.section = .fullScan }.buttonStyle(SecondaryButtonStyle())
        }
    }
}

/// Icon of an installed program by bundle id (a plain app symbol when it is not found).
struct AppIconImage: View {
    let bundleID: String?
    var body: some View {
        if let id = bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().interpolation(.high)
        } else {
            Image(systemName: "app.dashed").resizable().scaledToFit().foregroundStyle(KColor.textMuted).padding(3)
        }
    }
}

// MARK: storage forecast

struct ForecastCard: View {
    @ObservedObject private var guardian = Guardian.shared

    var body: some View {
        let f = guardian.forecast
        let disk = DiskInfo.read()
        VStack(alignment: .leading, spacing: 10) {
            Label(L("Disk tahmini"), systemImage: "calendar.badge.clock").font(.system(size: 14, weight: .semibold))
            Text(headline(f)).font(.system(size: 26, weight: .bold).monospacedDigit())
                .foregroundStyle(color(f))
            Text(detail(f)).font(.system(size: 12)).foregroundStyle(KColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            ForecastChart(samples: f.samples, total: disk.total, perDay: f.perDay, fills: fillDays(f))
                .frame(height: 110)
            Text(L("{0} dolu · {1} boş", KBytes.format(disk.used), KBytes.format(disk.free)))
                .font(.system(size: 11)).foregroundStyle(KColor.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .kCard(padding: 18)
    }

    private func fillDays(_ f: StorageForecast) -> Double? {
        if case .fills(let d) = f.kind { return d }
        return nil
    }

    private func headline(_ f: StorageForecast) -> String {
        switch f.kind {
        case .collecting: return L("Ölçüm birikiyor")
        case .steady: return f.perDay < 0 ? L("Disk boşalıyor") : L("Disk sabit")
        case .fills(let d):
            if d < 1 { return L("Bugün dolabilir") }
            if d < 60 { return L("~{0} gün", Int(d.rounded())) }
            return L("~{0} ay", Int((d / 30).rounded()))
        }
    }

    private func color(_ f: StorageForecast) -> Color {
        if case .fills(let d) = f.kind { return d < 14 ? KColor.heat : (d < 60 ? KColor.warning : KColor.text) }
        return KColor.success
    }

    private func detail(_ f: StorageForecast) -> String {
        switch f.kind {
        case .collecting(let have, let need):
            return L("Tahmin için en az {0} günlük ölçüm gerekiyor; şu an {1} saatlik ölçüm var. Kartov açık kaldıkça birikir.",
                     Int(need), Int(have * 24))
        case .steady:
            return f.perDay < 0 ? L("Kullanım son günlerde azalıyor; dolma riski yok.")
                                : L("Doluluk pek değişmiyor; yakın zamanda dolma riski yok.")
        case .fills(let d):
            let date = Date().addingTimeInterval(d * 86_400).formatted(date: .abbreviated, time: .omitted)
            return L("Bu hızla disk {0} civarında dolar. Günde ortalama {1} artıyor.", date, KBytes.format(Int64(f.perDay)))
        }
    }
}

/// Used space over time, and a dashed line to "full" at the current pace.
struct ForecastChart: View {
    let samples: [DiskSample]
    let total: Int64
    let perDay: Double
    let fills: Double?

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            // Frame: the full-disk line on top.
            var top = Path()
            top.move(to: CGPoint(x: 0, y: 1)); top.addLine(to: CGPoint(x: w, y: 1))
            ctx.stroke(top, with: .color(KColor.heat.opacity(0.5)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            guard samples.count >= 2, total > 0, let first = samples.first?.date, let last = samples.last else {
                var base = Path()
                base.move(to: CGPoint(x: 0, y: h - 1)); base.addLine(to: CGPoint(x: w, y: h - 1))
                ctx.stroke(base, with: .color(KColor.border), lineWidth: 1)
                return
            }
            let span = max(3600, last.date.timeIntervalSince(first))
            let future = fills.map { min($0 * 86_400, span * 2) } ?? span * 0.25
            let end = last.date.addingTimeInterval(future)
            let range = end.timeIntervalSince(first)
            // Show the top part of the disk so changes are visible: from 60 % of the lowest reading up to full.
            let low = Double(samples.map(\.used).min() ?? 0) * 0.6
            func pt(_ d: Date, _ used: Double) -> CGPoint {
                let x = CGFloat(d.timeIntervalSince(first) / range) * w
                let y = h - CGFloat((used - low) / max(1, Double(total) - low)) * (h - 2)
                return CGPoint(x: x, y: min(h, max(1, y)))
            }
            var line = Path()
            var area = Path()
            area.move(to: CGPoint(x: 0, y: h))
            for (i, s) in samples.enumerated() {
                let p = pt(s.date, Double(s.used))
                if i == 0 { line.move(to: p) } else { line.addLine(to: p) }
                area.addLine(to: p)
            }
            area.addLine(to: CGPoint(x: pt(last.date, 0).x, y: h))
            area.closeSubpath()
            ctx.fill(area, with: .linearGradient(Gradient(colors: [KColor.accent.opacity(0.28), KColor.accent.opacity(0.02)]),
                                                 startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: h)))
            ctx.stroke(line, with: .color(KColor.accent), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            // Projection.
            var proj = Path()
            let startP = pt(last.date, Double(last.used))
            proj.move(to: startP)
            proj.addLine(to: pt(end, Double(last.used) + perDay * future / 86_400))
            ctx.stroke(proj, with: .color(fills == nil ? KColor.textMuted : KColor.heat),
                       style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            ctx.fill(Path(ellipseIn: CGRect(x: startP.x - 3.5, y: startP.y - 3.5, width: 7, height: 7)), with: .color(KColor.accent))
        }
        .accessibilityHidden(true)
    }
}

// MARK: - energy

struct EnergyPage: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var guardian = Guardian.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            battery
            HStack(alignment: .top, spacing: 18) {
                live.frame(maxWidth: .infinity)
                day.frame(maxWidth: .infinity)
            }
            Text(L("Değerler macOS'un her programa ayırdığı tahmini enerjiden hesaplanır; Activity Monitor'deki Enerji etkisi puanıyla birebir aynı değildir."))
                .font(.system(size: 11)).foregroundStyle(KColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { guardian.startLiveEnergy() }
        .onDisappear { guardian.stopLiveEnergy() }
    }

    private var battery: some View {
        let b = SystemMonitor.battery()
        let total = guardian.liveEnergy.reduce(0) { $0 + $1.watts }
        return HStack(spacing: 16) {
            Image(systemName: b == nil ? "powerplug.fill" : (b!.charging ? "battery.100.bolt" : "battery.75"))
                .font(.system(size: 24, weight: .semibold)).foregroundStyle(KColor.success)
                .frame(width: 54, height: 54)
                .background(Circle().fill(KColor.success.opacity(0.14)))
            VStack(alignment: .leading, spacing: 4) {
                if let b {
                    Text(L("Pil %{0}", b.percent)).font(.system(size: 22, weight: .bold).monospacedDigit())
                    Text(batteryLine(b)).font(.system(size: 13)).foregroundStyle(KColor.textMuted)
                } else {
                    Text(L("Prizden çalışıyor")).font(.system(size: 22, weight: .bold))
                    Text(L("Bu Mac'te pil yok; programların enerji kullanımı yine de gösterilir.")).font(.system(size: 13)).foregroundStyle(KColor.textMuted)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(powerText(total)).font(.system(size: 22, weight: .bold).monospacedDigit())
                Text(L("açık programların toplamı")).font(.system(size: 11)).foregroundStyle(KColor.textMuted)
            }
        }
        .kCard(padding: 18)
    }

    private func batteryLine(_ b: SystemMonitor.Battery) -> String {
        var parts: [String] = []
        if b.charging { parts.append(L("şarj oluyor")) }
        else if let m = Guardian.batteryMinutesLeft() { parts.append(L("yaklaşık {0} sa {1} dk kaldı", m / 60, m % 60)) }
        if let h = b.health { parts.append(L("pil sağlığı %{0}", h)) }
        if let c = b.cycles { parts.append(L("{0} döngü", c)) }
        return parts.joined(separator: " · ")
    }

    private var live: some View {
        let rows = Array(guardian.liveEnergy.prefix(8))
        let top = max(0.001, rows.first?.watts ?? 0.001)
        return VStack(alignment: .leading, spacing: 10) {
            Label(L("Şu an en çok enerji kullananlar"), systemImage: "bolt.fill").font(.system(size: 14, weight: .semibold))
            if rows.isEmpty {
                Text(L("Okunuyor…")).font(.system(size: 12)).foregroundStyle(KColor.textMuted)
            }
            ForEach(rows) { r in
                HStack(spacing: 10) {
                    if let icon = r.icon { Image(nsImage: icon).resizable().frame(width: 22, height: 22) }
                    Text(r.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Bar(fraction: r.watts / top, tint: r.watts >= 5 ? KColor.heat : KColor.warning).frame(width: 80)
                    Text(powerText(r.watts)).font(.system(size: 12).monospacedDigit())
                        .frame(width: 60, alignment: .trailing)
                    Button(L("Kapat")) { if let pid = Int32(r.id) { model.quitApp(pid: pid) } }
                        .buttonStyle(SecondaryButtonStyle())
                }
                .frame(height: 34)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .kCard(padding: 18)
    }

    private var day: some View {
        let rows = guardian.dayEnergy
        let sum = max(0.001, rows.reduce(0) { $0 + $1.joules })
        return VStack(alignment: .leading, spacing: 10) {
            Label(guardian.dayEnergyOnBattery ? L("Son 24 saat, pildeyken") : L("Son 24 saat"), systemImage: "clock.arrow.circlepath")
                .font(.system(size: 14, weight: .semibold))
            Text(L("Pili en çok tüketenler. Gözetim açık kaldıkça birikir."))
                .font(.system(size: 12)).foregroundStyle(KColor.textMuted)
            if rows.isEmpty {
                Text(L("Henüz yeterli ölçüm yok.")).font(.system(size: 12)).foregroundStyle(KColor.textMuted)
            }
            ForEach(rows) { r in
                HStack(spacing: 10) {
                    if let icon = r.icon { Image(nsImage: icon).resizable().frame(width: 22, height: 22) }
                    Text(r.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("%\(Int((r.joules / sum * 100).rounded()))").font(.system(size: 12, weight: .semibold).monospacedDigit())
                    Text(powerText(r.watts)).font(.system(size: 11).monospacedDigit()).foregroundStyle(KColor.textMuted)
                        .frame(width: 56, alignment: .trailing)
                        .help(L("Ortalama güç"))
                }
                .frame(height: 30)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .kCard(padding: 18)
    }
}

// MARK: - crash detective

struct CrashPage: View {
    @ObservedObject private var guardian = Guardian.shared

    var body: some View {
        let groups = CrashGroup.make(guardian.crashes)
        let c = guardian.crashes
        return VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                StatTile(symbol: "xmark.octagon.fill", tint: KColor.heat, value: "\(c.filter { $0.kind == .crash }.count)", label: L("çökme"))
                StatTile(symbol: "hourglass", tint: KColor.warning, value: "\(c.filter { $0.kind == .hang }.count)", label: L("donma"))
                StatTile(symbol: "gauge.with.dots.needle.67percent", tint: Color.purple, value: "\(c.filter { $0.kind == .resource }.count)", label: L("kaynak aşımı"))
                StatTile(symbol: "bolt.trianglebadge.exclamationmark.fill", tint: KColor.heat, value: "\(c.filter { $0.kind == .panic }.count)", label: L("yeniden başlama"))
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(L("Son 30 gün"), systemImage: "stethoscope").font(.system(size: 14, weight: .semibold))
                    Spacer()
                    if guardian.crashesLoading { ProgressView().controlSize(.small) }
                    Button(L("Yenile")) { guardian.loadCrashes(force: true) }.buttonStyle(SecondaryButtonStyle())
                        .disabled(guardian.crashesLoading)
                }
                Text(L("macOS'un tuttuğu çökme ve donma raporları okunur, ne olduğu sade bir dille anlatılır. Raporlar silinmez."))
                    .font(.system(size: 12)).foregroundStyle(KColor.textMuted)
                if guardian.crashesLoaded && groups.isEmpty {
                    Label(L("Son 30 günde çöken ya da donan program yok."), systemImage: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(KColor.success).padding(.top, 4)
                }
                ForEach(groups) { g in CrashGroupRow(group: g) }
            }
            .kCard(padding: 18)
        }
        .onAppear { guardian.loadCrashes() }
    }
}

struct CrashGroupRow: View {
    @ObservedObject private var guardian = Guardian.shared
    let group: CrashGroup
    private var open: Bool { guardian.openCrashGroups.contains(group.id) }

    var body: some View {
        let main = group.mainReason
        VStack(alignment: .leading, spacing: 10) {
            Button { guardian.toggleCrashGroup(group.id) } label: {
                HStack(spacing: 10) {
                    Image(systemName: "chevron.right").rotationEffect(.degrees(open ? 90 : 0))
                        .foregroundStyle(KColor.textMuted).frame(width: 16)
                    if group.panics > 0 {
                        Image(systemName: "laptopcomputer.trianglebadge.exclamationmark").foregroundStyle(KColor.heat).frame(width: 24, height: 24)
                    } else {
                        AppIconImage(bundleID: group.bundleID).frame(width: 24, height: 24)
                    }
                    Text(group.app).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    HStack(spacing: 6) {
                        if group.crashes > 0 { CountChip(text: L("{0} çökme", group.crashes), color: KColor.heat) }
                        if group.hangs > 0 { CountChip(text: L("{0} donma", group.hangs), color: KColor.warning) }
                        if group.resource > 0 { CountChip(text: L("{0} kaynak aşımı", group.resource), color: Color.purple) }
                        if group.panics > 0 { CountChip(text: L("{0} yeniden başlama", group.panics), color: KColor.heat) }
                    }
                    Spacer()
                    Text(relativeDay(group.last)).font(.system(size: 11)).foregroundStyle(KColor.textMuted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open {
                VStack(alignment: .leading, spacing: 8) {
                    Text(CrashExplainer.explain(main.0, main.1)).font(.system(size: 13))
                        .fixedSize(horizontal: false, vertical: true)
                    Label(CrashExplainer.advice(group), systemImage: "lightbulb.fill")
                        .font(.system(size: 12)).foregroundStyle(KColor.accentSoft)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(group.reports.prefix(5)) { r in
                        HStack(spacing: 8) {
                            Text(r.date.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 11.5).monospacedDigit())
                            if let v = r.version { Text("v\(v)").font(.system(size: 11)).foregroundStyle(KColor.textMuted) }
                            Text(r.reason ?? "–").font(.system(size: 11, design: .monospaced)).foregroundStyle(KColor.textMuted).lineLimit(1)
                            Spacer()
                            Button(L("Raporu göster")) { Finder.reveal(r.url.path) }
                                .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(KColor.accentSoft)
                        }
                    }
                    if let id = group.bundleID, NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil {
                        Button(L("Bağlantılı dosyalar")) { AppMap.shared.open(bundleID: id, name: group.app) }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                }
                .padding(.leading, 26)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(KColor.surface2.opacity(0.5)))
    }
}

struct CountChip: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text).font(.system(size: 10.5, weight: .semibold))
            .padding(.horizontal, 7).frame(height: 18)
            .background(Capsule().fill(color.opacity(0.16)))
            .foregroundStyle(color)
    }
}

// MARK: - privacy inspector

struct PrivacyPage: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var guardian = Guardian.shared

    private var shown: [PrivacyApp] {
        guard let f = guardian.privacyFilter else { return guardian.privacy }
        return guardian.privacy.filter { $0.allowed.contains(f) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !guardian.privacyReadable && !guardian.privacyLoading {
                HStack(spacing: 12) {
                    Image(systemName: "lock.shield").font(.system(size: 20)).foregroundStyle(KColor.warning)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("İzinleri okumak için Tam Disk Erişimi gerekiyor")).font(.system(size: 13, weight: .semibold))
                        Text(L("macOS izin listesini korumalı bir dosyada tutar. Kartov yalnızca okur, değiştirmez."))
                            .font(.system(size: 12)).foregroundStyle(KColor.textMuted)
                    }
                    Spacer()
                    Button(L("İzin ver")) { Permissions.openFullDiskAccessSettings() }.buttonStyle(PrimaryButtonStyle())
                }
                .kCard(padding: 16)
            }
            services
            HStack(spacing: 12) {
                Image(systemName: "location.fill").foregroundStyle(KColor.accent)
                    .frame(width: 30, height: 30).background(RoundedRectangle(cornerRadius: 8).fill(KColor.accent.opacity(0.14)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Konum")).font(.system(size: 13, weight: .semibold))
                    Text(L("macOS konum izinlerini yalnızca kendisi okuyabilir; listeyi Sistem Ayarları'nda görebilirsin."))
                        .font(.system(size: 12)).foregroundStyle(KColor.textMuted)
                }
                Spacer()
                Button(L("Konum ayarlarını aç")) { if let u = PrivacyService.locationSettingsURL { NSWorkspace.shared.open(u) } }
                    .buttonStyle(SecondaryButtonStyle())
            }
            .kCard(padding: 14, radius: 16)
            appList
        }
        .onAppear { if guardian.privacy.isEmpty { guardian.loadPrivacy() } }
    }

    private var services: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
            ServiceChip(symbol: "square.grid.2x2", title: L("Tümü"), count: guardian.privacy.filter { !$0.allowed.isEmpty }.count,
                        selected: guardian.privacyFilter == nil, sensitive: false) { guardian.privacyFilter = nil }
            ForEach(PrivacyService.allCases) { s in
                ServiceChip(symbol: s.symbol, title: s.title, count: guardian.privacy.filter { $0.allowed.contains(s) }.count,
                            selected: guardian.privacyFilter == s, sensitive: s.sensitive) {
                    guardian.privacyFilter = guardian.privacyFilter == s ? nil : s
                }
            }
        }
    }

    private var appList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(L("İzin verilen programlar"), systemImage: "hand.raised.fill").font(.system(size: 14, weight: .semibold))
                Spacer()
                if guardian.privacyLoading { ProgressView().controlSize(.small) }
                Button(L("Yenile")) { guardian.loadPrivacy() }.buttonStyle(SecondaryButtonStyle())
                    .disabled(guardian.privacyLoading)
            }
            Text(L("Kartov izinleri yalnızca okur. Değiştirmek için Sistem Ayarları'ndaki ilgili bölüm açılır. Uzun süredir açmadığın ya da kaldırdığın programlar öne alınır."))
                .font(.system(size: 12)).foregroundStyle(KColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            if let m = guardian.privacyMessage {
                Label(m, systemImage: "info.circle.fill").font(.system(size: 12, weight: .medium)).foregroundStyle(KColor.accentSoft)
            }
            if shown.isEmpty && !guardian.privacyLoading && guardian.privacyReadable {
                Text(L("Bu izni kullanan program yok.")).font(.system(size: 12)).foregroundStyle(KColor.textMuted)
            }
            ForEach(shown) { app in PrivacyRow(app: app) }
        }
        .kCard(padding: 18)
    }
}

struct ServiceChip: View {
    let symbol: String
    let title: String
    let count: Int
    let selected: Bool
    let sensitive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(selected ? Color.white : (sensitive ? KColor.warning : KColor.accent))
                Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Spacer(minLength: 4)
                Text("\(count)").font(.system(size: 12, weight: .bold).monospacedDigit())
            }
            .foregroundStyle(selected ? Color.white : KColor.text)
            .padding(.horizontal, 12).frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 10).fill(selected ? AnyShapeStyle(KGradient.accent) : AnyShapeStyle(KColor.surface)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(KColor.border, lineWidth: selected ? 0 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct PrivacyRow: View {
    @ObservedObject private var guardian = Guardian.shared
    let app: PrivacyApp

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let icon = app.icon { Image(nsImage: icon).resizable() }
                else { Image(systemName: "questionmark.app.dashed").resizable().scaledToFit().foregroundStyle(KColor.textMuted).padding(2) }
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(app.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    if !app.installed { CountChip(text: L("Kaldırılmış"), color: KColor.heat) }
                    else if app.dormant { CountChip(text: L("3 aydır açılmadı"), color: KColor.warning) }
                }
                HStack(spacing: 6) {
                    ForEach(app.allowed) { s in
                        Image(systemName: s.symbol).font(.system(size: 11))
                            .foregroundStyle(s.sensitive ? KColor.warning : KColor.textMuted)
                            .help(s.title)
                    }
                    if app.allowed.isEmpty {
                        Text(L("izin kaydı kalmış")).font(.system(size: 11)).foregroundStyle(KColor.textMuted)
                    }
                }
            }
            Spacer(minLength: 8)
            if !app.installed, app.bundleID != nil {
                if guardian.privacyConfirm == app.id {
                    Button(L("Vazgeç")) { guardian.privacyConfirm = nil }.buttonStyle(SecondaryButtonStyle())
                    Button(L("Sıfırla")) { guardian.resetPermissions(of: app) }.buttonStyle(PrimaryButtonStyle())
                } else {
                    Button(L("İzinleri sıfırla…")) { guardian.privacyConfirm = app.id }.buttonStyle(SecondaryButtonStyle())
                        .help(L("Kaldırılmış programın macOS'ta kalan izin kayıtlarını siler."))
                }
            }
            Menu {
                ForEach(app.allowed) { s in
                    Button(L("{0} ayarlarını aç", s.title)) { if let u = s.settingsURL { NSWorkspace.shared.open(u) } }
                }
                if let u = app.url { Button(L("Finder'da göster")) { Finder.reveal(u.path) } }
            } label: { Image(systemName: "ellipsis.circle") }
            .menuStyle(.borderlessButton).fixedSize()
        }
        .padding(.horizontal, 8).frame(minHeight: 44)
        .background(RoundedRectangle(cornerRadius: 10).fill(KColor.surface2.opacity(0.45)))
    }
}

/// "1,4 W" or "320 mW" for small values.
func powerText(_ watts: Double) -> String {
    if watts <= 0 { return "0 mW" }
    if watts < 1 { return "\(max(1, Int((watts * 1000).rounded()))) mW" }
    return String(format: "%.1f W", watts)
}
