import SwiftUI
import KartovCore

/// Thin strip under the tabs when a new version is out.
struct UpdateBanner: View {
    @ObservedObject var updater = Updater.shared
    var body: some View {
        if let r = updater.release, updater.phase == .available, !updater.bannerDismissed {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.fill").font(.system(size: 18)).foregroundStyle(KColor.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("Kartov Cleaner {0} hazır", r.version)).font(.system(size: 13, weight: .semibold))
                    Text(L("Şu an {0} kullanıyorsun.", updater.currentVersion))
                        .font(.system(size: 12)).foregroundStyle(KColor.textMuted)
                }
                Spacer()
                Button(L("Sonra")) { updater.later() }.buttonStyle(SecondaryButtonStyle())
                Button(L("Yenilikler ve güncelle")) { updater.showSheet = true }.buttonStyle(PrimaryButtonStyle())
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
            .background(KColor.accent.opacity(0.08))
            .overlay(alignment: .bottom) { Rectangle().fill(KColor.border).frame(height: 1) }
        }
    }
}

/// The update window: what's new, then download and install with progress.
struct UpdateSheet: View {
    @ObservedObject var updater = Updater.shared

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
                .onTapGesture { if !busy { updater.showSheet = false } }
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    KartovLogo(size: 52)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).font(.system(size: 20, weight: .bold))
                        Text(L("Şu an {0} kullanıyorsun.", updater.currentVersion))
                            .font(.system(size: 12)).foregroundStyle(KColor.textMuted)
                    }
                    Spacer()
                }

                if let r = updater.release {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("Yenilikler")).font(.system(size: 12, weight: .semibold)).foregroundStyle(KColor.textMuted)
                        ScrollView {
                            Text(r.notes.isEmpty ? AttributedString(L("Bu sürüm için not yazılmamış."))
                                 : ((try? AttributedString(markdown: r.notes, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                                    ?? AttributedString(r.notes)))
                                .font(.system(size: 13))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(height: 170)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 10).fill(KColor.surface2))
                        if r.size > 0 {
                            Text(L("İndirme boyutu: {0}", KBytes.format(r.size)))
                                .font(.system(size: 11)).foregroundStyle(KColor.textMuted)
                        }
                    }
                }

                status

                HStack(spacing: 10) {
                    if updater.release != nil, !busy {
                        Button(L("Bu sürümü atla")) { updater.skipThisVersion() }
                            .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(KColor.textMuted)
                    }
                    Spacer()
                    if case .downloading = updater.phase {
                        Button(L("Vazgeç")) { updater.cancelDownload() }.buttonStyle(SecondaryButtonStyle())
                    } else if !busy {
                        Button(updater.release == nil ? L("Kapat") : L("Sonra")) { updater.later() }
                            .buttonStyle(SecondaryButtonStyle())
                        if updater.release != nil {
                            Button(L("Şimdi güncelle")) { updater.install() }
                                .buttonStyle(PrimaryButtonStyle())
                                .keyboardShortcut(.defaultAction)
                        }
                    }
                }
                Text(L("Güncelleme GitHub'dan indirilir, imzası kontrol edilir, Kartov kapanıp yeni sürümle yeniden açılır. Ayarların ve geçmişin korunur."))
                    .font(.system(size: 11)).foregroundStyle(KColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)
            .frame(width: 520)
            .kCard(padding: 0, radius: 20)
            .fixedSize()
        }
    }

    private var busy: Bool {
        switch updater.phase {
        case .downloading, .installing: return true
        default: return false
        }
    }

    private var title: String {
        if let r = updater.release { return L("Kartov Cleaner {0} hazır", r.version) }
        return L("Kartov Cleaner güncel")
    }

    @ViewBuilder private var status: some View {
        switch updater.phase {
        case .downloading(let f):
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: f).tint(KColor.accent)
                Text(L("İndiriliyor… %{0}", Int(f * 100))).font(.system(size: 12)).foregroundStyle(KColor.textMuted)
            }
        case .installing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(L("Doğrulanıyor ve kuruluyor; Kartov birazdan yeniden açılacak…")).font(.system(size: 12))
            }
        case .failed(let m):
            Label(m, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12)).foregroundStyle(KColor.heat)
                .fixedSize(horizontal: false, vertical: true)
        default:
            EmptyView()
        }
    }
}

/// Settings card: version, automatic checks, check now.
struct UpdateSettingsCard: View {
    @ObservedObject var updater = Updater.shared
    var body: some View {
        SettingsCard(title: L("Güncellemeler"), symbol: "arrow.down.circle") {
            SettingsRow(L("Yüklü sürüm"), note: updater.repo.map { L("Kaynak: github.com/{0}", $0) }
                        ?? L("Güncelleme deposu ayarlanmamış.")) {
                Text(updater.currentVersion).font(.system(size: 13, weight: .semibold).monospacedDigit())
            }
            SettingsRow(L("Güncellemeleri kendiliğinden denetle"), note: L("Günde bir kez bakar; yeni sürüm varsa haber verir, sen onaylamadan kurmaz.")) {
                Toggle("", isOn: Binding(get: { updater.autoCheck }, set: { updater.autoCheck = $0 })).labelsHidden()
            }
            SettingsRow(L("Şimdi denetle"), note: statusNote) {
                if updater.phase == .checking {
                    ProgressView().controlSize(.small)
                } else if updater.release != nil {
                    Button(L("Güncelle")) { updater.showSheet = true }.buttonStyle(PrimaryButtonStyle())
                } else {
                    Button(L("Denetle")) { Task { await updater.check(userInitiated: true) } }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(updater.repo == nil)
                }
            }
        }
    }

    private var statusNote: String? {
        switch updater.phase {
        case .upToDate: return L("En son sürümü kullanıyorsun.")
        case .available: return updater.release.map { L("{0} sürümü hazır.", $0.version) }
        case .failed(let m): return m
        default: return updater.lastCheck.map { L("Son denetim: {0}", relativeDay($0)) }
        }
    }
}
