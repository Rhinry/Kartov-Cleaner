import Foundation

/// Languages Kartov speaks. Turkish is the source text; the others come from strings.json.
public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system, tr, en, de, es
    public var id: String { rawValue }
    /// Each language's name in its own words, so anyone can find theirs.
    public var nativeName: String {
        switch self {
        case .system: return L("Sistem dili")
        case .tr: return "Türkçe"
        case .en: return "English"
        case .de: return "Deutsch"
        case .es: return "Español"
        }
    }
}

public enum I18n {
    public static let defaultsKey = "appLanguage"
    static let supported = ["tr", "en", "de", "es"]

    /// The language chosen in Settings (or "system").
    public static var choice: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .system
    }

    /// The language actually used. Read once at launch; changing it takes a restart.
    public static let code: String = {
        let pick = choice
        if pick != .system { return pick.rawValue }
        for pref in Locale.preferredLanguages {
            let c = String(pref.prefix(2)).lowercased()
            if supported.contains(c) { return c }
        }
        return "en"
    }()

    public static var locale: Locale {
        Locale(identifier: ["tr": "tr_TR", "en": "en_US", "de": "de_DE", "es": "es_ES"][code] ?? code)
    }

    static let table: [String: String] = {
        guard code != "tr", let url = resourceURL("strings.json"),
              let data = try? Data(contentsOf: url),
              let all = try? JSONDecoder().decode([String: [String: String]].self, from: data) else { return [:] }
        return all[code] ?? [:]
    }()

    /// Inside the .app the resource bundle sits in Contents/Resources; look there before Bundle.module.
    static func resourceURL(_ file: String) -> URL? {
        if let resources = Bundle.main.resourceURL,
           let names = try? FileManager.default.contentsOfDirectory(atPath: resources.path) {
            for name in names where name.hasSuffix(".bundle") && name.contains("KartovCore") {
                for candidate in [file, "Contents/Resources/" + file] {
                    let url = resources.appendingPathComponent(name).appendingPathComponent(candidate)
                    if FileManager.default.fileExists(atPath: url.path) { return url }
                }
            }
        }
        let base = (file as NSString).deletingPathExtension
        let ext = (file as NSString).pathExtension
        return Bundle.module.url(forResource: base, withExtension: ext)
    }
}

/// Translates a Turkish source text. `{0}`, `{1}`… are filled with `args` in order.
public func L(_ key: String, _ args: Any...) -> String {
    var s = I18n.table[key] ?? key
    for (i, a) in args.enumerated() {
        s = s.replacingOccurrences(of: "{\(i)}", with: "\(a)")
    }
    return s
}
