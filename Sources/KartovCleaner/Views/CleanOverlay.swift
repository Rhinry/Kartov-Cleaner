import SwiftUI
import KartovCore

/// The clean, told with the globe:
/// 1. While cleaning, the dirty world spins fast and its dirt flies off into space.
/// 2. When it is done, a ring of light sweeps out, the world turns blue and green and shines,
///    and the freed space counts up.
/// Driven by TimelineView and dates in the model (no @State: it needs full Xcode on the macOS 27 SDK).
struct CleanOverlay: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let start = model.cleanAnimationStart {
            ZStack {
                Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
                Color.black.opacity(0.55).ignoresSafeArea()
                TimelineView(.animation) { context in
                    content(now: context.date, start: start)
                }
            }
            .transition(.opacity)
        }
    }

    private func content(now: Date, start: Date) -> some View {
        let elapsed = now.timeIntervalSince(start)
        let ft = model.cleanFinishedAt.map { max(0, now.timeIntervalSince($0)) }
        let startDirt = max(model.cleanStartDirt, 0.35)

        // Dirt drains while cleaning, then clears completely in the finale.
        let working = min(0.85, max(model.cleaningProgress, elapsed / 1.8) * 0.85)
        let dirt: Double
        let speed: Double
        let shine: Double
        if let ft {
            dirt = startDirt * 0.15 * (1 - easeOut(ft / 0.9))
            speed = 0.35 + 2.6 * (1 - easeOut(ft / 1.4))
            shine = easeOut(ft / 0.8) * (1 - 0.45 * clamp((ft - 2.2) / 1.6))
        } else {
            dirt = startDirt * (1 - working)
            speed = reduceMotion ? 0.3 : 3.0
            shine = 0
        }

        return VStack(spacing: 18) {
            ZStack {
                if ft == nil && !reduceMotion { flyingDirt(elapsed: elapsed, amount: startDirt) }
                if let ft { shockwave(ft) }
                Globe(dirt: dirt, speed: speed, size: 230, shine: shine)
                if let ft { badge(ft) }
            }
            .frame(width: 440, height: 360)

            VStack(spacing: 6) {
                if let ft, let record = model.lastRecord {
                    Text(L("Dünya tertemiz")).font(.system(size: 26, weight: .bold))
                        .opacity(clamp((ft - 0.3) / 0.4))
                    BytesText(bytes: Int64(Double(record.bytesDeleted + record.bytesInTrash) * easeOut(ft / 1.3)),
                              size: 48, color: KColor.success)
                    Text(subtitle(record)).font(.system(size: 13)).foregroundStyle(KColor.textMuted)
                        .multilineTextAlignment(.center).frame(maxWidth: 420)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(L("Dünya temizleniyor…")).font(.system(size: 26, weight: .bold))
                    Text(L("%{0} · önbellekler siliniyor", Int(max(model.cleaningProgress, working / 0.85) * 100)))
                        .font(.system(size: 14).monospacedDigit()).foregroundStyle(KColor.textMuted)
                }
            }
            .frame(height: 130)

            HStack(spacing: 10) {
                if ft != nil {
                    if model.lastRecord?.canUndo == true {
                        Button(L("Çöpe gidenleri geri al")) {
                            if let r = model.lastRecord { model.undo(r) }
                            model.dismissCleanOverlay()
                        }
                        .buttonStyle(SecondaryButtonStyle(large: true))
                    }
                    Button(L("Harika")) { model.dismissCleanOverlay() }
                        .buttonStyle(PrimaryButtonStyle(large: true))
                        .keyboardShortcut(.defaultAction)
                }
            }
            .frame(height: 50)
            .opacity(ft.map { clamp(($0 - 0.8) / 0.4) } ?? 0)
        }
        .padding(.horizontal, 40).padding(.vertical, 28)
        .accessibilityElement(children: .contain)
    }

    /// Bits of dirt torn off the spinning globe, flying outward and fading.
    private func flyingDirt(elapsed: Double, amount: Double) -> some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let count = Int(18 + 30 * amount)
            for i in 0..<count {
                let seed = Double(i) * 1.618
                let period = 1.1 + (seed.truncatingRemainder(dividingBy: 0.7))
                let local = (elapsed + seed).truncatingRemainder(dividingBy: period) / period
                let angle = seed * 2.4 + elapsed * 0.6
                let dist = 80 + local * 170
                let p = CGPoint(x: c.x + CGFloat(cos(angle) * dist), y: c.y + CGFloat(sin(angle) * dist * 0.8))
                let s = CGFloat(2.5 + (seed * 7).truncatingRemainder(dividingBy: 3.5)) * CGFloat(1 - local * 0.6)
                var g = ctx
                g.opacity = (1 - local) * 0.85
                g.fill(Path(ellipseIn: CGRect(x: p.x - s / 2, y: p.y - s / 2, width: s, height: s)),
                       with: .color(i % 3 == 0 ? Color(.sRGB, red: 0.55, green: 0.45, blue: 0.34) : Color(.sRGB, red: 0.36, green: 0.30, blue: 0.24)))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// A ring of light that sweeps out when the world turns clean.
    private func shockwave(_ ft: Double) -> some View {
        let p = clamp(ft / 1.1)
        return ZStack {
            Circle().strokeBorder(KColor.success.opacity(0.7 * (1 - p)), lineWidth: 3)
                .frame(width: 180 + 260 * p, height: 180 + 260 * p)
            Circle().strokeBorder(KColor.accent.opacity(0.5 * (1 - clamp((ft - 0.15) / 1.1))), lineWidth: 2)
                .frame(width: 180 + 220 * clamp((ft - 0.15) / 1.1), height: 180 + 220 * clamp((ft - 0.15) / 1.1))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Green check badge at the globe's lower right, popping in with a small overshoot.
    private func badge(_ ft: Double) -> some View {
        let p = clamp((ft - 0.55) / 0.45)
        return ZStack {
            Circle().fill(KColor.success).frame(width: 56, height: 56)
                .shadow(color: KColor.success.opacity(0.6), radius: 14)
            Image(systemName: "checkmark").font(.system(size: 26, weight: .heavy)).foregroundStyle(KColor.bg)
        }
        .scaleEffect(p < 1 ? backOut(p) : 1)
        .opacity(p > 0 ? 1 : 0)
        .offset(x: 95, y: 95)
        .accessibilityLabel(L("Temizlik tamamlandı"))
    }

    private func subtitle(_ r: CleanRecord) -> String {
        var parts: [String] = []
        if let m = r.measuredFreed, m > 0 { parts.append(L("Diskte {0} yer açıldı.", KBytes.format(m))) }
        if r.bytesInTrash > 0 { parts.append(L("{0} çöp kutusunda; istersen geri alabilirsin.", KBytes.format(r.bytesInTrash))) }
        if r.skippedCount > 0 { parts.append(L("{0} kalem atlandı (açık uygulama ya da güvenlik kontrolü).", r.skippedCount)) }
        return parts.isEmpty ? L("Uygulamalar önbelleklerini gerektiğinde yeniden oluşturur.") : parts.joined(separator: " ")
    }

    // MARK: easing

    private func clamp(_ v: Double) -> Double { min(1, max(0, v)) }
    private func easeOut(_ v: Double) -> Double { let x = clamp(v); return 1 - pow(1 - x, 3) }
    private func backOut(_ v: Double) -> Double {
        let c1 = 1.70158, c3 = c1 + 1, x = v - 1
        return 1 + c3 * x * x * x + c1 * x * x
    }
}
