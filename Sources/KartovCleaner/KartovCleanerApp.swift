import SwiftUI
import KartovCore
import AppKit

@main
struct KartovCleanerApp: App {
    @StateObject private var model = AppModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // Run from Xcode or `swift run` without an app bundle, the process would otherwise
        // stay in the background with no Dock icon.
        NSApplication.shared.setActivationPolicy(.regular)
        DispatchQueue.main.async { NSApplication.shared.activate(ignoringOtherApps: true) }
    }

    var body: some Scene {
        WindowGroup("Kartov Cleaner", id: "main") {
            RootView()
                .environmentObject(model)
                .frame(minWidth: KLayout.windowMin.width, minHeight: KLayout.windowMin.height)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1260, height: 800)
        .commands {
            CommandGroup(after: .newItem) {
                Button(L("Tara")) { model.startScan() }
                    .keyboardShortcut("r", modifiers: [.command])
            }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        main
        .background(AppBackground())
        .foregroundStyle(KColor.text)
        .tint(KColor.accent)
        .environment(\.locale, I18n.locale)
        .overlay { CleanOverlay() }
        .overlay { if model.showTutorial { TutorialView() } }
        .overlay { if model.showBackgroundQuestion { BackgroundQuestion() } }
        .overlay { UpdateOverlay() }
        .animation(KMotion.base, value: model.cleanAnimationStart)
        .animation(KMotion.base, value: model.showTutorial)
        .animation(KMotion.base, value: model.hasFullDiskAccess)
        .animation(KMotion.base, value: model.askedBackground)
        .onAppear {
            klog("arayüz açıldı · \(model.rules.count) kural")
            let open = openWindow
            model.openMainWindow = { open(id: "main") }
        }
    }

    private var main: some View {
        VStack(spacing: 0) {
            TopBar()
            if !model.showTutorial { PermissionBanner(); UpdateBanner() }
            if let message = model.errorMessage {
                Text(message).foregroundStyle(KColor.danger).padding()
            }
            Group {
                switch model.section {
                case .dashboard: HomeView()
                case .overview: DashboardView()
                case .scan: ScanView()
                case .results: ResultsView()
                case .fullScan: FullScanView()
                case .system: SystemView()
                case .maintenance: MaintenanceView()
                case .history: HistoryView()
                case .settings: SettingsView()
                case .analysis: AnalysisView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .ignoresSafeArea(.container, edges: .top)
    }
}

/// The tabs shown in the top bar. "Temizlik" covers both the scan and its results.
enum TopTab: CaseIterable, Identifiable {
    case home, overview, clean, full, system, analysis, care, history
    var id: Self { self }
    var title: String {
        switch self {
        case .home: return L("Ana sayfa")
        case .overview: return L("Genel bakış")
        case .clean: return L("Temizlik")
        case .full: return L("Tam tarama")
        case .system: return L("Sistem")
        case .analysis: return L("Analiz")
        case .care: return L("Bakım")
        case .history: return L("Geçmiş")
        }
    }
    var symbol: String {
        switch self {
        case .home: return "globe.europe.africa.fill"
        case .overview: return "square.grid.2x2.fill"
        case .clean: return "sparkles"
        case .full: return "chart.pie.fill"
        case .system: return "speedometer"
        case .analysis: return "chart.bar.xaxis"
        case .care: return "clock.badge.checkmark"
        case .history: return "clock.arrow.circlepath"
        }
    }
    var sections: [AppSection] {
        switch self {
        case .home: return [.dashboard]
        case .overview: return [.overview]
        case .clean: return [.scan, .results]
        case .full: return [.fullScan]
        case .system: return [.system]
        case .analysis: return [.analysis]
        case .care: return [.maintenance]
        case .history: return [.history]
        }
    }
    static func of(_ s: AppSection) -> TopTab? { allCases.first { $0.sections.contains(s) } }
}

/// Pill tabs across the top of the window (the title bar is hidden; room is left for the window buttons).
struct TopBar: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        // Row 1 sits level with the window buttons: logo and name on the left, help on the right.
        // Row 2 holds the tabs, centered. Separate rows, so the name and the tabs never collide.
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Color.clear.frame(width: 70, height: 1)   // red / yellow / green window buttons
                KartovBrand()
                Spacer(minLength: 0)
                UpdateTopButton()
                Button { model.openTutorial() } label: {
                    Image(systemName: "questionmark.circle").font(.system(size: 14))
                        .foregroundStyle(KColor.textMuted).frame(width: 26, height: 26).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L("Nasıl kullanılır? Turu yeniden başlat"))
                Button { model.section = .settings } label: {
                    Image(systemName: model.section == .settings ? "gearshape.fill" : "gearshape").font(.system(size: 14))
                        .foregroundStyle(model.section == .settings ? KColor.accent : KColor.textMuted)
                        .frame(width: 26, height: 26).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L("Ayarlar"))
                .keyboardShortcut(",", modifiers: .command)
            }
            .frame(height: 30)

            HStack(spacing: 4) {
                ForEach(TopTab.allCases) { tab in
                    TabPill(tab: tab, selected: TopTab.of(model.section) == tab,
                            highlighted: model.tourSection.map { TopTab.of($0) == tab } ?? false,
                            badge: badge(for: tab)) { open(tab) }
                }
            }
            .padding(4)
            .background(Capsule().fill(KColor.surface.opacity(0.7)))
            .overlay(Capsule().strokeBorder(KGradient.rim))
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    private func open(_ tab: TopTab) {
        switch tab {
        case .clean:
            if model.phase == .scanning { model.section = .scan }
            else { model.section = model.items.isEmpty ? .scan : .results }
        default:
            model.section = tab.sections[0]
        }
    }

    private func badge(for tab: TopTab) -> String? {
        switch tab {
        case .clean where model.phase == .scanning: return "%\(Int(model.scanFraction * 100))"
        case .clean where model.selectedBytes > 0: return KBytes.format(model.selectedBytes)
        default: return nil
        }
    }
}

struct TabPill: View {
    let tab: TopTab
    let selected: Bool
    var highlighted: Bool = false
    let badge: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: tab.symbol).font(.system(size: 12, weight: .semibold))
                Text(tab.title).font(.system(size: 12, weight: selected ? .semibold : .medium))
                if let badge {
                    Text(badge).font(.system(size: 10, weight: .bold).monospacedDigit())
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(selected ? Color.white.opacity(0.22) : KColor.heat.opacity(0.18)))
                        .foregroundStyle(selected ? Color.white : KColor.heatSoft)
                }
            }
            .foregroundStyle(selected ? Color.white : KColor.textMuted)
            .padding(.horizontal, 12).frame(height: 30)
            .background(Capsule().fill(selected ? AnyShapeStyle(KGradient.accent) : AnyShapeStyle(Color.clear)))
            .overlay(Capsule().strokeBorder(KGradient.accent, lineWidth: highlighted && !selected ? 2 : 0))
            .shadow(color: KColor.accent.opacity(selected || highlighted ? 0.45 : 0), radius: 8, y: 2)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Progress notes in the Terminal window, to diagnose a run started with `swift run`.
func klog(_ message: String) {
    FileHandle.standardError.write(Data(("Kartov: " + message + "\n").utf8))
}

struct MenuBarPanel: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        let bytes = model.selectedBytes
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Globe(dirt: dirtLevel(bytes), speed: model.autoRunning ? 1.2 : 0.2, size: 40)
                    .frame(width: 60, height: 60)
                VStack(alignment: .leading, spacing: 2) {
                    KartovBrand()
                    Text(model.items.isEmpty ? L("Hazır") : (bytes > 0 ? KBytes.format(bytes) : L("Tertemiz")))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(bytes >= 5_000_000_000 ? KColor.heat : KColor.text)
                    Text(model.autoMessage ?? (model.items.isEmpty ? L("Tek tıkla temizle ya da optimize et.") : L("temizlenebilir")))
                        .font(.system(size: 11)).foregroundStyle(KColor.textMuted).lineLimit(2)
                }
            }
            if let m = model.memory {
                HStack {
                    Text(L("Bellek")).foregroundStyle(KColor.textMuted)
                    Spacer()
                    Text("%\(Int(m.pressure * 100))").monospacedDigit()
                }
                .font(.system(size: 12))
            }
            HStack(spacing: 8) {
                Button { StatusBar.shared.runQuick(.clean) } label: {
                    Text(model.autoRunning ? L("Temizleniyor…") : L("Temizle")).frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                Button { StatusBar.shared.runQuick(.optimize) } label: {
                    Text(model.optimizeBusy != nil ? "…" : L("Optimize et")).frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            .disabled(model.quickBusy)
            Button { StatusBar.shared.runQuick(.both) } label: {
                Text(L("İkisini birden yap")).frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(model.quickBusy)
            Button(L("Kartov'u aç")) { StatusBar.shared.openApp() }
                .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(KColor.accentSoft)
        }
        .padding(14)
        .frame(width: 300)
        .background(KColor.surface)
        .foregroundStyle(KColor.text)
        .onAppear { model.sampleSystem() }
    }
}


/// The app's own icon (blue globe), read from the bundle.
struct KartovLogo: View {
    var size: CGFloat = 22
    var body: some View {
        Image(nsImage: NSApplication.shared.applicationIconImage)
            .resizable().interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Logo and name, top left of the window.
struct KartovBrand: View {
    var body: some View {
        HStack(spacing: 7) {
            KartovLogo(size: 20)
            Text("Kartov").font(.system(size: 13, weight: .bold)).foregroundColor(KColor.text)
            + Text(" Cleaner").font(.system(size: 13, weight: .medium)).foregroundColor(KColor.textMuted)
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Kartov Cleaner")
    }
}

/// Shows the update window above everything when asked.
struct UpdateOverlay: View {
    @ObservedObject var updater = Updater.shared
    var body: some View {
        if updater.showSheet { UpdateSheet() }
    }
}
