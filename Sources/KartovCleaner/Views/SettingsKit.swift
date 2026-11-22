import SwiftUI
import KartovCore

// The building blocks of Settings: a page is a title and a few groups, a group is a few rows.
// Every row has the same shape: what it is, one plain sentence, one control.

enum SettingsMetrics {
    static let sidebar: CGFloat = 288
    static let page: CGFloat = 680
    static let rowMinHeight: CGFloat = 60
    static let rowInset: CGFloat = 20
}

// MARK: page and group

struct SettingsPageBody<Content: View>: View {
    let title: String
    let intro: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.system(size: 28, weight: .medium))
                    .accessibilityAddTraits(.isHeader)
                Text(intro).font(.system(size: 14)).foregroundStyle(KColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content()
        }
        .frame(maxWidth: SettingsMetrics.page, alignment: .leading)
    }
}

struct SettingsGroup<Content: View>: View {
    var title: String? = nil
    var footer: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(KColor.textMuted)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(spacing: 0) { content() }
                .background(RoundedRectangle(cornerRadius: KRadius.lg).fill(KColor.surface))
                .clipShape(RoundedRectangle(cornerRadius: KRadius.lg))
                .overlay(RoundedRectangle(cornerRadius: KRadius.lg).strokeBorder(KColor.border))
            if let footer {
                Text(footer).font(.system(size: 12)).foregroundStyle(KColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SettingsDivider: View {
    var body: some View {
        Rectangle().fill(KColor.border.opacity(0.7)).frame(height: 1).padding(.leading, SettingsMetrics.rowInset)
    }
}

// MARK: rows

struct SettingsLabel: View {
    let title: String
    var note: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 14, weight: .medium))
            if let note {
                Text(note).font(.system(size: 12)).foregroundStyle(KColor.textMuted)
            }
        }
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct SettingsRowLayout<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 16) {
            leading().frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
        .padding(.horizontal, SettingsMetrics.rowInset)
        .padding(.vertical, 12)
        .frame(minHeight: SettingsMetrics.rowMinHeight)
        .contentShape(Rectangle())
    }
}

struct SettingsRow<Control: View>: View {
    let title: String
    var note: String? = nil
    @ViewBuilder var control: () -> Control

    init(_ title: String, note: String? = nil, @ViewBuilder control: @escaping () -> Control) {
        self.title = title
        self.note = note
        self.control = control
    }

    var body: some View {
        SettingsRowLayout { SettingsLabel(title: title, note: note) } trailing: { control() }
    }
}

/// On or off. The whole row is the switch, so there is nothing small to aim at.
struct SettingsToggle: View {
    let title: String
    var note: String? = nil
    let isOn: Bool
    let set: (Bool) -> Void

    init(_ title: String, note: String? = nil, isOn: Bool, set: @escaping (Bool) -> Void) {
        self.title = title
        self.note = note
        self.isOn = isOn
        self.set = set
    }

    var body: some View {
        Button { set(!isOn) } label: {
            SettingsRowLayout { SettingsLabel(title: title, note: note) } trailing: { SettingsSwitch(on: isOn) }
        }
        .buttonStyle(SettingsPressStyle())
        .accessibilityRepresentation {
            Toggle(title, isOn: Binding(get: { isOn }, set: set)).accessibilityHint(note ?? "")
        }
    }
}

/// Drawn rather than native: the native switch turns gray when the window is inactive,
/// and then on and off look alike.
struct SettingsSwitch: View {
    let on: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(on ? KColor.accent : KColor.surface2)
                .overlay(Capsule().strokeBorder(on ? Color.clear : KColor.borderInput))
            Circle().fill(on ? KColor.onAccent : KColor.textMuted)
                .frame(width: 16, height: 16)
                .offset(x: on ? 20 : 4)
        }
        .frame(width: 40, height: 24)
        .animation(reduceMotion ? nil : KMotion.fast, value: on)
    }
}

/// A few choices in a menu.
struct SettingsChoice<T: Hashable>: View {
    let title: String
    var note: String? = nil
    let options: [T]
    let name: (T) -> String
    let selection: T
    let set: (T) -> Void

    var body: some View {
        SettingsRow(title, note: note) {
            Picker(title, selection: Binding(get: { selection }, set: set)) {
                ForEach(options, id: \.self) { Text(name($0)).tag($0) }
            }
            .pickerStyle(.menu).labelsHidden().controlSize(.large).fixedSize()
        }
    }
}

/// Opens another place.
struct SettingsNavRow: View {
    let title: String
    var note: String? = nil
    var value: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SettingsRowLayout { SettingsLabel(title: title, note: note) } trailing: {
                HStack(spacing: 8) {
                    if let value { Text(value).font(.system(size: 13)).foregroundStyle(KColor.textMuted) }
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(KColor.textMuted)
                }
            }
        }
        .buttonStyle(SettingsPressStyle())
    }
}

/// How something stands right now: symbol, sentence, and at most one action.
struct SettingsStatus<Action: View>: View {
    enum Tone { case good, attention, neutral }
    let tone: Tone
    let title: String
    let note: String
    @ViewBuilder var action: () -> Action

    var body: some View {
        SettingsRowLayout {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 20)).foregroundStyle(color).frame(width: 24)
                    .accessibilityHidden(true)
                SettingsLabel(title: title, note: note)
            }
        } trailing: { action() }
    }

    private var symbol: String {
        switch tone {
        case .good: return "checkmark.circle.fill"
        case .attention: return "exclamationmark.circle.fill"
        case .neutral: return "info.circle"
        }
    }

    private var color: Color {
        switch tone {
        case .good: return KColor.success
        case .attention: return KColor.warning
        case .neutral: return KColor.textMuted
        }
    }
}

struct SettingsPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? KColor.surface2 : Color.clear)
            .contentShape(Rectangle())
    }
}
