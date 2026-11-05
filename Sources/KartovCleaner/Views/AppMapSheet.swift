import SwiftUI
import AppKit
import KartovCore

/// Shows the dependency map above everything when a program is chosen.
struct AppMapOverlay: View {
    @ObservedObject private var map = AppMap.shared
    var body: some View {
        if let t = map.target { AppMapSheet(target: t) }
    }
}

/// App Dependency Map: the program in the middle, the files it keeps around it.
struct AppMapSheet: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var map = AppMap.shared
    let target: AppMapTarget

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
                .onTapGesture { if !map.busy { map.close() } }
            VStack(alignment: .leading, spacing: 14) {
                header
                graph.frame(height: 270)
                if let m = map.message {
                    Label(m, systemImage: "info.circle.fill").font(.system(size: 12, weight: .medium))
                        .foregroundStyle(KColor.accentSoft)
                }
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(map.nodes) { n in NodeRow(node: n) }
                    }
                }
                .frame(maxHeight: 250)
                Text(L("Yalnızca önbellek, kayıtlar, pencere durumu ve web verisi çöp kutusuna taşınabilir; program kapalıyken ve sen onaylayınca. Ayarlar ve destek dosyaları yalnızca gösterilir."))
                    .font(.system(size: 11)).foregroundStyle(KColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(22)
            .frame(width: 760)
            .background(RoundedRectangle(cornerRadius: 22).fill(KColor.surface))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(KColor.border))
            .shadow(color: .black.opacity(0.4), radius: 24, y: 10)
        }
        .transition(.opacity)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Group {
                if let icon = target.icon { Image(nsImage: icon).resizable() }
                else { Image(systemName: "app.dashed").resizable().scaledToFit().foregroundStyle(KColor.textMuted) }
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(target.name).font(.system(size: 20, weight: .bold))
                Text(map.loading ? L("Dosyaları aranıyor…")
                     : L("Library'de {0} · {1} yerde", KBytes.format(map.total), map.nodes.reduce(0) { $0 + $1.urls.count }))
                    .font(.system(size: 12)).foregroundStyle(KColor.textMuted)
            }
            Spacer()
            if map.isRunning {
                CountChip(text: L("Açık"), color: KColor.warning).help(L("Program açıkken dosyaları taşınamaz."))
            }
            Button { map.close() } label: {
                Image(systemName: "xmark").font(.system(size: 13, weight: .semibold)).foregroundStyle(KColor.textMuted)
                    .frame(width: 28, height: 28).background(Circle().fill(KColor.surface2))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
    }

    private var graph: some View {
        GeometryReader { g in
            let nodes = map.nodes
            let c = CGPoint(x: g.size.width / 2, y: g.size.height / 2)
            let radius = min(g.size.width, g.size.height) / 2 - 46
            let maxBytes = Double(max(1, nodes.map(\.bytes).max() ?? 1))
            ZStack {
                Canvas { ctx, _ in
                    for (i, n) in nodes.enumerated() {
                        let p = point(i, nodes.count, c, radius)
                        var line = Path()
                        line.move(to: c)
                        line.addLine(to: p)
                        let w = 1 + 3 * CGFloat(Double(n.bytes) / maxBytes)
                        ctx.stroke(line, with: .color((n.kind.removable ? KColor.accent : KColor.textMuted).opacity(0.45)),
                                   style: StrokeStyle(lineWidth: w, lineCap: .round, dash: n.kind == .startup ? [4, 4] : []))
                    }
                }
                Group {
                    if let icon = target.icon { Image(nsImage: icon).resizable() }
                    else { Image(systemName: "app.dashed").resizable().scaledToFit() }
                }
                .frame(width: 64, height: 64)
                .padding(10)
                .background(Circle().fill(KColor.surface2))
                .overlay(Circle().strokeBorder(KColor.accent.opacity(0.6), lineWidth: 2))
                .position(c)
                if map.loading {
                    ProgressView().controlSize(.small).position(x: c.x, y: c.y + 58)
                } else if nodes.isEmpty {
                    Text(L("Bu program Library'de iz bırakmamış."))
                        .font(.system(size: 12)).foregroundStyle(KColor.textMuted)
                        .position(x: c.x, y: c.y + 64)
                }
                ForEach(Array(nodes.enumerated()), id: \.element.id) { i, n in
                    NodeBubble(node: n, share: Double(n.bytes) / maxBytes)
                        .position(point(i, nodes.count, c, radius))
                }
            }
        }
    }

    private func point(_ i: Int, _ n: Int, _ c: CGPoint, _ r: CGFloat) -> CGPoint {
        let a = -Double.pi / 2 + Double(i) / Double(max(1, n)) * 2 * Double.pi
        return CGPoint(x: c.x + CGFloat(cos(a)) * r * 1.45, y: c.y + CGFloat(sin(a)) * r)
    }
}

struct NodeBubble: View {
    let node: FootprintNode
    let share: Double
    var body: some View {
        let tint = node.kind.removable ? KColor.accent : (node.kind == .startup ? KColor.warning : KColor.keep)
        VStack(spacing: 2) {
            Image(systemName: node.kind.symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(tint)
            Text(node.kind.title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
            Text(node.kind == .startup ? L("{0} öğe", node.urls.count) : KBytes.format(node.bytes))
                .font(.system(size: 10.5).monospacedDigit()).foregroundStyle(KColor.textMuted)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .frame(minWidth: 86 + 30 * CGFloat(share))
        .background(RoundedRectangle(cornerRadius: 12).fill(KColor.surface2))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(tint.opacity(0.5)))
    }
}

struct NodeRow: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var map = AppMap.shared
    let node: FootprintNode

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: node.kind.symbol).font(.system(size: 13, weight: .semibold))
                .foregroundStyle(node.kind.removable ? KColor.accent : KColor.textMuted)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8).fill(KColor.surface2))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(node.kind.title).font(.system(size: 13, weight: .semibold))
                    Text(node.kind == .startup ? L("{0} öğe", node.urls.count) : KBytes.format(node.bytes))
                        .font(.system(size: 12).monospacedDigit()).foregroundStyle(KColor.textMuted)
                }
                Text(node.kind.note).font(.system(size: 11)).foregroundStyle(KColor.textMuted)
                Text(node.urls.map { abbreviate($0.path) }.joined(separator: "  ·  "))
                    .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(KColor.textMuted)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Button(L("Göster")) { if let u = node.urls.first { Finder.reveal(u.path) } }
                .buttonStyle(SecondaryButtonStyle())
            if node.kind.removable && node.bytes > 0 {
                if map.confirm == node.kind {
                    Button(L("Vazgeç")) { map.confirm = nil }.buttonStyle(SecondaryButtonStyle())
                    Button(L("Çöpe taşı")) { map.trash(node, model: model) }.buttonStyle(PrimaryButtonStyle())
                        .disabled(map.busy)
                } else {
                    Button(L("Çöpe taşı…")) { map.confirm = node.kind }.buttonStyle(SecondaryButtonStyle())
                        .disabled(map.busy || map.isRunning)
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(KColor.surface2.opacity(0.45)))
    }
}
