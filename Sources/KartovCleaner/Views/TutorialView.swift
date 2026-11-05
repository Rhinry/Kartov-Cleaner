import SwiftUI
import KartovCore

/// The guided tour: each step opens the real tab behind it, lights up its tab at the top,
/// and explains it in a small card at the bottom. The app stays visible the whole time.
struct TourStep {
    let section: AppSection
    let title: String
    let text: String
    let symbol: String
    let gradient: LinearGradient
}

enum Tour {
    static let steps: [TourStep] = [
        TourStep(section: .dashboard, title: L("Kartov Cleaner'a hoş geldin"),
                 text: L("Bu dünya Mac'inin aynası. Önbellek ve gereksiz dosya biriktikçe kirlenir, temizledikçe yeniden maviye döner. Kısa bir turla bütün sekmeleri gezelim."),
                 symbol: "globe.europe.africa.fill", gradient: KGradient.accent),
        TourStep(section: .overview, title: L("Genel bakış"),
                 text: L("Kartlarda her şey bir arada: temizlik, tam tarama, sistem durumu, analiz ve otomatik bakım. Sistem kartındaki Optimize et belleği tek tıkla rahatlatır, Aç ise ayrıntıları gösterir."),
                 symbol: "square.grid.2x2.fill", gradient: KGradient.violet),
        TourStep(section: .scan, title: L("Tarama"),
                 text: L("Tarama hiçbir şeyi silmez, yalnızca bakar. Hangi bölümlere bakıldığı ve ne kadar yer bulunduğu burada canlı görünür."),
                 symbol: "magnifyingglass", gradient: KGradient.accent),
        TourStep(section: .results, title: L("Bulunanlar: seç ve temizle"),
                 text: L("Bulunanlar program program listelenir. Her satırda Temizle ya da Koru'yu seçersin. Açık bir program varsa Kapat düğmesi çıkar. Tarama geçmişi silinmeden önce sorulur."),
                 symbol: "square.stack.3d.up.fill", gradient: KGradient.heat),
        TourStep(section: .fullScan, title: L("Tam tarama"),
                 text: L("Programlarını, videolarını, görsellerini ve belgelerini boyutlarıyla gösterir. Sırala, Tümünü seç ya da Shift ile aralık seç; istemediklerini kaldır. Hepsi çöp kutusuna gider."),
                 symbol: "chart.pie.fill", gradient: KGradient.violet),
        TourStep(section: .system, title: L("Sistem durumu"),
                 text: L("İşlemci, bellek, disk ve pil anlık olarak burada. Belleği rahatlatabilir, çok bellek kullanan programları kapatabilir, açılışta çalışanları azaltabilirsin."),
                 symbol: "speedometer", gradient: KGradient.success),
        TourStep(section: .analysis, title: L("Analiz"),
                 text: L("Hangi program açık, ne kadar bellek, işlemci ve disk kullanıyor; en çok hangilerini kullanıyorsun, hangileri en çok yer kaplıyor, hangilerini aylardır açmadın. Kapatabilir, zorla kapatabilir ya da kaldırabilirsin."),
                 symbol: "chart.bar.xaxis", gradient: KGradient.violet),
        TourStep(section: .maintenance, title: L("Otomatik bakım"),
                 text: L("Kartov seçtiğin gün ve saatte önbellekleri kendisi temizler. Neleri temizleyeceğini, ne kadar birikince çalışacağını ve şarjdayken mi çalışacağını sen seçersin. Arka planda çalışmasını seçersen menü çubuğundaki küçük dünyaya tıklayıp tek tıkla temizlik ya da optimizasyon yapabilirsin."),
                 symbol: "clock.badge.checkmark", gradient: KGradient.accent),
        TourStep(section: .history, title: L("Geçmiş: her şey geri alınabilir"),
                 text: L("Yapılan her temizlik burada durur. Çöp kutusuna gidenleri Geri al ile tek tıkla yerine koyarsın."),
                 symbol: "arrow.uturn.backward.circle.fill", gradient: KGradient.warning),
        TourStep(section: .dashboard, title: L("Son bir rica: Tam Disk Erişimi"),
                 text: L("Kartov'un Mac'indeki bütün önbellekleri bulabilmesi için Tam Disk Erişimi gerekiyor. Dosyalarını yalnızca okur; sen onaylamadan hiçbir şey silmez. Sistem Ayarları'nda Kartov Cleaner'ın anahtarını açman yeterli."),
                 symbol: "lock.shield.fill", gradient: KGradient.accent)
    ]
}

struct TutorialView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let i = min(model.tutorialStep, Tour.steps.count - 1)
        let step = Tour.steps[i]
        ZStack(alignment: .bottom) {
            // Light dim so the tab behind stays readable.
            Color.black.opacity(0.28).ignoresSafeArea()
                .allowsHitTesting(true)
            card(step, index: i)
                .padding(.bottom, 26)
        }
        .transition(.opacity)
    }

    private func card(_ step: TourStep, index i: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Group {
                    if i == 0 {
                        KartovLogo(size: 52)
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14).fill(step.gradient).frame(width: 52, height: 52)
                            Image(systemName: step.symbol).font(.system(size: 22, weight: .semibold)).foregroundStyle(.white)
                        }
                    }
                }
                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(i + 1) / \(Tour.steps.count) · \(step.section.title)")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(KColor.textMuted)
                    Text(step.title).font(.system(size: 20, weight: .bold))
                    Text(step.text).font(.system(size: 13)).foregroundStyle(KColor.textMuted)
                        .lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button { model.finishTutorial() } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(KColor.textMuted)
                        .frame(width: 24, height: 24).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel(L("Turu kapat"))
            }

            extras(i)

            HStack {
                dots(i)
                Spacer()
                if i > 0 {
                    Button(L("Geri")) { model.goToTourStep(i - 1) }.buttonStyle(SecondaryButtonStyle())
                }
                if i < Tour.steps.count - 1 {
                    Button(L("İleri")) { model.goToTourStep(i + 1) }
                        .buttonStyle(PrimaryButtonStyle())
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button {
                        model.finishTutorial()
                        model.startScan()
                    } label: {
                        Label(model.hasFullDiskAccess ? L("Bitir ve tara") : L("İzinsiz devam et"), systemImage: "magnifyingglass")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 600)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 22).fill(KGradient.card)
            }
        )
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(KGradient.rim))
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
        .animation(KMotion.base, value: i)
    }

    @ViewBuilder private func extras(_ i: Int) -> some View {
        switch Tour.steps[i].section {
        case .maintenance:
            Toggle(isOn: Binding(get: { model.autoEnabled }, set: { model.autoEnabled = $0 })) {
                Text(L("Haftada bir otomatik bakım yap")).font(.system(size: 13, weight: .semibold))
            }
            .toggleStyle(.switch)
        case .dashboard where i == Tour.steps.count - 1:
            VStack(alignment: .leading, spacing: 10) {
                if model.hasFullDiskAccess {
                    Label(L("Tam Disk Erişimi verildi. Kartov tam performansla çalışacak."), systemImage: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(KColor.success)
                } else {
                    HStack(spacing: 10) {
                        Button { Permissions.openFullDiskAccessSettings() } label: {
                            Label(L("Sistem Ayarları'nı aç"), systemImage: "gearshape.fill")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        Button(L("Yeniden başlat")) { Permissions.relaunch() }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                    Text(L("Listede Kartov Cleaner yoksa + ile Uygulamalar klasöründen ekle. İzin verince burası kendiliğinden yeşile döner; dönmezse Yeniden başlat düğmesine bas."))
                        .font(.system(size: 11)).foregroundStyle(KColor.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(KColor.warning)
                        Text(L("İzin vermeden de devam edebilirsin. Ama o zaman Kartov tam performansla çalışmaz: Safari, Mail ve bazı uygulamaların klasörlerine bakamaz, bulduğu yer gerçekte olandan az olur."))
                            .font(.system(size: 12)).foregroundStyle(KColor.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(KColor.warning.opacity(0.08)))
                }
            }
        default:
            EmptyView()
        }
    }

    private func dots(_ current: Int) -> some View {
        HStack(spacing: 5) {
            ForEach(0..<Tour.steps.count, id: \.self) { j in
                Capsule().fill(j == current ? AnyShapeStyle(KGradient.accent) : AnyShapeStyle(KColor.border))
                    .frame(width: j == current ? 18 : 6, height: 6)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(L("Adım {0} / {1}", current + 1, Tour.steps.count))
    }
}
