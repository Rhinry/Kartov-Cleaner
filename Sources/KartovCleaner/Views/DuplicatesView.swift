import SwiftUI
import AppKit
import KartovCore

/// Full scan › Kopyalar: groups of files with exactly the same contents. One file of every group
/// is kept (marked, not selectable); the user picks which of the others go to the Trash.
struct DuplicatesList: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let groups = model.dupVisible
        LazyVStack(spacing: 10) {
            if groups.isEmpty {
                Text(model.fullQuery.trimmingCharacters(in: .whitespaces).isEmpty
                     ? L("Aynı içerikte dosya bulunamadı.") : L("Bu aramaya uyan kopya yok."))
                    .font(.system(size: 13)).foregroundStyle(KColor.textMuted)
                    .padding(.top, 40)
            }
            ForEach(groups.prefix(model.fullLimit)) { g in DuplicateGroupCard(group: g) }
            if groups.count > model.fullLimit {
                Button(L("{0} grup daha göster", groups.count - model.fullLimit)) { model.fullLimit += 300 }
                    .buttonStyle(SecondaryButtonStyle())
                    .padding(.vertical, 12)
            }
        }
        .padding(.horizontal, 16).padding(.bottom, 16)
    }
}

struct DuplicateGroupCard: View {
    @EnvironmentObject var model: AppModel
    let group: DuplicateGroup

    var body: some View {
        let keep = model.keepID(for: group)
        let first = group.files.first { $0.id == keep } ?? group.files[0]
        let reclaim = group.reclaimable(keeping: keep)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Image(nsImage: IconCache.icon(for: first.entry.url))
                    .resizable().interpolation(.high).frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(first.entry.name).font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.middle)
                    Text(L("{0} kopya · her biri {1}", group.files.count, KBytes.format(group.size)))
                        .font(.system(size: 11)).foregroundStyle(KColor.textMuted)
                }
                Spacer(minLength: 12)
                if reclaim > 0 {
                    ReclaimDot()
                    Text(KBytes.format(reclaim)).font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(KColor.heat)
                } else {
                    Text(L("Yer kaplamıyor")).font(.system(size: 12)).foregroundStyle(KColor.textMuted)
                }
            }
            .padding(.horizontal, 10).padding(.top, 6).padding(.bottom, 4)
            ForEach(group.files) { f in DuplicateRow(file: f, group: group, kept: f.id == keep) }
        }
        .kCard(padding: 6, radius: 16)
    }
}

struct DuplicateRow: View {
    @EnvironmentObject var model: AppModel
    let file: DuplicateFile
    let group: DuplicateGroup
    let kept: Bool

    private var selected: Bool { model.fullSelected.contains(file.id) }

    var body: some View {
        HStack(spacing: 8) {
            Button { model.toggleFull(file.entry) } label: {
                HStack(spacing: 12) {
                    Image(systemName: kept ? "checkmark.seal" : (selected ? "checkmark.circle.fill" : "circle"))
                        .font(.system(size: 15))
                        .foregroundStyle(selected && !kept ? KColor.accent : KColor.textMuted)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(abbreviate(file.entry.url.deletingLastPathComponent().path))
                            .font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                        Text(subtitle).font(.system(size: 11)).foregroundStyle(KColor.textMuted).lineLimit(1)
                    }
                    Spacer(minLength: 12)
                    if kept {
                        Text(L("Tutulacak")).font(.system(size: 11, weight: .medium)).foregroundStyle(KColor.textMuted)
                            .padding(.horizontal, 8).frame(height: 20)
                            .background(Capsule().fill(KColor.surface2))
                    }
                }
                .padding(.horizontal, 10).frame(height: 40)
                .background(RoundedRectangle(cornerRadius: 9).fill(selected && !kept ? KColor.accent.opacity(0.10) : Color.clear))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(kept)
            .accessibilityLabel(accessibility)

            if !kept {
                Button(L("Bunu tut")) { model.setKeep(file.id, in: group) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(KColor.accent)
            }
            RevealButtons(url: file.entry.url, isMedia: file.entry.kind == .video || file.entry.kind == .audio)
        }
    }

    private var subtitle: String {
        var parts = [file.entry.name]
        if let d = file.entry.modified { parts.append(relativeDay(d)) }
        if file.isClone { parts.append(L("Yer kaplamıyor (klon)")) }
        return parts.joined(separator: " · ")
    }

    private var accessibility: String {
        let state = kept ? L("Tutulacak") : (selected ? L("seçili") : L("seçili değil"))
        return "\(file.entry.name), \(abbreviate(file.entry.url.deletingLastPathComponent().path)), \(state)"
    }
}
