import SwiftUI
import AppKit
import KartovCore

/// "Projeler": caches that After Effects, Premiere Pro and Media Encoder left next to project
/// files, grouped by project, with the projects nobody has touched for a while pointed out.
struct ProjectsView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var caches = ProjectCaches.shared

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: L("Projeler")) {
                if caches.scanning {
                    Button(L("Durdur")) { caches.cancel() }.buttonStyle(SecondaryButtonStyle())
                } else if caches.scanDate != nil {
                    Button { caches.addFolder() } label: { Label(L("Klasör ekle"), systemImage: "folder.badge.plus") }
                        .buttonStyle(SecondaryButtonStyle())
                    Button(L("Yeniden tara")) { caches.scan() }.buttonStyle(SecondaryButtonStyle())
                }
            }
            if caches.scanning {
                scanning
            } else if caches.scanDate == nil {
                intro
            } else {
                results
            }
        }
        .confirmationDialog(L("{0} projenin önbelleği çöp kutusuna taşınsın mı?", caches.selectedProjectCount),
                            isPresented: $caches.showConfirm, titleVisibility: .visible) {
            Button(L("Çöp kutusuna taşı · {0}", KBytes.format(caches.selectedBytes)), role: .destructive) {
                caches.trashSelection(model: model)
            }
            Button(L("Vazgeç"), role: .cancel) {}
        } message: {
            Text(confirmText)
        }
    }

    private var confirmText: String {
        var s = L("Proje dosyalarına, medyana ve render çıktılarına dokunulmaz. Seçtiklerin kalıcı olarak silinmez; çöp kutusuna gider ve Geçmiş › Geri al ile geri gelir.")
        let open = caches.openEditors
        if !open.isEmpty {
            s += L("\n\n{0} şu an açık. Açık olan projenin önbelleğini taşımadan önce programı kapatman iyi olur.", open.joined(separator: ", "))
        }
        return s
    }

    // MARK: states

    private var intro: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(KColor.accent.opacity(0.12)).frame(width: 120, height: 120)
                Image(systemName: "film.stack.fill").font(.system(size: 46)).foregroundStyle(KColor.accent)
            }
            Text(L("Biten projeler ne kadar yer tutuyor?")).font(.system(size: 26, weight: .bold))
            Text(L("After Effects ve Premiere Pro projelerinin yanında biriken önizleme renderlarını, medya önbelleklerini, otomatik kayıtları ve proxy'leri proje proje gösterir. Uzun süredir dokunmadığın projeleri öne çıkarır. Tarama hiçbir şeyi silmez."))
                .font(.system(size: 14)).foregroundStyle(KColor.textMuted)
                .multilineTextAlignment(.center).frame(maxWidth: 520)
            Button { caches.scan() } label: { Label(L("Projeleri tara"), systemImage: "film.stack") }
                .buttonStyle(PrimaryButtonStyle(large: true))
                .keyboardShortcut(.defaultAction)
            rootsLine
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var rootsText: String {
        let base = L("Bakılan yerler: Masaüstü, Belgeler, İndirilenler, Filmler")
        if caches.extraRoots.isEmpty { return base }
        let extra = caches.extraRoots.map { abbreviate($0) }.joined(separator: ", ")
        return base + " + " + extra
    }

    private var rootsLine: some View {
        VStack(spacing: 8) {
            Text(rootsText)
                .font(.system(size: 12)).foregroundStyle(KColor.textMuted)
                .multilineTextAlignment(.center).frame(maxWidth: 520)
            Button { caches.addFolder() } label: {
                Label(L("Harici disk ya da başka bir klasör ekle"), systemImage: "folder.badge.plus").font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain).foregroundStyle(KColor.accentSoft)
        }
    }

    private var scanning: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large)
            Text(L("Projeler aranıyor…")).font(.system(size: 20, weight: .semibold))
            Text(abbreviate(caches.scanPath)).font(.system(size: 11, design: .monospaced))
                .foregroundStyle(KColor.textMuted).lineLimit(1).truncationMode(.middle).frame(maxWidth: 460)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var results: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    summary
                    if !caches.extraRoots.isEmpty { extraRoots }
                    if caches.projects.isEmpty {
                        empty
                    } else {
                        filterBar
                        LazyVStack(spacing: 2) {
                            let list = caches.visible
                            if list.isEmpty {
                                Text(L("{0} gündür dokunulmayan proje yok.", caches.idleDays))
                                    .font(.system(size: 13)).foregroundStyle(KColor.textMuted).padding(.vertical, 28)
                                    .frame(maxWidth: .infinity)
                            }
                            ForEach(list) { p in ProjectRow(project: p) }
                        }
                        .kCard(padding: 6, radius: 16)
                    }
                }
                .padding(.horizontal, 24).padding(.vertical, 18)
                .frame(maxWidth: 1080, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            if !caches.selected.isEmpty || caches.message != nil { bottomBar }
        }
    }

    private var summary: some View {
        let idle = caches.idleProjects
        return HStack(alignment: .center, spacing: 18) {
            Image(systemName: "film.stack.fill").font(.system(size: 24, weight: .semibold)).foregroundStyle(KColor.accent)
                .frame(width: 54, height: 54)
                .background(Circle().fill(KColor.accent.opacity(0.14)))
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(KBytes.format(caches.totalBytes)).font(.system(size: 26, weight: .bold).monospacedDigit())
                    Text(L("{0} projede önbellek ve yedek", caches.projects.count))
                        .font(.system(size: 13)).foregroundStyle(KColor.textMuted)
                }
                Text(idle.isEmpty
                     ? L("{0} gündür dokunmadığın, temizlenebilir önbelleği olan proje yok.", caches.idleDays)
                     : L("{0} projeye {1} gündür dokunmadın; kendiliğinden yeniden oluşan önbellekleri {2} tutuyor.",
                         idle.count, caches.idleDays, KBytes.format(caches.idleBytes)))
                    .font(.system(size: 13)).foregroundStyle(idle.isEmpty ? KColor.textMuted : KColor.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if !idle.isEmpty {
                Button(L("Bunları seç")) { caches.selectIdle() }.buttonStyle(PrimaryButtonStyle())
            }
        }
        .kCard(padding: 18)
    }

    private var extraRoots: some View {
        HStack(spacing: 6) {
            Text(L("Eklenen klasörler")).font(.system(size: 12)).foregroundStyle(KColor.textMuted)
            ForEach(caches.extraRoots, id: \.self) { path in
                HStack(spacing: 6) {
                    Image(systemName: "folder").font(.system(size: 11))
                    Text(abbreviate(path)).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                    Button { caches.removeRoot(path) } label: {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).frame(width: 16, height: 16).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(L("Listeden çıkar"))
                }
                .foregroundStyle(KColor.textMuted)
                .padding(.leading, 10).padding(.trailing, 6).frame(height: 26)
                .background(Capsule().fill(KColor.surface2))
            }
            Spacer(minLength: 0)
        }
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 34)).foregroundStyle(KColor.success)
            Text(L("Projelerinin yanında birikmiş önbellek yok.")).font(.system(size: 15, weight: .semibold))
            Text(L("Projelerin başka bir diskteyse o klasörü ekleyip yeniden tarayabilirsin."))
                .font(.system(size: 12)).foregroundStyle(KColor.textMuted)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
        .kCard(padding: 18)
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            chip(L("Tümü"), count: caches.projects.count, on: !caches.onlyIdle) { caches.onlyIdle = false }
            chip(L("Dokunulmayanlar"), count: caches.projects.filter { caches.isIdle($0) }.count, on: caches.onlyIdle) { caches.onlyIdle = true }
            Spacer()
            Text(L("Dokunulmuyor sayılsın:")).font(.system(size: 12)).foregroundStyle(KColor.textMuted)
            Picker("", selection: Binding(get: { caches.idleDays }, set: { caches.idleDays = $0 })) {
                ForEach(ProjectCaches.idleChoices, id: \.self) { d in Text(L("{0}+ gün", d)).tag(d) }
            }
            .labelsHidden().fixedSize()
        }
    }

    private func chip(_ title: String, count: Int, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 12, weight: on ? .semibold : .regular))
                Text("\(count)").font(.system(size: 11).monospacedDigit()).foregroundStyle(KColor.textMuted)
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
            if caches.selected.isEmpty, let m = caches.message {
                Label(m, systemImage: "checkmark.circle.fill").font(.system(size: 12)).foregroundStyle(KColor.success)
                Spacer()
                Button(L("Geçmiş'e git")) { model.section = .history }.buttonStyle(SecondaryButtonStyle())
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("{0} proje · {1}", caches.selectedProjectCount, KBytes.format(caches.selectedBytes)))
                        .font(.system(size: 14, weight: .semibold).monospacedDigit())
                    Text(L("Çöp kutusuna gider, geri alınabilir.")).font(.system(size: 11)).foregroundStyle(KColor.textMuted)
                }
                Spacer()
                Button(L("Seçimi kaldır")) { caches.clearSelection() }.buttonStyle(SecondaryButtonStyle())
                Button(caches.cleaning ? L("Taşınıyor…") : L("Çöp kutusuna taşı")) { caches.showConfirm = true }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(caches.cleaning)
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 12)
        .background(KColor.chrome)
        .overlay(alignment: .top) { Rectangle().fill(KColor.border.opacity(0.6)).frame(height: 1) }
    }
}

/// One project: tick, name, when it was last saved, size; opens to its cache kinds.
struct ProjectRow: View {
    @ObservedObject private var caches = ProjectCaches.shared
    let project: ProjectInfo

    var body: some View {
        let open = caches.expanded.contains(project.id)
        let tick = caches.tick(of: project)
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button { caches.toggle(project) } label: {
                    Image(systemName: tick == .all ? "checkmark.circle.fill" : (tick == .some ? "minus.circle.fill" : "circle"))
                        .font(.system(size: 15))
                        .foregroundStyle(tick == .none ? KColor.textMuted : KColor.accent)
                        .frame(width: 28, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L("Kendiliğinden yeniden oluşan önbellekleri seç"))
                .accessibilityLabel("\(project.name), \(tick == .none ? L("seçili değil") : L("seçili"))")

                Button { caches.toggleExpanded(project) } label: {
                    HStack(spacing: 10) {
                        HStack(spacing: -6) {
                            ForEach(project.apps, id: \.self) { app in
                                ProjectAppIcon(app: app).frame(width: 26, height: 26)
                            }
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 8) {
                                Text(project.name).font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.middle)
                                if caches.isIdle(project) {
                                    Text(L("Dokunulmuyor")).font(.system(size: 10, weight: .semibold))
                                        .padding(.horizontal, 7).padding(.vertical, 2)
                                        .background(Capsule().fill(KColor.heat.opacity(0.16)))
                                        .foregroundStyle(KColor.heatSoft)
                                }
                            }
                            Text(subtitle).font(.system(size: 11)).foregroundStyle(KColor.textMuted).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer(minLength: 12)
                        Text(KBytes.format(project.bytes)).font(.system(size: 13, weight: .semibold).monospacedDigit())
                            .frame(minWidth: 70, alignment: .trailing)
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(KColor.textMuted)
                            .rotationEffect(.degrees(open ? 90 : 0))
                    }
                    .frame(height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button { Reveal.inFinder(project.folder) } label: {
                    Image(systemName: "folder").frame(width: 28, height: 28).contentShape(Rectangle())
                }
                .buttonStyle(.plain).foregroundStyle(KColor.textMuted)
                .help(L("Finder'da göster"))
                .accessibilityLabel(L("Finder'da göster"))
            }
            .padding(.horizontal, 6)
            .background(RoundedRectangle(cornerRadius: 9).fill(tick == .none ? Color.clear : KColor.accent.opacity(0.10)))

            if open {
                VStack(spacing: 0) {
                    ForEach(caches.parts(of: project)) { part in ProjectPartRow(part: part) }
                }
                .padding(.leading, 34).padding(.bottom, 6)
            }
        }
        .animation(KMotion.fast, value: open)
    }

    private var subtitle: String {
        let where_ = abbreviate(project.folder.path)
        let file = project.projectFiles.count == 1 ? project.projectFiles[0] : L("{0} proje dosyası", project.projectFiles.count)
        if let d = project.lastModified { return L("{0} · son kayıt {1} · {2}", file, relativeDay(d), where_) }
        return "\(file) · \(where_)"
    }
}

struct ProjectPartRow: View {
    @ObservedObject private var caches = ProjectCaches.shared
    let part: ProjectPart

    var body: some View {
        let on = caches.selected.contains(part.id)
        Button { caches.toggle(part) } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.system(size: 14))
                    .foregroundStyle(on ? KColor.accent : KColor.textMuted).frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(part.kind.title).font(.system(size: 12, weight: .semibold))
                        Text(part.kind.regenerable ? L("Kendiliğinden yeniden oluşur") : L("Dikkatli seç"))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(part.kind.regenerable ? KColor.success : KColor.warning)
                    }
                    Text(part.kind.detail).font(.system(size: 11)).foregroundStyle(KColor.textMuted)
                        .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 12)
                Text(KBytes.format(part.bytes)).font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .frame(minWidth: 70, alignment: .trailing)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 9).fill(KColor.surface2.opacity(on ? 0.9 : 0.4)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2).padding(.trailing, 40)
        .accessibilityLabel("\(part.kind.title), \(KBytes.format(part.bytes)), \(on ? L("seçili") : L("seçili değil"))")
    }
}

/// The program's own icon when it is installed (Premiere Pro's bundle id carries its version),
/// otherwise its two letters.
struct ProjectAppIcon: View {
    let app: ProjectApp

    private static var cache: [ProjectApp: NSImage] = [:]
    private static var missing: Set<ProjectApp> = []

    private static func icon(_ app: ProjectApp) -> NSImage? {
        if let i = cache[app] { return i }
        if missing.contains(app) { return nil }
        var ids = [app.bundleID]
        ids += (20...40).reversed().map { "\(app.bundleID).\($0)" }
        for id in ids {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                let i = NSWorkspace.shared.icon(forFile: url.path)
                cache[app] = i
                return i
            }
        }
        missing.insert(app)
        return nil
    }

    var body: some View {
        if let image = Self.icon(app) {
            Image(nsImage: image).resizable().interpolation(.high)
        } else {
            RoundedRectangle(cornerRadius: 6).fill(KColor.accent.opacity(0.18))
                .overlay(Text(app == .afterEffects ? "Ae" : "Pr").font(.system(size: 11, weight: .bold))
                    .foregroundStyle(KColor.accentSoft))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(KColor.accent.opacity(0.4)))
                .padding(1)
        }
    }
}
