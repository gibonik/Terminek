import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(AppLock.self) private var lock
    @Query private var documents: [Document]
    @AppStorage(Haptics.enabledKey) private var haptics = true
    @AppStorage(AppAppearance.key) private var appearance = AppAppearance.system.rawValue
    @Namespace private var themePill

    var body: some View {
        @Bindable var lock = lock
        ScrollView {
            VStack(alignment: .leading, spacing: DT.Space.gutter) {
                Text("Ustawienia")
                    .font(DT.Typography.largeTitle)
                    .padding(.horizontal, DT.Space.xxs)

                VStack(alignment: .leading, spacing: DT.Space.xs) {
                    Toggle(isOn: $lock.isEnabled) {
                        row("faceid", "Zamek \(lock.biometryName)")
                    }
                    .tint(DT.Palette.accent)
                    .padding(.horizontal, DT.Space.md)
                    .frame(minHeight: DT.Size.row)
                    .walletPanel()
                    Text("Portfel zamknie się, gdy wyjdziesz z aplikacji.")
                        .font(DT.Typography.footnote)
                        .foregroundStyle(DT.Palette.textSecondary)
                        .padding(.horizontal, DT.Space.xs)
                }
                .riseIn(0)

                VStack(alignment: .leading, spacing: DT.Space.xs) {
                    HStack(spacing: DT.Space.xxs) {
                        ForEach(AppAppearance.allCases) { option in
                            let isOn = appearance == option.rawValue
                            Button {
                                withAnimation(DT.Motion.standard) { appearance = option.rawValue }
                            } label: {
                                Text(option.title)
                                    .font(DT.Typography.subheadlineEmphasized)
                                    .foregroundStyle(isOn ? DT.Palette.onAccent : DT.Palette.textPrimary)
                                    .frame(maxWidth: .infinity, minHeight: DT.Size.touch)
                                    .background {
                                        if isOn {
                                            Capsule().fill(DT.Palette.accent)
                                                .matchedGeometryEffect(id: "theme", in: themePill)
                                        }
                                    }
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(CardPressStyle())
                            .accessibilityAddTraits(isOn ? .isSelected : [])
                        }
                    }
                    .padding(DT.Space.xxs)
                    .walletCapsule()
                    Text("Wygląd portfela: jasna albo ciemna skóra.")
                        .font(DT.Typography.footnote)
                        .foregroundStyle(DT.Palette.textSecondary)
                        .padding(.horizontal, DT.Space.xs)
                }
                .riseIn(1)

                VStack(alignment: .leading, spacing: DT.Space.xs) {
                    Toggle(isOn: $haptics) {
                        row("iphone.radiowaves.left.and.right", "Wibracje")
                    }
                    .tint(DT.Palette.accent)
                    .padding(.horizontal, DT.Space.md)
                    .frame(minHeight: DT.Size.row)
                    .walletPanel()
                    .onChange(of: haptics) { _, on in
                        if on { Haptics.shared.fire(.stow) }
                    }
                    Text("Telefon delikatnie stuknie, gdy wyjmujesz kartę, odnawiasz dokument albo wkładasz nowy.")
                        .font(DT.Typography.footnote)
                        .foregroundStyle(DT.Palette.textSecondary)
                        .padding(.horizontal, DT.Space.xs)
                }
                .riseIn(2)

                VStack(alignment: .leading, spacing: DT.Space.xs) {
                    VStack(spacing: 0) {
                        HStack {
                            row("wallet.pass", "W portfelu")
                            Spacer()
                            Text(documents.count == 1 ? "1 dokument" : "\(documents.count) dokumentów")
                                .font(DT.Typography.headline)
                                .foregroundStyle(DT.Palette.textSecondary)
                        }
                        .padding(.horizontal, DT.Space.md)
                        .frame(minHeight: DT.Size.row)
                        Rectangle().fill(DT.Palette.separator).frame(height: DT.Size.hairline).padding(.leading, DT.Space.md * 2 + DT.Size.iconColumn)
                        HStack {
                            row(TerminyApp.usesCloudKit ? "icloud" : "iphone", "Zapis")
                            Spacer()
                            Text(TerminyApp.usesCloudKit ? "iCloud" : "Tylko ten iPhone")
                                .font(DT.Typography.headline)
                                .foregroundStyle(DT.Palette.textSecondary)
                        }
                        .padding(.horizontal, DT.Space.md)
                        .frame(minHeight: DT.Size.row)
                    }
                    .walletPanel()
                    Text(TerminyApp.usesCloudKit
                         ? "Dokumenty są w Twoim prywatnym iCloud i synchronizują się między urządzeniami."
                         : "Dokumenty są zapisane tylko na tym iPhonie, bo aplikacja jest wgrana bez iCloud.")
                        .font(DT.Typography.footnote)
                        .foregroundStyle(DT.Palette.textSecondary)
                        .padding(.horizontal, DT.Space.xs)
                }
                .riseIn(3)

                VStack(spacing: DT.Space.xs) {
                    Image(systemName: "wallet.pass.fill")
                        .font(DT.Typography.title2)
                        .foregroundStyle(DT.Palette.accentText)
                    Text("Terminy").font(DT.Typography.headline)
                    Text("Wersja \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                        .font(DT.Typography.footnote)
                        .foregroundStyle(DT.Palette.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, DT.Space.lg)
                .riseIn(4)
            }
            .padding(.horizontal, DT.Space.gutter)
            .padding(.top, DT.Space.xs)
            .padding(.bottom, DT.Space.dockClearance)
        }
        .scrollIndicators(.hidden)
    }

    private func row(_ symbol: String, _ title: String) -> some View {
        HStack(spacing: DT.Space.md) {
            Image(systemName: symbol)
                .font(DT.Typography.icon)
                .foregroundStyle(DT.Palette.accentText)
                .frame(width: DT.Size.iconColumn)
            Text(title).font(DT.Typography.headline).foregroundStyle(DT.Palette.textPrimary)
        }
    }
}
