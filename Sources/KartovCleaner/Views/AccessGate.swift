import SwiftUI
import KartovCore

/// Shown instead of the app until Full Disk Access is on. Without it most caches can't be read,
/// so Kartov would report far less than there really is.
struct AccessGate: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 30)
            ZStack(alignment: .bottomTrailing) {
                KartovLogo(size: 96)
                Image(systemName: "lock.shield.fill").font(.system(size: 26)).foregroundStyle(KColor.accent)
                    .padding(6).background(Circle().fill(KColor.bg))
            }
            VStack(spacing: 8) {
                Text(L("Kartov Cleaner'a Tam Disk Erişimi ver")).font(.system(size: 26, weight: .bold))
                Text(L("Mac'indeki önbellekleri eksiksiz bulabilmesi için Kartov'un bu izne ihtiyacı var. Kartov dosyalarını yalnızca okur; sen onaylamadan hiçbir şey silmez."))
                    .font(.system(size: 14)).foregroundStyle(KColor.textMuted)
                    .multilineTextAlignment(.center).frame(maxWidth: 500)
            }

            VStack(alignment: .leading, spacing: 0) {
                step(1, L("Sistem Ayarları'nı aç"), L("Aşağıdaki düğme seni doğrudan Tam Disk Erişimi sayfasına götürür."))
                Divider().overlay(KColor.border)
                step(2, L("Kartov Cleaner'ı aç"), L("Listede Kartov Cleaner'ın yanındaki anahtarı aç. Listede yoksa + düğmesine bas ve Uygulamalar klasöründen seç."))
                Divider().overlay(KColor.border)
                step(3, L("Kartov'a geri dön"), L("İzin verince bu ekran kendiliğinden kapanır. Kapanmazsa Yeniden başlat düğmesine bas."))
            }
            .kCard(padding: 6, radius: 16)
            .frame(maxWidth: 560)

            HStack(spacing: 10) {
                Button { Permissions.openFullDiskAccessSettings() } label: {
                    Label(L("Sistem Ayarları'nı aç"), systemImage: "gearshape.fill")
                }
                .buttonStyle(PrimaryButtonStyle(large: true))
                .keyboardShortcut(.defaultAction)
                Button(L("Uygulamayı Finder'da göster")) { Finder.reveal(Bundle.main.bundlePath) }
                    .buttonStyle(SecondaryButtonStyle(large: true))
                Button(L("Yeniden başlat")) { Permissions.relaunch() }
                    .buttonStyle(SecondaryButtonStyle(large: true))
            }

            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(L("İzin bekleniyor…")).font(.system(size: 12)).foregroundStyle(KColor.textMuted)
            }
            Spacer(minLength: 30)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { model.refreshPermissions() }
    }

    private func step(_ n: Int, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(n)")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(KColor.accent)
                .frame(width: 28, height: 28)
                .background(Circle().fill(KColor.accent.opacity(0.14)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(text).font(.system(size: 12)).foregroundStyle(KColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
    }
}
