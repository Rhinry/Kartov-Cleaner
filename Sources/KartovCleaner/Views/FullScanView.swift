import SwiftUI
import AppKit
import KartovCore

/// "Tam tarama": what takes space on the Mac, by size: programs, videos, images, music,
/// documents and archives. The user sorts, picks and moves things to the Trash.
struct FullScanView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: L("Tam tarama")) {
                if model.fullScanning {
                    Button(L("Durdur")) { model.cancelFullScan() }.buttonStyle(SecondaryButtonStyle())
                } else if model.fullScanDate != nil {
                    Button(L("Yeniden tara")) { model.startFullScan() }.buttonStyle(SecondaryButtonStyle())
                }
            }
            if model.fullScanning {
                scanning
            } else if model.fullScanDate == nil {
                intro
            } else {
                results
            }
        }
        .confirmationDialog(L("{0} öğe çöp kutusuna taşınsın mı?", model.fullSelected.count),
                            isPresented: $model.showFullConfirm, titleVisibility: .visible) {
            Button(L("Çöp kutusuna taşı · {0}", KBytes.format(model.fullSelectedBytes)), role: .destructive) {
                model.trashFullSelection()
            }
            Button(L("Vazgeç"), role: .cancel) {}
        } message: {
            Text(confirmText)
        }
    }

    private var confirmText: String {
        var s = L("Kalıcı olarak silinmez; çöp kutusuna gider. Geri almak için Kartov'da Geçmiş › Geri al, ya da Finder'da Çöp Kutusu › Geri Koy. Çöp kutusunu boşaltınca yer açılır.")
        let apps = model.fullSelectedEntries.filter { $0.kind == .app }
        if !apps.isEmpty {
            s += L("\n\nProgramlar, ayarları ve önbellekleriyle birlikte kaldırılır.")
        }
        let running = model.fullSelectedRunningApps
        if !running.isEmpty {
            s += L(" Açık olanlar ({0}) önce kapatılır; kaydedilmemiş işin varsa sorarlar.", running.joined(separator: ", "))
        }
        return s
    }

    // MARK: states

    private var intro: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(KColor.accent.opacity(0.12)).frame(width: 120, height: 120)
                Image(systemName: "chart.pie.fill").font(.system(size: 50)).foregroundStyle(KColor.accent)
            }
            Text(L("Mac'inde ne nerede?")).font(.system(size: 26, weight: .bold))
            Text(L("Programlarını, videolarını, görsellerini, müziklerini ve belgelerini boyutlarıyla listeler. İstediğin gibi sıralar, istemediklerini buradan kaldırırsın. Tarama hiçbir şeyi silmez."))
                .font(.system(size: 14)).foregroundStyle(KColor.textMuted)
                .multilineTextAlignment(.center).frame(maxWidth: 460)
            Button { model.startFullScan() } label: { Label(L("Tam taramayı başlat"), systemImage: "chart.pie") }
                .buttonStyle(PrimaryButtonStyle(large: true))
                .keyboardShortcut(.defaultAction)
            Text(L("Bir iki dakika sürebilir.")).font(.system(size: 12)).foregroundStyle(KColor.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var scanning: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large)
            Text(L("Taranıyor…")).font(.system(size: 20, weight: .semibold))
            Text(L("{0} dosyaya bakıldı", model.fullFiles.formatted())).font(.system(size: 13).monospacedDigit())
                .foregroundStyle(KColor.textMuted)
            Text(abbreviate(model.fullPath)).font(.system(size: 11, design: .monospaced))
                .foregroundStyle(KColor.textMuted).lineLimit(1).truncationMode(.middle).frame(maxWidth: 460)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var results: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                StorageMap()
                controls
                selectionBar
            }
            .padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 10)

            ScrollView {
                LazyVStack(spacing: 2) {
                    let list = model.fullVisible
                    if list.isEmpty {
                        Text(L("Bu filtreye uyan bir şey yok.")).font(.system(size: 13)).foregroundStyle(KColor.textMuted)
                            .padding(.top, 40)
                    }
                    ForEach(list.prefix(model.fullLimit)) { e in EntryRow(entry: e) }
                    if list.count > model.fullLimit {
                        Button(L("{0} öğe daha göster", list.count - model.fullLimit)) { model.fullLimit += 300 }
                            .buttonStyle(SecondaryButtonStyle())
                            .padding(.vertical, 12)
                    }
                }
                .kCard(padding: 6, radius: 16)
                .padding(.horizontal, 16).padding(.bottom, 16)
            }

            if !model.fullSelected.isEmpty || model.fullMessage != nil { bottomBar }
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip(nil, L("Tümü"), model.fullEntries.reduce(Int64(0)) { $0 + $1.size })
                    ForEach(DiskKind.allCases, id: \.self) { k in
                        let b = model.bytes(of: k)
                        if b > 0 { chip(k, k.title, b) }
                    }
                }
            }
            Picker(L("Sırala"), selection: Binding(get: { model.fullSort }, set: { model.fullSort = $0 })) {
                ForEach(FullSort.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 210)
            TextField(L("Ara"), text: Binding(get: { model.fullQuery }, set: { model.fullQuery = $0; model.fullLimit = 200 }))
                .textFieldStyle(.roundedBorder)
                .frame(width: 160)
        }
    }

    /// Select everything shown (respecting the filter and search), or clear it.
    private var selectionBar: some View {
        let visible = model.fullSelectableVisible
        let visibleBytes = visible.reduce(Int64(0)) { $0 + $1.size }
        return HStack(spacing: 10) {
            Button {
                model.selectAllVisible()
            } label: {
                Label(model.fullAllVisibleSelected ? L("Bunların seçimini kaldır") : L("Tümünü seç · {0} öğe · {1}", visible.count, KBytes.format(visibleBytes)),
                      systemImage: model.fullAllVisibleSelected ? "minus.circle" : "checkmark.circle")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(KColor.accent)
            .disabled(visible.isEmpty)
            if !model.fullSelected.isEmpty {
                Button(L("Seçimi kaldır")) { model.clearFullSelection() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(KColor.textMuted)
            }
            Spacer()
            Text(L("İpucu: Bir satıra tıkla, sonra Shift ile başka birine tıkla; aradakilerin hepsi seçilir."))
                .font(.system(size: 11)).foregroundStyle(KColor.textMuted)
                .lineLimit(1)
        }
    }

    private func chip(_ kind: DiskKind?, _ title: String, _ bytes: Int64) -> some View {
        let on = model.fullFilter == kind
        return Button {
            model.fullFilter = kind
            model.fullLimit = 200
        } label: {
            HStack(spacing: 6) {
                if let kind { Circle().fill(kind.color).frame(width: 7, height: 7) }
                Text(title).font(.system(size: 12, weight: on ? .semibold : .regular))
                Text(KBytes.format(bytes)).font(.system(size: 11).monospacedDigit()).foregroundStyle(KColor.textMuted)
            }
            .padding(.horizontal, 10).frame(height: 28)
            .background(Capsule().fill(on ? KColor.surface2 : Color.clear))
            .overlay(Capsule().strokeBorder(on ? KColor.accent : KColor.border))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var bottomBar: some View {
        HStack(spacing: 14) {
            if model.fullSelected.isEmpty, let m = model.fullMessage {
                Label(m, systemImage: "checkmark.circle.fill").font(.system(size: 12)).foregroundStyle(KColor.success)
                Spacer()
                Button(L("Geçmiş'e git")) { model.section = .history }.buttonStyle(SecondaryButtonStyle())
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("{0} öğe · {1}", model.fullSelected.count, KBytes.format(model.fullSelectedBytes)))
                        .font(.system(size: 14, weight: .semibold).monospacedDigit())
                    Text(L("Çöp kutusuna gider, geri alınabilir.")).font(.system(size: 11)).foregroundStyle(KColor.textMuted)
                }
                Spacer()
                Button(L("Seçimi kaldır")) { model.clearFullSelection() }.buttonStyle(SecondaryButtonStyle())
                Button(L("Çöp kutusuna taşı")) { model.showFullConfirm = true }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 12)
        .background(KColor.chrome)
        .overlay(alignment: .top) { Rectangle().fill(KColor.border.opacity(0.6)).frame(height: 1) }
    }
}

/// One stacked bar: how the space splits across programs, videos, images...
struct StorageMap: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let kinds = DiskKind.allCases.map { KindBytes(kind: $0, bytes: model.bytes(of: $0)) }.filter { $0.bytes > 0 }
        let total = max(kinds.reduce(Int64(0)) { $0 + $1.bytes }, 1)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(KBytes.format(total)).font(.system(size: 26, weight: .bold).monospacedDigit())
                Text(L("programların ve dosyaların kapladığı alan")).font(.system(size: 13)).foregroundStyle(KColor.textMuted)
                Spacer()
                if let d = model.fullScanDate {
                    Text(L("Taranma {0}", relativeDay(d))).font(.system(size: 11)).foregroundStyle(KColor.textMuted)
                }
            }
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(kinds) { kb in
                        Rectangle().fill(kb.kind.color)
                            .frame(width: max(2, (geo.size.width - CGFloat(kinds.count * 2)) * CGFloat(kb.bytes) / CGFloat(total)))
                            .help("\(kb.kind.title): \(KBytes.format(kb.bytes))")
                            .onTapGesture { model.fullFilter = kb.kind; model.fullLimit = 200 }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .frame(height: 12)
        }
        .accessibilityElement(children: .combine)
    }
}

struct KindBytes: Identifiable {
    let kind: DiskKind
    let bytes: Int64
    var id: DiskKind { kind }
}

struct EntryRow: View {
    @EnvironmentObject var model: AppModel
    let entry: DiskEntry

    private var selected: Bool { model.fullSelected.contains(entry.id) }

    var body: some View {
        HStack(spacing: 8) {
            Button { model.toggleFull(entry) } label: {
                HStack(spacing: 12) {
                    Image(systemName: entry.protected ? "lock" : (selected ? "checkmark.circle.fill" : "circle"))
                        .font(.system(size: 15))
                        .foregroundStyle(entry.protected ? KColor.textMuted : (selected ? KColor.accent : KColor.textMuted))
                        .frame(width: 18)
                    Image(nsImage: IconCache.icon(for: entry.url))
                        .resizable().interpolation(.high).frame(width: 26, height: 26)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.name).font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.middle)
                        Text(subtitle).font(.system(size: 11)).foregroundStyle(KColor.textMuted).lineLimit(1)
                    }
                    Spacer(minLength: 12)
                    Circle().fill(entry.kind.color).frame(width: 6, height: 6)
                    Text(KBytes.format(entry.size)).font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .frame(minWidth: 70, alignment: .trailing)
                }
                .padding(.horizontal, 10).frame(height: 44)
                .background(RoundedRectangle(cornerRadius: 9).fill(selected ? KColor.accent.opacity(0.10) : Color.clear))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(entry.protected)
            .accessibilityLabel("\(entry.name), \(KBytes.format(entry.size)), \(selected ? L("seçili") : L("seçili değil"))")

            RevealButtons(url: entry.url, isMedia: entry.kind == .video || entry.kind == .audio)
        }
    }

    private var subtitle: String {
        if entry.protected {
            return entry.kind == .app ? L("macOS ile gelir · kaldırılamaz") : L("Arşiv · kendi uygulamasından yönet")
        }
        if entry.kind == .app {
            if let d = entry.lastUsed { return L("Programlar · son açılış {0}", relativeDay(d)) }
            return L("Programlar")
        }
        let folder = abbreviate(entry.url.deletingLastPathComponent().path)
        if let d = entry.modified { return "\(folder) · \(relativeDay(d))" }
        return folder
    }
}

extension DiskKind {
    var color: Color {
        switch self {
        case .app: return KColor.accent
        case .video: return KColor.heat
        case .image: return Color(.sRGB, red: 0.71, green: 0.55, blue: 1.0)
        case .audio: return KColor.success
        case .document: return KColor.warning
        case .archive: return KColor.keep
        case .other: return KColor.textMuted
        }
    }
}

/// File icons are slow to fetch; keep them while the app runs.
enum IconCache {
    private static var cache: [String: NSImage] = [:]
    static func icon(for url: URL) -> NSImage {
        if let i = cache[url.path] { return i }
        let i = NSWorkspace.shared.icon(forFile: url.path)
        cache[url.path] = i
        return i
    }
}
