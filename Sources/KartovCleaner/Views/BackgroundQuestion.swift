import SwiftUI
import KartovCore

/// Asked once, after the tour: should Kartov keep running in the background?
struct BackgroundQuestion: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    KartovLogo(size: 48)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L("Kartov Cleaner arka planda çalışsın mı?")).font(.system(size: 20, weight: .bold))
                        Text(L("Pencereyi kapatınca da açık kalır, Mac açılınca kendiliğinden başlar."))
                            .font(.system(size: 13)).foregroundStyle(KColor.textMuted)
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    point("clock.badge.checkmark", L("Otomatik bakım, seçtiğin saatte kendiliğinden yapılır."))
                    point("globe.europe.africa.fill", L("Menü çubuğunda küçük bir dünya simgesi durur; tek tıkla temizlik ya da optimizasyon yapabilirsin."))
                    point("bolt.slash", L("Arka planda neredeyse hiç pil ve bellek harcamaz."))
                }
                HStack {
                    Text(L("Simgeye tıklayınca")).font(.system(size: 13)).foregroundStyle(KColor.textMuted)
                    Spacer()
                    Picker("", selection: Binding(get: { model.menuBarAction }, set: { model.menuBarAction = $0 })) {
                        ForEach(MenuBarAction.allCases) { a in Text(a.title).tag(a) }
                    }
                    .labelsHidden().fixedSize()
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(KColor.surface2))
                HStack(spacing: 10) {
                    Spacer()
                    Button(L("Hayır, sadece açtığımda")) { model.chooseBackground(false) }
                        .buttonStyle(SecondaryButtonStyle())
                    Button(L("Evet, arka planda çalışsın")) { model.chooseBackground(true) }
                        .buttonStyle(PrimaryButtonStyle())
                        .keyboardShortcut(.defaultAction)
                }
                Text(L("Bunu istediğin zaman Bakım sekmesinden değiştirebilirsin."))
                    .font(.system(size: 11)).foregroundStyle(KColor.textMuted)
            }
            .padding(24)
            .frame(width: 520)
            .kCard(padding: 0, radius: 20)
            .fixedSize()
        }
    }

    private func point(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(KColor.accent).frame(width: 20)
            Text(text).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
        }
    }
}
