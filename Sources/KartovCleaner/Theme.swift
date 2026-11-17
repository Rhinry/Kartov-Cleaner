// Kartov Cleaner design tokens for SwiftUI — generated from tokens.json.
// This replaces the Tailwind mapping in the template: the app is native, so views use
// KTheme roles (Color.k.surface, KFont.lg, KSpace.s4), never raw hex.
// Colors adapt to dark/light via NSColor(name:dynamicProvider:). Dark is the default appearance.

import SwiftUI
import AppKit

private func dyn(_ dark: UInt32, _ light: UInt32) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let v = isDark ? dark : light
        return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                       green:   CGFloat((v >> 8) & 0xFF) / 255,
                       blue:    CGFloat(v & 0xFF) / 255, alpha: 1)
    })
}

enum KColor {
    static let bg          = dyn(0x0E0F12, 0xF6F6F8)
    static let surface     = dyn(0x17191E, 0xFFFFFF)
    static let surface2    = dyn(0x1F2228, 0xEEEFF2)
    static let border      = dyn(0x2A2E36, 0xDFE1E6)
    static let borderInput = dyn(0x636B78, 0x868D99)
    static let text        = dyn(0xECEEF2, 0x121418)
    static let textMuted   = dyn(0x9AA1AD, 0x565E6B)
    static let accent      = dyn(0x4C8DFF, 0x1F5FD6)   // action, selection, "temizle"
    static let onAccent    = dyn(0x061433, 0xFFFFFF)
    static let heat        = dyn(0xFF5A5F, 0xC42B33)   // accumulated cache, "temizlik zamanı"
    static let danger      = dyn(0xFF5A5F, 0xC42B33)
    static let success     = dyn(0x3DD68C, 0x1B7A4B)
    static let warning     = dyn(0xF2D16B, 0x7D6200)
    static let keep        = dyn(0xB8C1D1, 0x55606F)   // "koru" state (silver)
}

enum KFont {
    static let xs      = Font.system(size: 11, weight: .medium)
    static let sm      = Font.system(size: 13)
    static let base    = Font.system(size: 14)
    static let lg      = Font.system(size: 17, weight: .semibold)
    static let xl      = Font.system(size: 24, weight: .medium)
    static let display = Font.system(size: 44, weight: .medium).monospacedDigit()
    /// Every byte value (GB/MB) uses tabular digits so columns don't jitter.
    static func number(_ size: CGFloat = 14, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight).monospacedDigit()
    }
}

enum KSpace {
    static let s1: CGFloat = 4, s2: CGFloat = 8, s3: CGFloat = 12, s4: CGFloat = 16, s5: CGFloat = 20
    static let s6: CGFloat = 24, s7: CGFloat = 32, s8: CGFloat = 48, s9: CGFloat = 64
}

enum KRadius { static let sm: CGFloat = 6, md: CGFloat = 10, lg: CGFloat = 14 }

enum KLayout {
    static let windowMin = CGSize(width: 1240, height: 660)
    static let windowDefault = CGSize(width: 1120, height: 720)
    static let sidebar: CGFloat = 220, toolbar: CGFloat = 52, contentMax: CGFloat = 880
    static let row: CGFloat = 44, rowCompact: CGFloat = 36
}

enum KMotion {
    static let fast = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.12)
    static let base = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.20)
    static let count: Double = 0.6   // GB roll-up; skip when accessibilityReduceMotion is on
}

/// Byte formatting used everywhere: "38,2 GB", "742 MB" (locale-aware decimal separator).
enum KBytes {
    static func format(_ bytes: Int64) -> String {
        if bytes <= 0 { return "0 MB" }
        let f = ByteCountFormatter()
        f.countStyle = .file          // decimal (1 GB = 1,000,000,000 B), matches Finder
        f.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        f.allowsNonnumericFormatting = false   // no "Zero KB"
        return f.string(fromByteCount: bytes)
    }
}

extension KColor {
    /// Sidebar and toolbar layer, one step darker than content.
    static let chrome    = dyn(0x131519, 0xEEEFF2)
    static let heatSoft  = dyn(0xFF8A8E, 0xA8232B)
    static let accentSoft = dyn(0x8FB5FF, 0x1A4FB3)
    /// Accumulation chart layers, bottom to top.
    static let strataSystem   = dyn(0x7A2630, 0xF4C7CA)
    static let strataApp      = dyn(0xB3323D, 0xE8959A)
    static let strataBrowser  = dyn(0xE5484D, 0xD9575E)
    static let strataCreative = dyn(0xFF7A7E, 0xB3202A)
}

// MARK: gradients and cards

enum KGradient {
    /// Primary actions: blue to cyan.
    /// Solid fills, kept as gradient types for existing call sites. No hue-to-hue gradients:
    /// blue means "an action", red means "space you can get back".
    static let accent = LinearGradient(colors: [KColor.accent, KColor.accent], startPoint: .top, endPoint: .bottom)
    static let heat = LinearGradient(colors: [KColor.heat, KColor.heat], startPoint: .top, endPoint: .bottom)
    static let success = LinearGradient(colors: [KColor.success, KColor.success], startPoint: .top, endPoint: .bottom)
    static let violet = LinearGradient(colors: [KColor.accent, KColor.accent], startPoint: .top, endPoint: .bottom)
    static let warning = LinearGradient(colors: [KColor.warning, KColor.warning], startPoint: .top, endPoint: .bottom)
    /// Quiet fill for icon tiles and normal gauges.
    static let quiet = LinearGradient(colors: [KColor.textMuted, KColor.textMuted], startPoint: .top, endPoint: .bottom)
    /// Card fill: a touch lighter at the top.
    /// Card fill: flat (one color), kept as a gradient type for existing call sites.
    static let card = LinearGradient(colors: [KColor.surface, KColor.surface], startPoint: .top, endPoint: .bottom)
    /// Card edge: flat hairline.
    static let rim = LinearGradient(colors: [KColor.border, KColor.border], startPoint: .top, endPoint: .bottom)
}

/// Window background: one flat dark ground. Color lives in the globe and the figures, not behind them.
struct AppBackground: View {
    var body: some View {
        KColor.bg.ignoresSafeArea()
    }
}

struct KCardModifier: ViewModifier {
    var padding: CGFloat
    var radius: CGFloat
    var glow: Color?
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: radius).fill(KColor.surface))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(KColor.border, lineWidth: 1))
    }
}

extension View {
    /// The Kartov card: flat solid fill and a hairline border. `glow` is kept for call sites but not drawn.
    func kCard(padding: CGFloat = 18, radius: CGFloat = 18, glow: Color? = nil) -> some View {
        modifier(KCardModifier(padding: padding, radius: radius, glow: glow))
    }
}
