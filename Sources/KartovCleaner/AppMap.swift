import Foundation
import AppKit
import KartovCore

/// The program shown in the "Bağlantılı dosyalar" map.
struct AppMapTarget: Identifiable, Equatable {
    let id: String          // bundle id
    let name: String
    let url: URL?
    let icon: NSImage?
}

extension FootprintNode.Kind {
    var title: String {
        switch self {
        case .cache: return L("Önbellek")
        case .logs: return L("Kayıtlar")
        case .preferences: return L("Ayarlar")
        case .support: return L("Destek dosyaları")
        case .container: return L("Kapsayıcı")
        case .savedState: return L("Pencere durumu")
        case .webData: return L("Web verisi")
        case .startup: return L("Başlangıç öğeleri")
        }
    }

    var symbol: String {
        switch self {
        case .cache: return "shippingbox.fill"
        case .logs: return "doc.text.fill"
        case .preferences: return "slider.horizontal.3"
        case .support: return "folder.fill"
        case .container: return "cube.box.fill"
        case .savedState: return "macwindow"
        case .webData: return "network"
        case .startup: return "power"
        }
    }

    var note: String {
        switch self {
        case .cache: return L("Program yeniden oluşturur; silmek güvenli.")
        case .logs: return L("Sorun kayıtları; silmek güvenli.")
        case .preferences: return L("Programın ayarları. Silinirse ayarlar sıfırlanır.")
        case .support: return L("Programın verileri; belgelerin, eklentilerin ve hesapların olabilir.")
        case .container: return L("Programın korumalı alanı; içinde kendi verileri durur.")
        case .savedState: return L("Açık pencerelerin yeri; silmek güvenli.")
        case .webData: return L("Çerezler ve web önbelleği; silinirse oturumlar kapanabilir.")
        case .startup: return L("Mac açılınca çalışan yardımcılar.")
        }
    }
}

/// App Dependency Map: everything one program keeps in the Library, grouped and measured.
/// Only regenerable files (cache, logs, window state, web data) can be moved to the Trash,
/// only after the user confirms, only while the program is closed, and always undoable from History.
@MainActor
final class AppMap: ObservableObject {
    static let shared = AppMap()

    @Published private(set) var target: AppMapTarget?
    @Published private(set) var nodes: [FootprintNode] = []
    @Published private(set) var loading = false
    @Published var confirm: FootprintNode.Kind?
    @Published var message: String?
    @Published private(set) var busy = false

    var total: Int64 { nodes.filter { $0.kind != .startup }.reduce(0) { $0 + $1.bytes } }

    func open(bundleID: String, name: String, url: URL? = nil) {
        let appURL = url ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        target = AppMapTarget(id: bundleID, name: name, url: appURL,
                              icon: appURL.map { NSWorkspace.shared.icon(forFile: $0.path) })
        nodes = []
        confirm = nil
        message = nil
        reload()
    }

    func close() {
        target = nil
        nodes = []
        confirm = nil
        message = nil
    }

    private func reload() {
        guard let t = target else { return }
        loading = true
        let id = t.id, name = t.name
        Task.detached(priority: .userInitiated) {
            let found = AppFootprint.scan(bundleID: id, appName: name)
            await MainActor.run {
                let m = AppMap.shared
                guard m.target?.id == id else { return }
                m.nodes = found.sorted { $0.bytes > $1.bytes }
                m.loading = false
            }
        }
    }

    var isRunning: Bool {
        guard let id = target?.id else { return false }
        return NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == id }
    }

    /// Moves one group of regenerable files to the Trash and records it in History.
    func trash(_ node: FootprintNode, model: AppModel) {
        confirm = nil
        guard let t = target, node.kind.removable, !busy else { return }
        if isRunning {
            message = L("Önce {0} programını kapat; açıkken dosyalarını kullanıyor.", t.name)
            return
        }
        busy = true
        let urls = node.urls, kind = node.kind, appName = t.name
        Task.detached(priority: .userInitiated) {
            let record = PathTrasher.trash(urls, ruleID: "appmap." + kind.rawValue, appKey: appName)
            await MainActor.run {
                let m = AppMap.shared
                m.busy = false
                if record.bytesCleaned > 0 { model.addRecord(record) }
                m.message = record.bytesCleaned > 0
                    ? L("{0} çöp kutusuna taşındı. Geçmiş'ten geri alabilirsin.", KBytes.format(record.bytesCleaned))
                    : L("Hiçbir şey taşınamadı.")
                m.reload()
            }
        }
    }
}

// MARK: - Crash Detective helpers

/// Reports of one program, for the Çökmeler page.
struct CrashGroup: Identifiable {
    var id: String { app }
    let app: String
    let bundleID: String?
    let reports: [CrashReport]

    var crashes: Int { reports.filter { $0.kind == .crash }.count }
    var hangs: Int { reports.filter { $0.kind == .hang }.count }
    var resource: Int { reports.filter { $0.kind == .resource }.count }
    var panics: Int { reports.filter { $0.kind == .panic }.count }
    var last: Date { reports.map(\.date).max() ?? .distantPast }

    /// The most frequent reason.
    var mainReason: (CrashReport.Kind, String?) {
        var count: [String: Int] = [:]
        for r in reports { count[r.kind.rawValue + "|" + (r.reason ?? ""), default: 0] += 1 }
        guard let top = count.max(by: { $0.value < $1.value })?.key else { return (.crash, nil) }
        let parts = top.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        let kind = CrashReport.Kind(rawValue: String(parts[0])) ?? .crash
        let reason = parts.count > 1 && !parts[1].isEmpty ? String(parts[1]) : nil
        return (kind, reason)
    }

    static func make(_ reports: [CrashReport]) -> [CrashGroup] {
        var by: [String: [CrashReport]] = [:]
        for r in reports { by[r.app, default: []].append(r) }
        return by.map { app, list in
            CrashGroup(app: app, bundleID: list.compactMap(\.bundleID).first, reports: list.sorted { $0.date > $1.date })
        }
        .sorted { a, b in
            if a.panics != b.panics { return a.panics > b.panics }
            if a.reports.count != b.reports.count { return a.reports.count > b.reports.count }
            return a.last > b.last
        }
    }
}

enum CrashExplainer {
    /// What happened, in plain words.
    static func explain(_ kind: CrashReport.Kind, _ reason: String?) -> String {
        let r = (reason ?? "").uppercased()
        switch kind {
        case .panic: return L("Mac beklenmedik şekilde yeniden başladı. Sık oluyorsa bir sürücü ya da donanım sorunu olabilir.")
        case .hang: return L("Program bir süre yanıt vermedi (dönen renkli top).")
        case .resource:
            if r.contains("DISKWRITES") { return L("Diske kısa sürede çok fazla yazdı; diski yorar.") }
            if r.contains("WAKEUPS") { return L("Mac'i çok sık uyandırdı; pil ömrünü kısaltır.") }
            return L("İşlemciyi uzun süre çok fazla kullandı.")
        case .crash:
            if r.contains("SIGKILL") { return L("macOS programı kapattı: yanıt vermedi ya da çok fazla kaynak kullandı.") }
            if r.contains("BAD_ACCESS") || r.contains("SIGSEGV") || r.contains("SIGBUS") {
                return L("Program bellekte geçersiz bir yere erişmeye çalıştı. Genellikle programın kendi hatasıdır.")
            }
            if r.contains("SIGABRT") { return L("Program bir iç kontrolü geçemeyip kendini durdurdu. Bozuk ayar ya da önbellek de buna yol açabilir.") }
            if r.contains("BREAKPOINT") || r.contains("SIGTRAP") { return L("Program beklemediği bir durumla karşılaşıp durdu.") }
            if r.contains("BAD_INSTRUCTION") || r.contains("SIGILL") { return L("Program çalıştırılamayan bir komuta geldi; bozuk ya da uyumsuz bir sürüm olabilir.") }
            if r.contains("GUARD") { return L("macOS, korunan bir kaynağa yanlış erişimi durdurdu.") }
            return L("Program beklenmedik şekilde kapandı.")
        }
    }

    /// What the user can do about it.
    static func advice(_ g: CrashGroup) -> String {
        if g.panics > 0 { return L("macOS'u güncelle; çevre birimlerini çıkarıp dene. Sürerse Apple desteğine başvur.") }
        if g.reports.count >= 3 { return L("Sık oluyor: programı güncelle. Düzelmezse önbelleğini temizle (Bağlantılı dosyalar).") }
        return L("Bir kez olduysa önemli değil. Tekrarlarsa programı güncelle.")
    }
}
