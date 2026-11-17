import SwiftUI
import KartovCore

/// A new announcement from the developer, as a card in the middle of the window.
struct AnnouncementOverlay: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var center = AnnouncementCenter.shared
    @ObservedObject private var updater = Updater.shared

    var body: some View {
        if let a = center.current, !model.showTutorial, !updater.showSheet, !updater.showWhatsNew {
            ZStack {
                Color.black.opacity(0.45).ignoresSafeArea()
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        Image(systemName: "megaphone.fill").font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(KColor.onAccent)
                            .frame(width: 46, height: 46)
                            .background(Circle().fill(KGradient.accent))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("Duyuru")).font(.system(size: 12, weight: .semibold)).foregroundStyle(KColor.accentSoft)
                            Text(relativeDay(a.date)).font(.system(size: 11)).foregroundStyle(KColor.textMuted)
                        }
                        Spacer()
                        if center.queue.count > 1 {
                            Text(L("{0} duyuru daha", center.queue.count - 1)).font(.system(size: 11, weight: .semibold))
                                .padding(.horizontal, 8).frame(height: 22)
                                .background(Capsule().fill(KColor.surface2))
                                .foregroundStyle(KColor.textMuted)
                        }
                    }
                    Text(a.title).font(.system(size: 19, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    if !a.body.isEmpty {
                        Text(notesText(a.body)).font(.system(size: 13)).foregroundStyle(KColor.text.opacity(0.9))
                            .textSelection(.enabled)
                            .lineLimit(14)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack(spacing: 10) {
                        Text(L("Gözetim'deki uyarılarda da durur."))
                            .font(.system(size: 11)).foregroundStyle(KColor.textMuted)
                        Spacer()
                        if a.url != nil {
                            Button(L("Tamam")) { center.dismiss() }.buttonStyle(SecondaryButtonStyle())
                            Button(L("Aç")) { center.openLink() }
                                .buttonStyle(PrimaryButtonStyle())
                                .keyboardShortcut(.defaultAction)
                        } else {
                            Button(L("Tamam")) { center.dismiss() }
                                .buttonStyle(PrimaryButtonStyle())
                                .keyboardShortcut(.defaultAction)
                        }
                    }
                }
                .padding(24)
                .frame(width: 460)
                .kCard(padding: 0, radius: 20)
                .fixedSize()
                .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
                .id(a.id)
                .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
        }
    }
}
