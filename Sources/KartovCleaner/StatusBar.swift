import AppKit
import SwiftUI
import KartovCore
import Combine

/// The small globe in the menu bar. A left click does what the user chose (open the panel,
/// quick clean, or optimize memory); a right click always shows the menu.
@MainActor
final class StatusBar: NSObject {
    static let shared = StatusBar()

    private var item: NSStatusItem?
    private weak var model: AppModel?
    private let popover = NSPopover()
    private let feedback = NSPopover()
    private var closeWork: DispatchWorkItem?
    private var bag = Set<AnyCancellable>()
    private var resetWork: DispatchWorkItem?

    func install(model: AppModel) {
        self.model = model
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarPanel().environmentObject(model).preferredColorScheme(.dark))
        feedback.behavior = .transient
        feedback.animates = true
        feedback.contentViewController = NSHostingController(
            rootView: QuickFeedback().environmentObject(model).preferredColorScheme(.dark))
        // When a one-click action finishes, leave the result up for a moment, then close.
        model.$quickBusy.removeDuplicates().dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] busy in Task { @MainActor in self?.quickChanged(busy) } }
            .store(in: &bag)
        // Show progress and results on the icon itself.
        model.$autoRunning.combineLatest(model.$optimizeBusy)
            .receive(on: RunLoop.main)
            .sink { [weak self] running, busy in Task { @MainActor in self?.setBusy(running || busy != nil) } }
            .store(in: &bag)
        model.$autoMessage.compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] m in Task { @MainActor in self?.flash(StatusBar.shortResult(m)) } }
            .store(in: &bag)
        model.$optimizeMessage.compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in Task { @MainActor in self?.flash("✓") } }
            .store(in: &bag)
        refresh()
    }

    func refresh() {
        guard let model else { return }
        if model.showMenuBarIcon {
            if item == nil {
                let it = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                it.button?.image = Self.icon("globe.europe.africa.fill")
                it.button?.imagePosition = .imageLeading
                it.button?.target = self
                it.button?.action = #selector(clicked(_:))
                it.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
                it.button?.toolTip = "Kartov Cleaner"
                item = it
            }
        } else if let it = item {
            NSStatusBar.system.removeStatusItem(it)
            item = nil
        }
    }

    private static func icon(_ name: String) -> NSImage? {
        let img = NSImage(systemSymbolName: name, accessibilityDescription: "Kartov Cleaner")
        img?.isTemplate = true
        return img
    }

    private func setBusy(_ busy: Bool) {
        item?.button?.image = Self.icon(busy ? "arrow.triangle.2.circlepath" : "globe.europe.africa.fill")
        if busy { item?.button?.title = "" }
    }

    /// Shows a short text next to the icon for a few seconds.
    private func flash(_ text: String) {
        guard let button = item?.button else { return }
        button.title = text.isEmpty ? "" : " " + text
        resetWork?.cancel()
        let work = DispatchWorkItem { [weak self] in Task { @MainActor in self?.item?.button?.title = "" } }
        resetWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: work)
    }

    static func shortResult(_ message: String) -> String {
        // "Hızlı temizlik 1,2 GB yer açtı." → "1,2 GB"
        // Pick the first size in the message ("1,2 GB"), whatever the language.
        if let r = message.range(of: #"[0-9][0-9.,]*\s?[A-Za-z]{1,5}"#, options: .regularExpression) {
            return String(message[r])
        }
        return "✓"
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        guard let model else { return }
        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if wantsMenu { showMenu(); return }
        if model.menuBarAction == .panel { togglePopover(sender) } else { runQuick(model.menuBarAction) }
    }

    /// Runs a one-click action and shows a small bubble under the icon with what is happening.
    func runQuick(_ action: MenuBarAction) {
        guard let model, let button = item?.button else { return }
        if popover.isShown { popover.performClose(nil) }
        closeWork?.cancel()
        model.runQuick(action)
        if !feedback.isShown { feedback.show(relativeTo: button.bounds, of: button, preferredEdge: .minY) }
    }

    private func quickChanged(_ busy: Bool) {
        guard !busy else { return }
        closeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in Task { @MainActor in self?.feedback.performClose(nil) } }
        closeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }

    private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown { popover.performClose(nil); return }
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func showMenu() {
        guard let model, let item else { return }
        let menu = NSMenu()
        if let r = Updater.shared.release {
            menu.addItem(entry(L("Güncelleme var: {0}", r.version), #selector(showUpdate)))
        } else {
            menu.addItem(entry(L("Güncellemeleri denetle…"), #selector(checkUpdates)))
        }
        menu.addItem(entry(L("Kartov'u aç"), #selector(openApp)))
        menu.addItem(.separator())
        menu.addItem(entry(model.autoRunning ? L("Temizleniyor…") : L("Hızlı temizlik"), #selector(clean)))
        menu.addItem(entry(model.optimizeBusy != nil ? L("Optimize ediliyor…") : L("Belleği optimize et"), #selector(optimize)))
        menu.addItem(entry(L("Temizle ve optimize et"), #selector(both)))
        menu.addItem(.separator())
        let clickMenu = NSMenu()
        for a in MenuBarAction.allCases {
            let mi = entry(a.title, #selector(setAction(_:)))
            mi.representedObject = a.rawValue
            mi.state = model.menuBarAction == a ? .on : .off
            clickMenu.addItem(mi)
        }
        let clickItem = NSMenuItem(title: L("Simgeye tıklayınca"), action: nil, keyEquivalent: "")
        clickItem.submenu = clickMenu
        menu.addItem(clickItem)
        let bg = entry(L("Arka planda çalış"), #selector(toggleBackground))
        bg.state = model.runInBackground ? .on : .off
        menu.addItem(bg)
        menu.addItem(.separator())
        menu.addItem(entry(L("Kartov'dan çık"), #selector(quit)))
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil   // so the next left click goes back to the chosen action
    }

    private func entry(_ title: String, _ action: Selector) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: "")
        mi.target = self
        return mi
    }

    @objc func openApp() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let w = NSApp.windows.first(where: { $0.canBecomeMain && !($0 is NSPanel) }) {
            w.makeKeyAndOrderFront(nil)
        } else {
            model?.openMainWindow?()
        }
    }
    @objc private func checkUpdates() {
        openApp()
        Task { await Updater.shared.check(userInitiated: true) }
    }
    @objc private func showUpdate() {
        openApp()
        Updater.shared.showSheet = true
    }
    @objc private func clean() { runQuick(.clean) }
    @objc private func optimize() { runQuick(.optimize) }
    @objc private func both() { runQuick(.both) }
    @objc private func setAction(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let a = MenuBarAction(rawValue: raw) { model?.menuBarAction = a }
    }
    @objc private func toggleBackground() { model?.runInBackground.toggle() }
    @objc private func quit() { NSApp.terminate(nil) }
}

/// Decides whether closing the window quits the app, and hides the Dock icon while
/// Kartov only lives in the menu bar.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !UserDefaults.standard.bool(forKey: "runInBackground")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { note in
            guard let closing = note.object as? NSWindow else { return }
            Task { @MainActor in
                guard closing.canBecomeMain, !(closing is NSPanel) else { return }
                let open = NSApp.windows.contains { $0 !== closing && $0.isVisible && $0.canBecomeMain && !($0 is NSPanel) }
                if !open && UserDefaults.standard.bool(forKey: "runInBackground") {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { Task { @MainActor in StatusBar.shared.openApp() } }
        return true
    }
}

/// The bubble under the menu bar icon after a one-click action: progress, then the result.
struct QuickFeedback: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Globe(dirt: 0, speed: model.quickBusy ? 1.6 : 0.2, size: 30, shine: model.quickBusy ? 0 : 0.8)
                .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 5) {
                Text(model.quickBusy ? L("Kartov çalışıyor") : L("Bitti"))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(model.quickBusy ? KColor.text : KColor.success)
                if let s = model.quickStatus {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(s).font(.system(size: 12)).foregroundStyle(KColor.textMuted)
                    }
                }
                ForEach(model.quickResults, id: \.self) { r in
                    Label(r, systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(KColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(width: 300)
        .background(KColor.surface)
        .foregroundStyle(KColor.text)
    }
}
