import SwiftUI
import KartovCore

struct ResultsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: L("Önbellekler")) {
                if !model.items.isEmpty && model.phase != .done {
                    Button(L("Seçimi sıfırla")) { model.resetChoices() }.buttonStyle(SecondaryButtonStyle())
                }
                Button(L("Yeniden tara")) { model.startScan() }.buttonStyle(SecondaryButtonStyle())
            }
            gainBar
            if model.items.isEmpty && model.phase != .done {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2, pinnedViews: []) {
                        SystemDataCard().padding(.top, 16)
                        ForEach(CategoryGroup.allCases, id: \.self) { section in
                            let groups = model.groups.filter { $0.section == section }
                            if !groups.isEmpty {
                                HStack(spacing: 8) {
                                    Image(systemName: section.symbol)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(section.isUserData ? KColor.warning : KColor.textMuted)
                                    Text(section.title)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(section.isUserData ? KColor.warning : KColor.textMuted)
                                    Spacer()
                                    Text(KBytes.format(groups.reduce(Int64(0)) { $0 + $1.size }))
                                        .font(.system(size: 12).monospacedDigit()).foregroundStyle(KColor.textMuted)
                                }
                                .padding(.horizontal, 12).padding(.top, 22).padding(.bottom, 4)
                                if section.isUserData { TrashInfo().padding(.horizontal, 12).padding(.bottom, 6) }
                                if section == .privacy {
                                    Text(L("İsteğe bağlı. Çerezleri silersen sitelerden çıkış yaparsın."))
                                        .font(.system(size: 12)).foregroundStyle(KColor.textMuted)
                                        .padding(.horizontal, 12).padding(.bottom, 4)
                                }
                                VStack(spacing: 0) {
                                    ForEach(groups) { g in GroupRows(group: g) }
                                }
                                .kCard(padding: 6, radius: 16)
                                .padding(.horizontal, 4)
                            }
                        }
                        Text(L("Satıra tıklamak seçimi değiştirir. \"Koru\" dediğin önbellekler sonraki taramalarda da korunur."))
                            .font(.system(size: 12)).foregroundStyle(KColor.textMuted)
                            .padding(.horizontal, 12).padding(.vertical, 20)
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    // MARK: header with the live total

    @ViewBuilder private var gainBar: some View {
        HStack(alignment: .center, spacing: 28) {
            VStack(alignment: .leading, spacing: 2) {
                if model.phase == .done, let r = model.lastRecord {
                    Text(L("Kazandın")).font(.system(size: 14)).foregroundStyle(KColor.textMuted)
                    BytesText(bytes: r.bytesDeleted, size: 56, color: KColor.success)
                    Text(doneDetail(r)).font(.system(size: 13)).foregroundStyle(KColor.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(L("Seçtiklerin temizlenince kazanacağın alan")).font(.system(size: 14)).foregroundStyle(KColor.textMuted)
                    BytesText(bytes: model.selectedBytes, size: 56,
                              color: model.selectedBytes > 0 ? KColor.heat : KColor.textMuted)
                    Text(selectionDetail).font(.system(size: 13)).foregroundStyle(KColor.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            if !model.items.isEmpty && model.phase != .done {
                VStack(alignment: .leading, spacing: 8) {
                    ShareBar(selected: model.selectedBytes, kept: model.keptBytes, locked: model.lockedBytes)
                    HStack(spacing: 14) {
                        LegendDot(color: KColor.heat, text: L("Temizlenecek"))
                        LegendDot(color: KColor.keep, text: L("Korunuyor"))
                        LegendDot(color: KColor.textMuted, text: L("Açık uygulama"))
                    }
                }
                .frame(width: 320)
            }

            if model.phase == .cleaning {
                VStack(spacing: 6) {
                    ProgressView(value: model.cleaningProgress).frame(width: 160)
                    Text(L("Temizleniyor…")).font(.system(size: 12)).foregroundStyle(KColor.textMuted)
                }
            } else if model.phase == .done, let r = model.lastRecord {
                HStack(spacing: 10) {
                    if r.canUndo {
                        Button(L("Çöpe gidenleri geri al")) { model.undo(r) }
                            .buttonStyle(SecondaryButtonStyle(large: true))
                    }
                    Button(L("Bitti")) { model.phase = model.items.isEmpty ? .idle : .results; model.lastRecord = nil }
                        .buttonStyle(PrimaryButtonStyle(large: true))
                }
            } else if !model.items.isEmpty {
                if model.lockedBytes > 0 {
                    Button(L("Açık uygulamaları kapat")) { model.quitAllLockedApps() }
                        .buttonStyle(SecondaryButtonStyle(large: true))
                        .help(L("Önbelleği kilitli uygulamalara kapanmalarını söyler; kaydedilmemiş işin varsa sorarlar."))
                }
                Button {
                    model.requestClean()
                } label: {
                    Text(model.selectedBytes > 0 ? L("Temizle · {0}", KBytes.format(model.selectedBytes)) : L("Seçim yok"))
                }
                .buttonStyle(PrimaryButtonStyle(large: true))
                .disabled(model.selectedBytes == 0 || model.phase == .scanning)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 28).padding(.vertical, 22)
        .background(KColor.chrome)
        .overlay(alignment: .bottom) { Rectangle().fill(KColor.border.opacity(0.6)).frame(height: 1) }
        .confirmationDialog(forceTitle, isPresented: forceBinding, titleVisibility: .visible) {
            Button(L("Zorla kapat"), role: .destructive) {
                if let g = model.forceQuitTarget { model.quitApps(for: g, force: true) }
                model.forceQuitTarget = nil
            }
            Button(L("Vazgeç"), role: .cancel) { model.forceQuitTarget = nil }
        } message: {
            Text(L("Uygulama kaydetmeni beklemeden hemen kapanır. Kaydedilmemiş projeler ve belgeler kaybolur."))
        }
        .confirmationDialog(confirmTitle, isPresented: $model.showConfirm, titleVisibility: .visible) {
            Button(L("Temizle · {0}", KBytes.format(model.selectedBytes)), role: .destructive) { model.clean() }
            if model.confirmBytes > 0 {
                Button(skipLabel) { model.cleanSkippingConfirmItems() }
            }
            Button(L("Vazgeç"), role: .cancel) {}
        } message: {
            Text(confirmMessage)
        }
    }

    private var forceBinding: Binding<Bool> {
        Binding(get: { model.forceQuitTarget != nil }, set: { if !$0 { model.forceQuitTarget = nil } })
    }

    private var forceTitle: String {
        guard let g = model.forceQuitTarget else { return "" }
        return L("{0} zorla kapatılsın mı?", model.blockingAppNames(for: g))
    }

    private var confirmTitle: String {
        if !model.selectedHistoryBrowsers.isEmpty { return L("Tarayıcı geçmişin de silinecek") }
        if model.confirmTrashBytes > 0 { return L("Çöp kutusu kalıcı olarak boşaltılacak") }
        return L("Kişisel dosyaların çöp kutusuna taşınacak")
    }

    private var skipLabel: String {
        let history = !model.selectedHistoryBrowsers.isEmpty, trash = model.confirmTrashBytes > 0
        if history && trash { return L("Geçmişe ve çöp kutusuna dokunmadan temizle") }
        if history { return L("Geçmişi silmeden temizle") }
        return L("Çöp kutusuna dokunmadan temizle")
    }

    private var confirmMessage: String {
        var parts: [String] = []
        let browsers = model.selectedHistoryBrowsers
        if !browsers.isEmpty {
            parts.append(L("{0} geçmişi silinecek: ziyaret ettiğin siteler ve indirme listesi. Yer imleri, şifreler ve açık oturumlar kalır. Geçmiş dosyası çöp kutusuna gider; geri alabilirsin.", browsers.joined(separator: ", ")))
        }
        if model.confirmTrashBytes > 0 {
            parts.append(L("Çöp kutusundaki {0} geri alınamayacak şekilde silinecek.", KBytes.format(model.confirmTrashBytes)))
        }
        if model.selectedUserFileBytes > 0 {
            parts.append(L("Seçtiğin {0} kişisel dosya (fotoğraf, video, belge) kalıcı silinmez, çöp kutusuna taşınır. Geri almak için Geçmiş › Geri al ya da Finder'da Çöp Kutusu › Geri Koy.", KBytes.format(model.selectedUserFileBytes)))
        }
        return parts.joined(separator: "\n\n")
    }

    private var selectionDetail: String {
        if model.phase == .scanning { return L("Tarama sürüyor; liste doldukça güncellenir.") }
        if let m = model.quitMessage { return m }
        if model.selectedBytes == 0 { return L("Hiçbir şey seçilmedi. Satıra tıklayarak seçebilirsin.") }
        var parts = [L("{0} kalem", model.groups.filter { $0.selectedSize > 0 }.count)]
        if model.keptBytes > 0 { parts.append(L("{0} korunuyor", KBytes.format(model.keptBytes))) }
        let locked = model.lockedAppNames
        if !locked.isEmpty { parts.append(locked.joined(separator: ", ") + L(" açık olduğu için atlanacak")) }
        return parts.joined(separator: " · ")
    }

    private func doneDetail(_ r: CleanRecord) -> String {
        var parts: [String] = []
        if let measured = r.measuredFreed, measured > 0 {
            parts.append(L("Diskte ölçülen boş alan artışı: {0}.", KBytes.format(measured)))
        }
        if r.bytesInTrash > 0 {
            parts.append(L("{0} çöp kutusunda bekliyor; geri alabilirsin, çöpü boşaltınca yer açılır.", KBytes.format(r.bytesInTrash)))
        }
        if r.skippedCount > 0 { parts.append(L("{0} kalem atlandı (açık uygulama ya da güvenlik kontrolü).", r.skippedCount)) }
        if r.undoneAt != nil { parts.append(L("Çöpe gidenler geri yerine kondu.")) }
        return parts.isEmpty ? L("Önbellekler silindi; uygulamalar gerektiğinde yeniden oluşturur.") : parts.joined(separator: " ")
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Globe(dirt: 0.15, speed: 0.2, size: 110).frame(width: 165, height: 165)
            Text(L("Burada taranan önbellekler listelenecek")).font(.system(size: 17, weight: .semibold))
            Text(L("Her uygulama ayrı satırda, boyutuyla birlikte görünür. Hangisinin temizleneceğini sen seçersin."))
                .font(.system(size: 13)).foregroundStyle(KColor.textMuted).multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button(L("Taramayı başlat")) { model.startScan() }.buttonStyle(PrimaryButtonStyle(large: true))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// An app's row plus, when expanded, one row per cache part (After Effects → disk cache…).
struct GroupRows: View {
    @EnvironmentObject var model: AppModel
    let group: CacheGroup

    private var expandable: Bool { group.parts.count > 1 }
    private var isOpen: Bool { model.expanded.contains(group.id) || model.expanded.contains(group.title) }
    private var hasLocked: Bool { group.parts.contains(where: \.locked) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { model.toggle(group: group) } label: { mainRow }
                    .buttonStyle(RowButtonStyle())
                    .disabled(group.state == .locked || model.phase == .cleaning)
                    .accessibilityLabel(accessibility)
                trailing
            }
            if expandable && isOpen {
                ForEach(group.parts) { part in
                    Button { model.toggle(part: part) } label: { partRow(part) }
                        .buttonStyle(RowButtonStyle())
                        .disabled(part.locked || model.phase == .cleaning)
                        .padding(.leading, 44)
                }
            }
        }
    }

    /// Controls outside the row button: close an open app, or look at a personal file.
    @ViewBuilder private var trailing: some View {
        if hasLocked {
            QuitMenu(group: group)
        } else if group.section.isUserData, let url = group.parts.first?.items.first?.url {
            RevealButtons(url: url, isMedia: false)
        }
    }

    private var mainRow: some View {
        HStack(spacing: 12) {
            AppIcon(key: group.iconKey, monogram: AppIcon.monogram(group.title), hot: false)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(group.title).font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(group.state == .locked ? KColor.textMuted : KColor.text)
                        .lineLimit(1)
                    if expandable {
                        Button {
                            if isOpen { model.expanded.remove(group.id); model.expanded.remove(group.title) }
                            else { model.expanded.insert(group.id) }
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                                .rotationEffect(.degrees(isOpen ? 0 : -90))
                                .foregroundStyle(KColor.textMuted)
                                .frame(width: 18, height: 18).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L("{0} ayrıntıları", group.title))
                    }
                }
                Text(subtitle).font(.system(size: 11)).foregroundStyle(KColor.textMuted).lineLimit(1)
            }
            Spacer(minLength: 12)
            Text(KBytes.format(group.state == .mixed ? group.selectedSize : group.size))
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(group.state == .clean || group.state == .mixed ? KColor.text : KColor.textMuted)
            if group.state != .locked { KeepSwitch(state: group.state) }
        }
        .frame(height: 48)
    }

    private func partRow(_ part: CachePart) -> some View {
        let state: ToggleState = part.locked ? .locked : (part.kept ? .keep : .clean)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(part.title).font(.system(size: 12, weight: .medium))
                Text(part.detail).font(.system(size: 11)).foregroundStyle(KColor.textMuted).lineLimit(1)
            }
            Spacer(minLength: 12)
            Text(KBytes.format(part.size)).font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(part.kept ? KColor.textMuted : KColor.text)
            if !part.locked { KeepSwitch(state: state) }
        }
        .frame(height: 40)
        .help(part.items.map { abbreviate($0.url.path) }.joined(separator: "\n"))
    }

    private var subtitle: String {
        if group.section.isUserData, let item = group.parts.first?.items.first {
            return abbreviate(item.url.deletingLastPathComponent().path)
        }
        switch group.state {
        case .locked: return L("Açık · kapatınca temizlenebilir")
        case .keep: return L("Korunuyor")
        case .mixed: return L("Bir kısmı korunuyor")
        case .clean: break
        }
        if group.section == .privacy { return L("Silmeden önce sorulur · geri alınabilir") }
        if let rule = group.parts.first.flatMap({ model.rule($0.ruleID) }), rule.safety == .caution {
            return L("Çöp kutusuna gider · geri alınabilir")
        }
        if group.parts.count > 1 { return L("{0} bölüm", group.parts.count) }
        if let d = group.parts.first?.items.first?.newestModification { return L("Son değişiklik {0}", relativeDay(d)) }
        return group.section.title
    }

    private var accessibility: String {
        let s: String
        switch group.state {
        case .clean: s = L("temizlenecek")
        case .keep: s = L("korunuyor")
        case .mixed: s = L("kısmen korunuyor")
        case .locked: s = L("uygulama açık, temizlenemez")
        }
        return "\(group.title), \(KBytes.format(group.size)), \(s)"
    }
}

/// One compact control for an open app: "Kapat", with "Zorla kapat" inside the menu.
struct QuitMenu: View {
    @EnvironmentObject var model: AppModel
    let group: CacheGroup

    var body: some View {
        Group {
            if model.quitting.contains(group.id) {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(L("Kapatılıyor")).font(.system(size: 12)).foregroundStyle(KColor.textMuted)
                }
                .frame(height: 28)
            } else {
                Menu {
                    Button(L("Kapat")) { model.quitApps(for: group, force: false) }
                    Button(L("Zorla kapat…")) { model.forceQuitTarget = group }
                } label: {
                    Text(model.quitStuck.contains(group.id) ? L("Kapanmadı") : L("Kapat"))
                        .font(.system(size: 12, weight: .semibold))
                } primaryAction: {
                    model.quitApps(for: group, force: false)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(Capsule().strokeBorder(model.quitStuck.contains(group.id) ? KColor.danger : KColor.border))
                .help(L("{0} kapanır; kaydedilmemiş işin varsa sorar. Kapat düğmesinin yanındaki okta Zorla kapat seçeneği de var.", model.blockingAppNames(for: group)))
            }
        }
        .padding(.trailing, 6)
        .disabled(model.phase == .cleaning)
    }
}

struct Tag: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text).font(.system(size: 11, weight: .semibold)).foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 1)
            .background(Capsule().fill(color.opacity(0.12)))
    }
}

struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverRow(pressed: configuration.isPressed) { configuration.label }
    }
}

/// Row background that reacts to press; the whole row is the click target.
/// (No hover state: @State is a macro on the macOS 27 SDK and needs full Xcode to expand.)
struct HoverRow<Content: View>: View {
    let pressed: Bool
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, 12)
            .background(RoundedRectangle(cornerRadius: 10)
                .fill(pressed ? KColor.surface2 : Color.clear))
            .contentShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// Shown above the user's own files: these are offers, not recommendations.
struct UserFilesWarning: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(KColor.warning)
            Text(L("Bunlar senin dosyaların. Kartov hiçbirini kendiliğinden seçmez. Seçtiklerin kalıcı olarak silinmez, çöp kutusuna gider; çöp kutusu boşaltılınca yer açılır. Emin değilsen imleci satırın üzerinde tutup dosyanın tam yerini gör."))
                .font(.system(size: 12)).foregroundStyle(KColor.text.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(KColor.warning.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(KColor.warning.opacity(0.35)))
        .padding(.horizontal, 12).padding(.bottom, 6)
    }
}

/// Time Machine local snapshots and unfinished macOS updates: needs the administrator password.
struct SystemDataCard: View {
    @EnvironmentObject var model: AppModel

    private var hasSomething: Bool { (model.snapshotCount ?? 0) > 0 || model.installDataPresent }

    var body: some View {
        if hasSomething || model.systemPurgeMessage != nil || model.systemPurging {
            HStack(spacing: 12) {
                Image(systemName: "internaldrive.fill").foregroundStyle(hasSomething ? KColor.heat : KColor.success)
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("Sistem Verisi")).font(.system(size: 13, weight: .semibold))
                    Text(model.systemPurgeMessage ?? detail).font(.system(size: 11))
                        .foregroundStyle(model.systemPurgeMessage == nil ? KColor.textMuted : KColor.success)
                        .lineLimit(2)
                }
                Spacer(minLength: 12)
                if model.systemPurging {
                    ProgressView().controlSize(.small)
                } else if hasSomething {
                    Button(L("Temizle (şifre ister)")) { model.purgeSystemData() }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12).fill(KColor.surface))
            .padding(.horizontal, 12)
        }
    }

    private var detail: String {
        var parts: [String] = []
        if let n = model.snapshotCount, n > 0 { parts.append(L("{0} Time Machine anlık görüntüsü", n)) }
        if model.installDataPresent { parts.append(L("yarım kalmış bir macOS güncellemesi")) }
        return parts.joined(separator: " · ") + ". Harici diskteki yedeklerine dokunulmaz."
    }
}

/// Look at a personal file before choosing it: open it, or show it in Finder.
struct RevealButtons: View {
    let url: URL
    let isMedia: Bool
    var body: some View {
        HStack(spacing: 2) {
            Button { Reveal.open(url) } label: {
                Image(systemName: isMedia ? "play.rectangle" : "eye")
                    .frame(width: 28, height: 28).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isMedia ? L("Aç ve izle") : L("Aç"))
            .accessibilityLabel(L("Dosyayı aç"))
            Button { Reveal.inFinder(url) } label: {
                Image(systemName: "folder").frame(width: 28, height: 28).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L("Finder'da göster"))
            .accessibilityLabel(L("Finder'da göster"))
        }
        .foregroundStyle(KColor.textMuted)
        .padding(.trailing, 6)
    }
}
