import SwiftUI
import AppKit
import KartovCore

/// Shown when "Temizle" is pressed while some programs that hold chosen caches are open:
/// how much is held back, and a choice to close them all or clean the rest.
struct LockedCleanSheet: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let apps = model.lockedApps
        let held = model.lockedSelectedBytes
        let now = model.selectedBytes
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
                .onTapGesture { if !model.quittingForClean { model.showLockedSheet = false } }
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    Image(systemName: "lock.app.dashed")
                        .font(.system(size: 22, weight: .semibold)).foregroundStyle(KColor.warning)
                        .frame(width: 48, height: 48)
                        .background(RoundedRectangle(cornerRadius: 12).fill(KColor.warning.opacity(0.14)))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L("{0} program açık", apps.count)).font(.system(size: 20, weight: .bold))
                        Text(L("Açıkken önbelleklerini kullandıkları için {0} temizlenemiyor.", KBytes.format(held)))
                            .font(.system(size: 13)).foregroundStyle(KColor.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(spacing: 6) {
                    ForEach(apps) { a in
                        HStack(spacing: 10) {
                            if let icon = a.icon { Image(nsImage: icon).resizable().frame(width: 24, height: 24) }
                            Text(a.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                            Spacer()
                            Text(KBytes.format(a.bytes)).font(.system(size: 12, weight: .semibold).monospacedDigit())
                                .foregroundStyle(KColor.warning)
                        }
                        .padding(.horizontal, 12).frame(height: 38)
                        .background(RoundedRectangle(cornerRadius: 10).fill(KColor.surface2.opacity(0.6)))
                    }
                }

                HStack(spacing: 12) {
                    Summary(label: L("Kapatırsan"), value: KBytes.format(now + held), tint: KColor.success)
                    Summary(label: L("Kapatmadan"), value: KBytes.format(now), tint: KColor.text)
                }

                if model.quittingForClean {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(L("Programlar kapatılıyor… Kaydedilmemiş bir işin varsa program önce sorar."))
                            .font(.system(size: 12)).foregroundStyle(KColor.textMuted)
                    }
                } else {
                    Text(L("Programlar kapanmadan önce kaydedilmemiş işin varsa sorar. Temizlikten sonra yeniden açabilirsin."))
                        .font(.system(size: 11)).foregroundStyle(KColor.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 10) {
                    Button(L("Vazgeç")) { model.showLockedSheet = false }
                        .buttonStyle(.plain).font(.system(size: 13)).foregroundStyle(KColor.textMuted)
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button(now > 0 ? L("Kapatmadan {0} temizle", KBytes.format(now)) : L("Kapatmadan temizlenecek bir şey yok")) {
                        model.proceedClean()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(now == 0 || model.quittingForClean)
                    Button(L("Hepsini kapat ve temizle")) { model.quitLockedAppsAndClean() }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(model.quittingForClean)
                }
            }
            .padding(22)
            .frame(width: 540)
            .background(RoundedRectangle(cornerRadius: 22).fill(KColor.surface))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(KColor.border))
            .shadow(color: .black.opacity(0.4), radius: 24, y: 10)
        }
        .transition(.opacity)
    }

    private struct Summary: View {
        let label: String
        let value: String
        let tint: Color
        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 11)).foregroundStyle(KColor.textMuted)
                Text(value).font(.system(size: 20, weight: .bold).monospacedDigit()).foregroundStyle(tint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(KColor.surface2.opacity(0.6)))
        }
    }
}
