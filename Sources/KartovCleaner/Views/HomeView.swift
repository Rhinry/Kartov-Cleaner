import SwiftUI
import KartovCore

func homeGreeting(_ date: Date = Date()) -> String {
    switch Calendar.current.component(.hour, from: date) {
    case 5..<12: return L("Günaydın")
    case 12..<18: return L("İyi günler")
    default: return L("İyi akşamlar")
    }
}

/// The home screen: only the globe. Its dirt shows how much has piled up; one number, one button.
struct HomeView: View {
    @EnvironmentObject var model: AppModel

    private var scanning: Bool { model.phase == .scanning }
    private var bytes: Int64 { scanning ? model.foundBytes : model.selectedBytes }
    private var never: Bool { model.lastScanDate == nil && model.items.isEmpty && !scanning }
    private var dirty: Bool { bytes >= 5_000_000_000 }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 10)
            Text(homeGreeting()).font(.system(size: 15, weight: .medium)).foregroundStyle(KColor.textMuted)
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [(dirty ? KColor.heat : KColor.accent).opacity(0.22), .clear],
                                         center: .center, startRadius: 40, endRadius: 260))
                    .frame(width: 520, height: 520)
                Globe(dirt: dirtLevel(bytes), speed: scanning ? 1.1 : 0.2, size: 210,
                      shine: !never && bytes == 0 ? 0.5 : 0)
                    .frame(width: 360, height: 360)
            }
            .frame(height: 380)
            .accessibilityLabel(mood)

            Text(figure)
                .font(.system(size: 54, weight: .bold).monospacedDigit())
                .foregroundStyle(figureColor)
            Text(mood).font(.system(size: 15)).foregroundStyle(KColor.textMuted)
                .multilineTextAlignment(.center).frame(maxWidth: 460)
                .padding(.top, 4)

            HStack(spacing: 10) { buttons }
                .padding(.top, 22)

            Spacer(minLength: 10)
            footer.padding(.bottom, 22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            // The globe can only show dirt once it knows how much there is: look right away (reading only).
            if never && !model.showTutorial && model.scanOnLaunch { model.startScan() }
        }
    }

    private var figure: String {
        if never { return L("Hazır") }
        return bytes > 0 ? KBytes.format(bytes) : L("Tertemiz")
    }

    private var figureColor: Color {
        if never { return KColor.text }
        if dirty { return KColor.heat }
        return bytes > 0 ? KColor.warning : KColor.success
    }

    private var mood: String {
        if scanning { return L("bulundu · Mac'ine bakılıyor…") }
        if never { return L("Dünyanın ne kadar kirlendiğine bakmak için tara. Tarama hiçbir şeyi silmez.") }
        if dirty { return L("Dünyan kirlenmiş. Bu kadar gereksiz dosya temizlenebilir.") }
        if bytes > 0 { return L("temizlenebilir") }
        return L("Dünyan temiz. Temizlenecek bir şey yok.")
    }

    @ViewBuilder private var buttons: some View {
        if scanning {
            Button(L("Taramayı izle")) { model.section = .scan }.buttonStyle(PrimaryButtonStyle(large: true))
            Button(L("Durdur")) { model.cancelScan() }.buttonStyle(SecondaryButtonStyle(large: true))
        } else if bytes > 0 {
            Button { model.requestClean() } label: { Label(L("Temizle"), systemImage: "sparkles") }
                .buttonStyle(PrimaryButtonStyle(large: true))
                .keyboardShortcut(.defaultAction)
            Button(L("Gözden geçir")) { model.section = .results }.buttonStyle(SecondaryButtonStyle(large: true))
        } else {
            Button { model.startScan() } label: { Label(never ? L("Tara") : L("Yeniden tara"), systemImage: "magnifyingglass") }
                .buttonStyle(PrimaryButtonStyle(large: true))
                .keyboardShortcut(.defaultAction)
        }
    }

    private var footer: some View {
        let d = DiskInfo.read()
        return HStack(spacing: 6) {
            Image(systemName: "internaldrive").foregroundStyle(KColor.textMuted)
            Text(L("{0} · {1} boş", d.name, KBytes.format(d.free)))
            Text("·").foregroundStyle(KColor.textMuted)
            Button(L("Genel bakış")) { model.section = .overview }.buttonStyle(.plain).foregroundStyle(KColor.accentSoft)
        }
        .font(.system(size: 12))
    }
}
