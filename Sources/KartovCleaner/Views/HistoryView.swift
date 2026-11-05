import SwiftUI
import KartovCore

struct HistoryView: View {
    @EnvironmentObject var model: AppModel

    private var totalFreed: Int64 { model.history.reduce(0) { $0 + $1.bytesDeleted } }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: L("Geçmiş"))
            if model.history.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath").font(.system(size: 36)).foregroundStyle(KColor.textMuted)
                    Text(L("Henüz temizlik yapılmadı")).font(.system(size: 17, weight: .semibold))
                    Text(L("Her temizlik burada kalemleriyle birlikte saklanır. Çöp kutusuna gidenleri buradan geri alabilirsin."))
                        .font(.system(size: 13)).foregroundStyle(KColor.textMuted)
                        .multilineTextAlignment(.center).frame(maxWidth: 420)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            BytesText(bytes: totalFreed, size: 32, color: KColor.success)
                            Text(L("toplam kazanıldı · {0} temizlik", model.history.count))
                                .font(.system(size: 13)).foregroundStyle(KColor.textMuted)
                        }
                        VStack(spacing: 0) {
                            ForEach(model.history) { record in RecordRow(record: record) }
                        }
                        .kCard(padding: 6)
                    }
                    .padding(32)
                }
            }
        }
    }
}

struct RecordRow: View {
    @EnvironmentObject var model: AppModel
    let record: CleanRecord
    // Open/closed state lives in the model: on the macOS 27 SDK @State is a macro whose
    // plugin ships only with full Xcode, so plain `swift build` cannot expand it.
    private var open: Bool { model.openRecords.contains(record.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                Button { model.toggleRecord(record.id) } label: {
                    Image(systemName: "chevron.right").rotationEffect(.degrees(open ? 90 : 0))
                        .foregroundStyle(KColor.textMuted).frame(width: 20, height: 20).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(open ? L("Kalemleri gizle") : L("Kalemleri göster"))
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.date.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 14, weight: .semibold))
                    Text(detail).font(.system(size: 12)).foregroundStyle(KColor.textMuted)
                }
                Spacer()
                Text(KBytes.format(record.bytesCleaned)).font(.system(size: 15, weight: .semibold).monospacedDigit())
                if record.canUndo {
                    Button(L("Geri al")) { model.undo(record) }.buttonStyle(SecondaryButtonStyle())
                }
            }
            if open {
                ForEach(record.items) { item in
                    HStack {
                        Text(abbreviate(item.originalPath)).font(.system(size: 11.5, design: .monospaced))
                            .lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text(status(item)).font(.system(size: 11)).foregroundStyle(KColor.textMuted)
                        Text(KBytes.format(item.size)).font(.system(size: 11.5).monospacedDigit()).frame(width: 80, alignment: .trailing)
                    }
                    .padding(.leading, 34)
                }
            }
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(KColor.border.opacity(0.6)).frame(height: 1) }
    }

    private var detail: String {
        var parts = [L("{0} kalem", record.items.filter { $0.status != .skipped && $0.status != .failed }.count)]
        if record.automatic == true { parts.insert(L("Otomatik bakım"), at: 0) }
        if record.bytesInTrash > 0 { parts.append(L("{0} çöp kutusuna", KBytes.format(record.bytesInTrash))) }
        if record.skippedCount > 0 { parts.append(L("{0} atlandı", record.skippedCount)) }
        if record.undoneAt != nil { parts.append(L("geri alındı")) }
        return parts.joined(separator: " · ")
    }

    private func status(_ item: CleanItemRecord) -> String {
        switch item.status {
        case .deleted: return L("silindi")
        case .trashed: return L("çöp kutusunda")
        case .restored: return L("geri alındı")
        case .skipped: return L("atlandı") + (item.reason.map { " · \($0)" } ?? "")
        case .failed: return L("olmadı") + (item.reason.map { " · \($0)" } ?? "")
        }
    }
}
