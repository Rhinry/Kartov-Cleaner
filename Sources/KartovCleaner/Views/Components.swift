import SwiftUI
import KartovCore

// MARK: buttons

struct PrimaryButtonStyle: ButtonStyle {
    var large = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: large ? 15 : 13, weight: .bold))
            .foregroundStyle(KColor.onAccent)
            .padding(.horizontal, large ? 24 : 16)
            .frame(height: large ? 46 : 34)
            .background(Capsule().fill(KGradient.accent).opacity(configuration.isPressed ? 0.8 : 1))
            .shadow(color: KColor.accent.opacity(isEnabled ? 0.35 : 0), radius: 10, y: 4)
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Capsule())
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var large = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: large ? 14 : 13, weight: .semibold))
            .foregroundStyle(KColor.text)
            .padding(.horizontal, large ? 20 : 14)
            .frame(height: large ? 46 : 32)
            .background(Capsule().fill(KColor.surface2.opacity(configuration.isPressed ? 1 : 0.0)))
            .overlay(Capsule().strokeBorder(KColor.border))
            .contentShape(Capsule())
    }
}

// MARK: capsule picker

/// A small set of choices as pill tabs, drawn like the main tab bar.
struct CapsulePicker<T: Hashable & Identifiable>: View {
    let options: [T]
    let title: (T) -> String
    let selection: T
    let onSelect: (T) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options) { option in
                let selected = option == selection
                Button { onSelect(option) } label: {
                    Text(title(option)).font(.system(size: 12, weight: selected ? .semibold : .medium))
                        .foregroundStyle(selected ? Color.white : KColor.textMuted)
                        .padding(.horizontal, 12).frame(height: 26)
                        .background(Capsule().fill(selected ? AnyShapeStyle(KGradient.accent) : AnyShapeStyle(Color.clear)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(KColor.surface2.opacity(0.8)))
        .overlay(Capsule().strokeBorder(KGradient.rim))
        .fixedSize()
    }
}

// MARK: status

struct StatusPill: View {
    let text: String
    let color: Color
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.system(size: 13, weight: .semibold)).foregroundStyle(color)
        }
        .padding(.horizontal, 11)
        .frame(height: 26)
        .background(Capsule().fill(color.opacity(0.14)))
    }
}

/// Clean / keep / mixed switch drawn to match the design. It is decoration: the row is the button.
struct KeepSwitch: View {
    let state: ToggleState
    var body: some View {
        HStack(spacing: 8) {
            ZStack(alignment: .leading) {
                Capsule().fill(track).frame(width: 36, height: 20)
                Circle().fill(knob).frame(width: 16, height: 16).offset(x: offset)
            }
            .opacity(state == .locked ? 0.45 : 1)
            .animation(KMotion.fast, value: offset)
        }
        .accessibilityHidden(true)
    }
    private var label: String {
        switch state { case .clean: return L("Temizle"); case .keep: return L("Koru"); case .mixed: return L("Karışık"); case .locked: return L("Açık uygulama") }
    }
    private var labelColor: Color {
        switch state { case .clean: return KColor.accentSoft; case .keep: return KColor.keep; case .mixed: return KColor.text; case .locked: return KColor.textMuted }
    }
    private var track: Color {
        switch state { case .clean: return KColor.accent; case .keep: return KColor.keep; case .mixed: return KColor.accent.opacity(0.45); case .locked: return KColor.border }
    }
    private var knob: Color { state == .clean ? KColor.onAccent : KColor.bg }
    private var offset: CGFloat {
        switch state { case .clean, .locked: return 18; case .keep: return 2; case .mixed: return 10 }
    }
}

struct AppIcon: View {
    let key: String?
    let monogram: String
    var hot = false
    var body: some View {
        Group {
            if let key, let image = AppInfoResolver.shared.icon(for: key) {
                Image(nsImage: image).resizable().interpolation(.high)
            } else {
                RoundedRectangle(cornerRadius: 7)
                    .fill(hot ? KColor.heat.opacity(0.14) : KColor.surface2)
                    .overlay(Text(monogram).font(.system(size: 11, weight: .bold))
                        .foregroundStyle(hot ? KColor.heatSoft : KColor.textMuted))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(KColor.border))
            }
        }
        .frame(width: 30, height: 30)
        .accessibilityHidden(true)
    }

    static func monogram(_ title: String) -> String {
        let words = title.split(separator: " ").prefix(2)
        let letters = words.compactMap(\.first).map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }
}

// MARK: numbers

/// Big byte figure. Digits are tabular so they don't jitter while counting.
struct BytesText: View {
    let bytes: Int64
    var size: CGFloat = 44
    var color: Color = KColor.text
    var body: some View {
        Text(KBytes.format(bytes))
            .font(.system(size: size, weight: .bold).monospacedDigit())
            .kerning(size > 40 ? -1.2 : -0.3)
            .foregroundStyle(color)
    }
}

/// Horizontal share bar: selected / kept / locked.
struct ShareBar: View {
    let selected: Int64
    let kept: Int64
    let locked: Int64
    var selectedColor: Color = KColor.heat
    var body: some View {
        GeometryReader { geo in
            let total = max(CGFloat(selected + kept + locked), 1)
            HStack(spacing: 2) {
                Rectangle().fill(selectedColor).frame(width: geo.size.width * CGFloat(selected) / total)
                Rectangle().fill(KColor.keep.opacity(0.75)).frame(width: geo.size.width * CGFloat(kept) / total)
                Rectangle().fill(KColor.textMuted.opacity(0.6)).frame(width: geo.size.width * CGFloat(locked) / total)
                Spacer(minLength: 0)
            }
            .clipShape(Capsule())
            .animation(KMotion.base, value: selected)
        }
        .frame(height: 14)
        .background(Capsule().fill(KColor.surface2))
    }
}

struct LegendDot: View {
    let color: Color
    let text: String
    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            Text(text).font(.system(size: 11)).foregroundStyle(KColor.textMuted)
        }
    }
}

// MARK: permission

struct PermissionBanner: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        if !model.hasFullDiskAccess {
            HStack(spacing: 12) {
                Image(systemName: "lock.shield").foregroundStyle(KColor.warning)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Kartov şu an tam performansla çalışmıyor")).font(.system(size: 13, weight: .semibold))
                    Text(L("Tam Disk Erişimi verilmediği için Safari, Mail ve bazı uygulamaların klasörlerine bakılamıyor; bulunan yer gerçekte olandan az görünebilir."))
                        .font(.system(size: 12)).foregroundStyle(KColor.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button(L("İzin ver")) { Permissions.openFullDiskAccessSettings() }
                    .buttonStyle(PrimaryButtonStyle())
                Button(L("Yeniden başlat")) { Permissions.relaunch() }
                    .buttonStyle(SecondaryButtonStyle())
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(KColor.warning.opacity(0.08))
            .overlay(alignment: .bottom) { Rectangle().fill(KColor.border).frame(height: 1) }
        }
    }
}

struct PageHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing
    var body: some View {
        HStack(spacing: 12) {
            Text(title).font(.system(size: 15, weight: .semibold))
            Spacer()
            trailing()
        }
        .padding(.horizontal, 28)
        .frame(height: KLayout.toolbar)
        .overlay(alignment: .bottom) { Rectangle().fill(KColor.border.opacity(0.6)).frame(height: 1) }
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String) { self.init(title: title) { EmptyView() } }
}

func relativeDay(_ date: Date) -> String {
    let f = RelativeDateTimeFormatter()
    f.locale = I18n.locale
    f.unitsStyle = .full
    return f.localizedString(for: date, relativeTo: Date())
}
