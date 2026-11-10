import SwiftUI
import AppKit
import KartovCore

struct HistoryView: View {
    @EnvironmentObject var model: AppModel

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
                        PassportCard()
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
                HStack(spacing: 8) {
                    ForEach(Passport.sections(of: [record], model: model).prefix(4)) { row in
                        CountChip(text: "\(row.title) · \(KBytes.format(row.bytes))", color: KColor.accentSoft)
                    }
                    Spacer()
                    Button { Passport.copyReport(record, model: model) } label: {
                        Label(L("Raporu kopyala"), systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(KColor.accentSoft)
                }
                .padding(.leading, 34)
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


// MARK: - Cleanup Passport

/// What every cleanup so far has added up to.
struct PassportCard: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let records = model.history.filter { $0.undoneAt == nil }
        let total = records.reduce(Int64(0)) { $0 + $1.bytesCleaned }
        let first = records.map(\.date).min()
        let sections = Passport.sections(of: records, model: model)
        let months = Passport.months(records)
        let top = Passport.topApps(records).first
        let maxSection = Double(max(1, sections.first?.bytes ?? 1))
        let maxMonth = Double(max(1, months.map(\.bytes).max() ?? 1))
        HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 6) {
                Label(L("Temizlik pasaportu"), systemImage: "seal.fill")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(KColor.textMuted)
                BytesText(bytes: total, size: 34, color: KColor.success)
                Text(first.map { L("{0} temizlik · {1} tarihinden beri", records.count, $0.formatted(date: .abbreviated, time: .omitted)) }
                     ?? L("{0} temizlik", records.count))
                    .font(.system(size: 12)).foregroundStyle(KColor.textMuted)
                if let top {
                    Text(L("En çok yer açan: {0} ({1})", top.0, KBytes.format(top.1)))
                        .font(.system(size: 12)).foregroundStyle(KColor.textMuted)
                }
                Text(L("{0} otomatik bakım", records.filter { $0.automatic == true }.count))
                    .font(.system(size: 12)).foregroundStyle(KColor.textMuted)
            }
            .frame(width: 250, alignment: .leading)
            VStack(alignment: .leading, spacing: 8) {
                Text(L("Bölümler")).font(.system(size: 11, weight: .semibold)).foregroundStyle(KColor.textMuted)
                ForEach(sections.prefix(5)) { row in
                    HStack(spacing: 8) {
                        Text(row.title).font(.system(size: 12)).lineLimit(1).frame(width: 150, alignment: .leading)
                        Bar(fraction: Double(row.bytes) / maxSection, tint: KColor.accent)
                        Text(KBytes.format(row.bytes)).font(.system(size: 11.5).monospacedDigit()).frame(width: 70, alignment: .trailing)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 8) {
                Text(L("Son 6 ay")).font(.system(size: 11, weight: .semibold)).foregroundStyle(KColor.textMuted)
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(months) { m in
                        VStack(spacing: 4) {
                            Capsule().fill(m.bytes > 0 ? AnyShapeStyle(KGradient.success) : AnyShapeStyle(KColor.surface2))
                                .frame(width: 18, height: max(4, 70 * CGFloat(Double(m.bytes) / maxMonth)))
                                .help(KBytes.format(m.bytes))
                            Text(m.title).font(.system(size: 10)).foregroundStyle(KColor.textMuted)
                        }
                    }
                }
                .frame(height: 92, alignment: .bottom)
            }
        }
        .kCard(padding: 18)
    }
}

/// A labelled amount for the passport lists.
struct PassportRow: Identifiable {
    let title: String
    let bytes: Int64
    var id: String { title }
}

enum Passport {
    /// Bytes per cleanup section, largest first.
    @MainActor static func sections(of records: [CleanRecord], model: AppModel) -> [PassportRow] {
        var d: [String: Int64] = [:]
        for r in records {
            for i in r.items where i.status == .trashed || i.status == .deleted {
                d[title(for: i.ruleID, model: model), default: 0] += i.size
            }
        }
        return d.sorted { $0.value > $1.value }.map { PassportRow(title: $0.key, bytes: $0.value) }
    }

    @MainActor static func title(for ruleID: String, model: AppModel) -> String {
        if ruleID == "fullscan" { return L("Tam tarama") }
        if ruleID.hasPrefix("appmap.") { return L("Bağlantılı dosyalar") }
        if ruleID.hasPrefix("projects.") { return L("Proje önbellekleri") }
        return model.rule(ruleID)?.group.title ?? L("Diğer")
    }

    static func topApps(_ records: [CleanRecord]) -> [(String, Int64)] {
        var d: [String: Int64] = [:]
        for r in records {
            for i in r.items where i.status == .trashed || i.status == .deleted { d[i.appKey, default: 0] += i.size }
        }
        return d.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    /// The last six months, oldest first: (short month name, bytes).
    static func months(_ records: [CleanRecord], now: Date = Date()) -> [PassportRow] {
        let cal = Calendar.current
        let f = DateFormatter()
        f.locale = I18n.locale
        f.dateFormat = "LLL"
        guard let thisMonth = cal.dateInterval(of: .month, for: now)?.start else { return [] }
        return (0..<6).reversed().compactMap { back -> PassportRow? in
            guard let start = cal.date(byAdding: .month, value: -back, to: thisMonth),
                  let end = cal.date(byAdding: .month, value: 1, to: start) else { return nil }
            let bytes = records.filter { $0.date >= start && $0.date < end }.reduce(Int64(0)) { $0 + $1.bytesCleaned }
            return PassportRow(title: f.string(from: start), bytes: bytes)
        }
    }

    /// A plain-text summary of one cleanup, copied to the clipboard.
    @MainActor static func copyReport(_ r: CleanRecord, model: AppModel) {
        var lines: [String] = []
        lines.append(L("Kartov Cleaner · temizlik raporu"))
        lines.append(L("Tarih: {0}", r.date.formatted(date: .long, time: .shortened)))
        if r.automatic == true { lines.append(L("Otomatik bakım")) }
        lines.append(L("Açılan yer: {0}", KBytes.format(r.bytesCleaned)))
        if r.bytesInTrash > 0 { lines.append(L("Çöp kutusunda: {0} (geri alınabilir)", KBytes.format(r.bytesInTrash))) }
        if r.bytesDeleted > 0 { lines.append(L("Kalıcı silinen: {0}", KBytes.format(r.bytesDeleted))) }
        let done = r.items.filter { $0.status == .trashed || $0.status == .deleted }.count
        lines.append(L("Kalem: {0} · atlanan: {1}", done, r.skippedCount))
        if r.undoneAt != nil { lines.append(L("Bu temizlik geri alındı.")) }
        lines.append("")
        lines.append(L("Bölümler"))
        for row in sections(of: [r], model: model) { lines.append("• \(row.title): \(KBytes.format(row.bytes))") }
        lines.append("")
        lines.append(L("En büyük kalemler"))
        for i in r.items.filter({ $0.status == .trashed || $0.status == .deleted }).sorted(by: { $0.size > $1.size }).prefix(10) {
            lines.append("• \(abbreviate(i.originalPath)) — \(KBytes.format(i.size))")
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }
}
