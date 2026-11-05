import SwiftUI
import KartovCore

/// The scan, kept simple: the globe, one number, one progress bar, the folder being read,
/// and a small grid with one tile per category instead of a long list of locations.
struct ScanView: View {
    @EnvironmentObject var model: AppModel

    private var isDone: Bool { model.phase != .scanning && !model.locations.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: L("Tarama")) {
                if model.phase == .scanning {
                    Button(L("Durdur")) { model.cancelScan() }.buttonStyle(SecondaryButtonStyle())
                }
            }
            ScrollView {
                VStack(spacing: 26) {
                    if model.locations.isEmpty { start } else { progress; grid }
                }
                .padding(.horizontal, 32).padding(.vertical, 28)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: before the first scan

    private var start: some View {
        VStack(spacing: 18) {
            Globe(dirt: 0.2, speed: 0.25, size: 150).frame(width: 230, height: 230)
            Text(L("Taramaya hazır")).font(.system(size: 26, weight: .bold))
            Text(L("Tarama hiçbir şeyi silmez. Bitince neyin ne kadar yer kapladığını görür, neyin silineceğine sen karar verirsin."))
                .font(.system(size: 14)).foregroundStyle(KColor.textMuted)
                .multilineTextAlignment(.center).frame(maxWidth: 440)
            Button { model.startScan() } label: { Label(L("Taramayı başlat"), systemImage: "magnifyingglass") }
                .buttonStyle(PrimaryButtonStyle(large: true))
                .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: while scanning and after

    private var progress: some View {
        VStack(spacing: 14) {
            Globe(dirt: dirtLevel(model.foundBytes), speed: isDone ? 0.25 : 1.2, size: 130)
                .frame(width: 200, height: 200)
            VStack(spacing: 2) {
                BytesText(bytes: model.foundBytes, size: 52, color: isDone ? KColor.heat : KColor.text)
                Text(isDone ? L("temizlenebilir alan bulundu") : L("bulundu · {0} dosyaya bakıldı", model.filesSeen.formatted()))
                    .font(.system(size: 13)).foregroundStyle(KColor.textMuted)
            }
            .accessibilityElement(children: .combine)

            VStack(spacing: 6) {
                ProgressView(value: isDone ? 1 : model.scanFraction)
                    .tint(isDone ? KColor.success : KColor.accent)
                    .frame(maxWidth: 420)
                Text(isDone ? L("Tarama bitti") : (model.currentPath.isEmpty ? L("Hazırlanıyor…") : abbreviate(model.currentPath)))
                    .font(.system(size: 11, design: isDone ? .default : .monospaced))
                    .foregroundStyle(KColor.textMuted)
                    .lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: 420)
            }

            if isDone {
                HStack(spacing: 10) {
                    if !model.items.isEmpty {
                        Button(L("Sonuçları gör")) { model.section = .results }
                            .buttonStyle(PrimaryButtonStyle(large: true))
                            .keyboardShortcut(.defaultAction)
                    }
                    Button(L("Yeniden tara")) { model.startScan() }
                        .buttonStyle(SecondaryButtonStyle(large: true))
                }
            }
        }
    }

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 8)], spacing: 8) {
            ForEach(categoryStates, id: \.group) { c in
                HStack(spacing: 10) {
                    statusIcon(c.status).frame(width: 16)
                    Image(systemName: c.group.symbol).font(.system(size: 12)).foregroundStyle(KColor.textMuted).frame(width: 16)
                    Text(c.group.title).font(.system(size: 12)).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(c.status == .queued ? "" : (c.bytes > 0 ? KBytes.format(c.bytes) : (c.status == .done ? L("Temiz") : "")))
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(c.bytes > 0 ? KColor.text : KColor.success)
                }
                .padding(.horizontal, 12).frame(height: 36)
                .background(RoundedRectangle(cornerRadius: 10).fill(c.status == .scanning ? AnyShapeStyle(KColor.surface2) : AnyShapeStyle(KGradient.card)))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(KGradient.rim))
                .accessibilityElement(children: .combine)
            }
        }
    }

    private enum CatStatus { case queued, scanning, done }
    private struct CatState { let group: CategoryGroup; let status: CatStatus; let bytes: Int64 }

    private var categoryStates: [CatState] {
        var byGroup: [CategoryGroup: [LocationState]] = [:]
        for loc in model.locations {
            if let g = model.rule(loc.id)?.group { byGroup[g, default: []].append(loc) }
        }
        return CategoryGroup.allCases.compactMap { g in
            guard let locs = byGroup[g] else { return nil }
            let bytes = locs.reduce(Int64(0)) { $0 + $1.bytes }
            let finished = locs.allSatisfy {
                switch $0.status { case .done, .skipped: return true; default: return false }
            }
            let started = locs.contains { $0.status != .queued }
            let status: CatStatus = finished ? .done : (started ? .scanning : .queued)
            return CatState(group: g, status: status, bytes: bytes)
        }
    }

    @ViewBuilder private func statusIcon(_ s: CatStatus) -> some View {
        switch s {
        case .done: Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(KColor.success)
        case .scanning: ProgressView().controlSize(.mini)
        case .queued: Circle().strokeBorder(KColor.textMuted.opacity(0.5), lineWidth: 1.2).frame(width: 8, height: 8)
        }
    }
}

/// `/Users/umut/Library/Caches` → `~/Library/Caches`
func abbreviate(_ path: String) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
}
