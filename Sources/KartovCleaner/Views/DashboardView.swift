import SwiftUI
import KartovCore

extension CategoryGroup {
    var symbol: String {
        switch self {
        case .apps: return "square.stack.3d.up.fill"
        case .creative: return "film.stack.fill"
        case .browsers: return "globe"
        case .developer: return "hammer.fill"
        case .logs: return "doc.text.fill"
        case .updates: return "arrow.down.circle.fill"
        case .trash: return "trash.fill"
        case .privacy: return "hand.raised.fill"
        case .userFiles: return "folder.fill"
        }
    }

    /// One plain sentence anyone understands: what lives in this category.
    var blurb: String {
        switch self {
        case .apps: return L("Programların hızlı açılmak için biriktirdiği geçici dosyalar.")
        case .creative: return L("Video, fotoğraf ve tasarım programlarının önizleme dosyaları.")
        case .browsers: return L("Gezdiğin sitelerin geçici kopyaları. Şifrelerin kalır.")
        case .developer: return L("Kod yazma araçlarının dosyaları. Kullanmıyorsan boştur.")
        case .logs: return L("Programların tuttuğu eski kayıtlar ve geçici dosyalar.")
        case .updates: return L("İşi bitmiş kurulum dosyaları ve eski güncellemeler.")
        case .trash: return L("Çöp kutusunda bekleyenler.")
        case .privacy: return L("Gezdiğin sitelerin listesi. Silmeden önce sorulur.")
        case .userFiles: return L("Uzun süredir açmadığın büyük dosyalar. Sen seçersin.")
        }
    }

    /// Short title for tiles.
    var shortTitle: String { title }
}

struct DashboardView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Genel bakış")).font(.system(size: 28, weight: .bold))
                    Text(subline).font(.system(size: 14)).foregroundStyle(KColor.textMuted)
                }
                HStack(alignment: .top, spacing: 16) {
                    CleanCard()
                    FullScanCard()
                    SystemCard()
                    AnalysisCard()
                    CareCard()
                }
                .frame(height: 380)
                DiskBar()
            }
            .padding(.horizontal, 28).padding(.top, 14).padding(.bottom, 28)
            .frame(maxWidth: 1240, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .onAppear { model.startMonitoring() }
        .onDisappear { model.stopMonitoring() }
    }

    private var subline: String {
        if model.phase == .scanning { return L("Mac'ine bakılıyor…") }
        if model.lastScanDate == nil && model.items.isEmpty { return L("Başlamak için Temizlik kartından tara.") }
        if model.selectedBytes >= 5_000_000_000 { return L("Dünyan kirlenmiş; temizlik zamanı.") }
        return L("Mac'in iyi durumda.")
    }
}

/// The shared shape of the four home cards: visual on top, one big figure, one line, one button.
struct HomeCard<Visual: View, Action: View>: View {
    let title: String
    let symbol: String
    let gradient: LinearGradient
    let glow: Color
    let figure: String
    let figureColor: Color
    let line: String
    @ViewBuilder var visual: () -> Visual
    @ViewBuilder var action: () -> Action

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(glow.opacity(0.16)).frame(width: 26, height: 26)
                    Image(systemName: symbol).font(.system(size: 12, weight: .bold)).foregroundStyle(glow)
                }
                Text(title).font(.system(size: 13, weight: .semibold))
            }
            visual()
                .frame(maxWidth: .infinity)
                .frame(height: 160)
                .padding(.vertical, 8)
            Text(figure)
                .font(.system(size: 30, weight: .bold).monospacedDigit())
                .foregroundStyle(figureColor)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(line).font(.system(size: 12)).foregroundStyle(KColor.textMuted)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                .frame(height: 34, alignment: .topLeading)
            Spacer(minLength: 10)
            action()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .kCard(padding: 18, radius: 22, glow: glow)
    }
}

struct CleanCard: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        let scanning = model.phase == .scanning
        let bytes = scanning ? model.foundBytes : model.selectedBytes
        let never = model.lastScanDate == nil && model.items.isEmpty && !scanning
        return HomeCard(title: L("Temizlik"), symbol: "sparkles",
                        gradient: bytes >= 5_000_000_000 ? KGradient.heat : KGradient.accent,
                        glow: bytes >= 5_000_000_000 ? KColor.heat : KColor.accent,
                        figure: never ? L("Taranmadı") : (bytes > 0 ? KBytes.format(bytes) : L("Tertemiz")),
                        figureColor: never ? KColor.text : (bytes >= 5_000_000_000 ? KColor.heat : (bytes > 0 ? KColor.warning : KColor.success)),
                        line: scanning ? L("bulundu, tarama sürüyor") :
                            (never ? L("Önbellek ve gereksiz dosyaları bul.") : (bytes > 0 ? L("temizlenebilir") : L("Temizlenecek bir şey yok.")))) {
            Globe(dirt: dirtLevel(bytes), speed: scanning ? 1.1 : 0.22, size: 105,
                  shine: !never && bytes == 0 ? 0.5 : 0)
        } action: {
            VStack(spacing: 8) {
                if scanning {
                    Button(L("Taramayı izle")) { model.section = .scan }.buttonStyle(PrimaryButtonStyle()).frame(maxWidth: .infinity)
                } else if bytes > 0 {
                    Button { model.requestClean() } label: { Text(L("Temizle")).frame(maxWidth: .infinity) }
                        .buttonStyle(PrimaryButtonStyle())
                    Button(L("Gözden geçir")) { model.section = .results }.buttonStyle(.plain)
                        .font(.system(size: 12)).foregroundStyle(KColor.textMuted)
                } else {
                    Button { model.startScan() } label: { Text(never ? L("Tara") : L("Yeniden tara")).frame(maxWidth: .infinity) }
                        .buttonStyle(PrimaryButtonStyle())
                }
            }
        }
    }
}

struct FullScanCard: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        let total = model.fullEntries.reduce(Int64(0)) { $0 + $1.size }
        let done = model.fullScanDate != nil
        return HomeCard(title: L("Tam tarama"), symbol: "chart.pie.fill", gradient: KGradient.violet, glow: Color.purple,
                        figure: model.fullScanning ? L("Taranıyor") : (done ? KBytes.format(total) : L("Ne nerede?")),
                        figureColor: KColor.text,
                        line: done ? L("programların ve dosyaların kapladığı alan") : L("Programlarını, videolarını ve belgelerini boyutlarıyla gör.")) {
            KindRing(model: model).frame(width: 140, height: 140)
        } action: {
            Button {
                model.section = .fullScan
                if !done && !model.fullScanning { model.startFullScan() }
            } label: { Text(done ? L("Aç") : L("Tam tara")).frame(maxWidth: .infinity) }
            .buttonStyle(SecondaryButtonStyle())
        }
    }
}

/// Donut of space by kind (programs, videos...), or an empty ring before the first full scan.
struct KindRing: View {
    @ObservedObject var model: AppModel
    var body: some View {
        let kinds = DiskKind.allCases.map { KindBytes(kind: $0, bytes: model.bytes(of: $0)) }.filter { $0.bytes > 0 }
        let total = Double(max(kinds.reduce(Int64(0)) { $0 + $1.bytes }, 1))
        ZStack {
            Circle().stroke(KColor.surface2, lineWidth: 18)
            ForEach(Array(kinds.enumerated()), id: \.element.id) { i, kb in
                let start = kinds.prefix(i).reduce(0.0) { $0 + Double($1.bytes) } / total
                let end = start + Double(kb.bytes) / total
                Circle().trim(from: start, to: max(start, end - 0.006))
                    .stroke(kb.kind.color, style: StrokeStyle(lineWidth: 18, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
            Image(systemName: "chart.pie.fill").font(.system(size: 26)).foregroundStyle(KGradient.violet)
        }
        .padding(9)
    }
}

struct SystemCard: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        let mem = model.memory?.pressure ?? 0
        let hot = mem > 0.85
        let usage = model.memory.map { "\(KBytes.format(Int64($0.used))) / \(KBytes.format(Int64($0.total)))" } ?? L("Ölçülüyor…")
        return HomeCard(title: L("Sistem durumu"), symbol: "speedometer", gradient: KGradient.success,
                        glow: hot ? KColor.heat : KColor.success,
                        figure: usage,
                        figureColor: hot ? KColor.heat : KColor.text,
                        line: model.optimizeMessage ?? L("İşlemci %{0} · diskte {1} boş", Int(model.cpu * 100), KBytes.format(DiskInfo.read().free))) {
            ZStack {
                Circle().stroke(KColor.surface2, lineWidth: 14)
                Circle().trim(from: 0, to: max(0.01, mem))
                    .stroke(hot ? KGradient.heat : KGradient.success, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(KMotion.base, value: mem)
                VStack(spacing: 0) {
                    Text("%\(Int(mem * 100))")
                        .font(.system(size: 32, weight: .bold).monospacedDigit())
                        .foregroundStyle(hot ? KColor.heat : KColor.text)
                    Text(L("bellek dolu")).font(.system(size: 11, weight: .medium)).foregroundStyle(KColor.textMuted)
                }
            }
            .frame(width: 136, height: 136)
            .accessibilityElement(children: .combine)
        } action: {
            HStack(spacing: 8) {
                Button { model.section = .system } label: { Text(L("Aç")).frame(maxWidth: .infinity) }
                    .buttonStyle(SecondaryButtonStyle())
                Button { model.runOptimize("ram") } label: {
                    HStack(spacing: 6) {
                        if model.optimizeBusy == "ram" { ProgressView().controlSize(.small) }
                        Text(L("Optimize et")).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(model.optimizeBusy != nil)
            }
        }
    }
}

struct AnalysisCard: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        let apps = Array(model.topApps.prefix(4))
        let maxBytes = Double(apps.first?.bytes ?? 1)
        return HomeCard(title: L("Analiz"), symbol: "chart.bar.xaxis", gradient: KGradient.violet, glow: Color.purple,
                        figure: apps.isEmpty ? "…" : (apps.first?.name ?? ""),
                        figureColor: KColor.text,
                        line: apps.first.map { L("en çok belleği o kullanıyor · {0}", KBytes.format(Int64($0.bytes))) }
                              ?? L("Programların bellek, işlemci ve disk kullanımı.")) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(apps) { a in
                    HStack(spacing: 8) {
                        if let icon = a.icon { Image(nsImage: icon).resizable().frame(width: 20, height: 20) }
                        Bar(fraction: Double(a.bytes) / maxBytes, tint: Color.purple)
                    }
                }
            }
            .padding(.horizontal, 6)
        } action: {
            Button { model.section = .analysis } label: { Text(L("Aç")).frame(maxWidth: .infinity) }
                .buttonStyle(SecondaryButtonStyle())
        }
    }
}

struct CareCard: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        HomeCard(title: L("Otomatik bakım"), symbol: "clock.badge.checkmark", gradient: KGradient.accent,
                 glow: model.autoEnabled ? KColor.accent : KColor.textMuted,
                 figure: model.autoEnabled ? L("Açık") : L("Kapalı"),
                 figureColor: model.autoEnabled ? KColor.accentSoft : KColor.textMuted,
                 line: model.autoEnabled ? model.autoScheduleText : L("Kartov önbellekleri kendisi temizlesin.")) {
            ZStack {
                Circle().fill(KColor.accent.opacity(model.autoEnabled ? 0.22 : 0.07)).frame(width: 120, height: 120)
                Circle().strokeBorder(KGradient.rim, lineWidth: 1).frame(width: 120, height: 120)
                Image(systemName: model.autoEnabled ? "checkmark.shield.fill" : "shield")
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(model.autoEnabled ? AnyShapeStyle(KGradient.accent) : AnyShapeStyle(KColor.textMuted))
            }
        } action: {
            HStack(spacing: 8) {
                Button { model.section = .maintenance } label: { Text(L("Ayarlar")).frame(maxWidth: .infinity) }
                    .buttonStyle(SecondaryButtonStyle())
                if model.autoEnabled {
                    Button { model.autoEnabled = false } label: { Text(L("Durdur")).frame(maxWidth: .infinity) }
                        .buttonStyle(SecondaryButtonStyle())
                } else {
                    Button { model.autoEnabled = true } label: { Text(L("Aktif et")).lineLimit(1).frame(maxWidth: .infinity) }
                        .buttonStyle(PrimaryButtonStyle())
                }
            }
        }
    }
}

struct CategoryTile: View {
    let group: CategoryGroup
    let bytes: Int64?
    let scanned: Bool
    var offLabel: String? = nil
    let action: () -> Void

    private var tint: Color {
        guard let b = bytes, b > 0 else { return scanned ? KColor.success : KColor.accent }
        if group.isUserData || group == .privacy { return KColor.warning }
        return b >= 1_000_000_000 ? KColor.heat : KColor.warning
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle().fill(tint.opacity(0.14)).frame(width: 38, height: 38)
                    Image(systemName: group.symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(tint)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(group.shortTitle).font(.system(size: 14, weight: .semibold)).foregroundStyle(KColor.text)
                        Spacer(minLength: 6)
                        sizeLabel
                    }
                    Text(group.blurb).font(.system(size: 12)).foregroundStyle(KColor.textMuted)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
            .kCard(padding: 14, radius: 16, glow: bytes.map { $0 > 0 } == true ? tint : nil)
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(group.shortTitle), \(bytes.map { KBytes.format($0) } ?? (scanned ? "temiz" : L("taranmadı")))")
    }

    @ViewBuilder private var sizeLabel: some View {
        if let b = bytes, b > 0 {
            Text(KBytes.format(b)).font(.system(size: 14, weight: .bold).monospacedDigit()).foregroundStyle(tint)
        } else if let offLabel {
            Text(offLabel).font(.system(size: 11, weight: .semibold)).foregroundStyle(KColor.textMuted)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Capsule().strokeBorder(KColor.border))
        } else if scanned {
            Label(L("Temiz"), systemImage: "checkmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(KColor.success)
                .labelStyle(.titleAndIcon)
        }
    }
}

/// Startup disk usage with the cleanable part shown in red.
struct DiskBar: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let disk = DiskInfo.read()
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "internaldrive").foregroundStyle(KColor.textMuted)
                Text(disk.name).font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(L("{0} dolu · {1} boş · toplam {2}", KBytes.format(disk.used), KBytes.format(disk.free), KBytes.format(disk.total)))
                    .font(.system(size: 12).monospacedDigit()).foregroundStyle(KColor.textMuted)
            }
            GeometryReader { geo in
                let total = max(CGFloat(disk.total), 1)
                let cleanable = min(CGFloat(model.selectedBytes), CGFloat(disk.used))
                let usedW = geo.size.width * (CGFloat(disk.used) - cleanable) / total
                let cleanW = geo.size.width * cleanable / total
                HStack(spacing: 0) {
                    Rectangle().fill(KColor.textMuted.opacity(0.55)).frame(width: max(0, usedW))
                    Rectangle().fill(KGradient.heat).frame(width: max(0, cleanW))
                    Spacer(minLength: 0)
                }
                .clipShape(Capsule())
            }
            .frame(height: 10)
            .background(Capsule().fill(KColor.surface2))
            HStack(spacing: 16) {
                LegendDot(color: KColor.textMuted.opacity(0.55), text: L("Kullanılan"))
                if model.selectedBytes > 0 { LegendDot(color: KColor.heat, text: L("Temizlenebilir {0}", KBytes.format(model.selectedBytes))) }
                LegendDot(color: KColor.surface2, text: L("Boş"))
            }
        }
        .kCard(padding: 16, radius: 16)
        .accessibilityElement(children: .combine)
    }
}

enum DiskInfo {
    struct Info { let name: String; let total: Int64; let free: Int64; var used: Int64 { max(0, total - free) } }

    static func read() -> Info {
        let url = URL(fileURLWithPath: "/")
        let v = try? url.resourceValues(forKeys: [.volumeNameKey, .volumeTotalCapacityKey,
                                                  .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        let total = Int64(v?.volumeTotalCapacity ?? 0)
        let free = v?.volumeAvailableCapacityForImportantUsage ?? Int64(v?.volumeAvailableCapacity ?? 0)
        return Info(name: v?.volumeName ?? "Macintosh HD", total: total, free: free)
    }
}
