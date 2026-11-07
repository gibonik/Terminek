import SwiftUI
import StoreKit

/// Ekran Terminek Plus: korzyści, trzy plany (rok z okresem próbnym, miesiąc, na zawsze),
/// przywracanie zakupów i wymagane przez Apple informacje o odnawianiu.
struct PaywallView: View {
    let reason: PaywallReason
    @Environment(\.dismiss) private var dismiss
    @State private var selected = Store.yearlyID
    @State private var legal: LegalDocument?
    private var store: Store { .shared }

    private struct Plan: Identifiable {
        let id: String
        let title: String
        let fallbackPrice: String
        let note: String
    }

    private let plans = [
        Plan(id: Store.yearlyID, title: "Rok", fallbackPrice: "69,99 zł", note: "7 dni za darmo, potem ok. 5,83 zł miesięcznie"),
        Plan(id: Store.monthlyID, title: "Miesiąc", fallbackPrice: "9,99 zł", note: "Anulujesz, kiedy chcesz"),
        Plan(id: Store.lifetimeID, title: "Na zawsze", fallbackPrice: "199,99 zł", note: "Jedna płatność, bez abonamentu"),
    ]

    private let benefits: [(symbol: String, title: String, detail: String)] = [
        ("rectangle.stack.badge.plus", "Dokumenty bez limitu", "Cała rodzina, wszystkie auta i subskrypcje"),
        ("doc.on.doc", "Skany wielostronicowe", "Cała polisa w jednym PDF-ie, do wysłania jednym ruchem"),
        ("sparkles", "Asystent bez limitu", "Pytaj o terminy, ile chcesz"),
        ("icloud", "Kopia w iCloud", "Te same dokumenty na każdym Twoim iPhonie"),
    ]

    var body: some View {
        ZStack(alignment: .top) {
            DT.Palette.background.ignoresSafeArea()
            LiveGradient(colors: [DT.Palette.accent, DT.Palette.accentAlt, DT.Palette.accent])
                .frame(height: DT.Size.detailHeader)
                .mask(LinearGradient(colors: [DT.Palette.scrim, DT.Palette.scrim.opacity(0)], startPoint: .top, endPoint: .bottom))
                .opacity(0.7)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: DT.Space.lg) {
                    HStack {
                        Spacer()
                        RoundIconButton(symbol: "xmark", label: "Zamknij") { dismiss() }
                    }

                    VStack(spacing: DT.Space.sm) {
                        LogoMark(size: DT.Size.lockBadge)
                            .shadow(color: DT.Palette.accent.opacity(0.5), radius: DT.Space.lg)
                        Text("Terminek Plus").font(DT.Typography.largeTitle)
                        Text(reason.headline)
                            .font(DT.Typography.body)
                            .foregroundStyle(DT.Palette.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .riseIn(0)

                    VStack(alignment: .leading, spacing: DT.Space.md) {
                        ForEach(benefits, id: \.title) { item in
                            HStack(spacing: DT.Space.sm) {
                                Image(systemName: item.symbol)
                                    .font(DT.Typography.subheadlineEmphasized)
                                    .foregroundStyle(DT.Palette.onAccent)
                                    .frame(width: DT.Size.iconBadge, height: DT.Size.iconBadge)
                                    .background(DT.Palette.accent, in: Circle())
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(item.title).font(DT.Typography.headline)
                                    Text(item.detail).font(DT.Typography.footnote).foregroundStyle(DT.Palette.textSecondary)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DT.Space.md)
                    .panel()
                    .riseIn(1)

                    VStack(spacing: DT.Space.sm) {
                        ForEach(plans) { plan in planCard(plan) }
                    }
                    .riseIn(2)

                    if store.loaded && store.products.isEmpty {
                        Label("Zakupy działają w wersji z App Store. W tej wersji testowej Plus włączysz w Koncie, w menu deweloperskim.",
                              systemImage: "info.circle")
                            .font(DT.Typography.footnote)
                            .foregroundStyle(DT.Palette.textSecondary)
                    }
                    if let message = store.message {
                        Text(message)
                            .font(DT.Typography.footnote)
                            .foregroundStyle(DT.Palette.warning)
                    }

                    Text("Subskrypcja odnawia się automatycznie, dopóki nie anulujesz jej co najmniej 24 godziny przed końcem okresu (Ustawienia › Twoje imię › Subskrypcje). Płatność pobiera Apple z Twojego konta Apple ID. Okres próbny dotyczy tylko planu rocznego, a jego niewykorzystana część przepada po zakupie.")
                        .font(DT.Typography.caption)
                        .foregroundStyle(DT.Palette.textTertiary)
                        .multilineTextAlignment(.center)

                    HStack(spacing: DT.Space.md) {
                        Button("Przywróć zakupy") { Task { await store.restore() } }
                        Button("Regulamin") { legal = .terms }
                        Button("Prywatność") { legal = .privacy }
                    }
                    .font(DT.Typography.footnoteEmphasized)
                    .foregroundStyle(DT.Palette.accentText)
                    .frame(minHeight: DT.Size.touch)
                }
                .padding(.horizontal, DT.Space.gutter)
                .padding(.top, DT.Space.md)
                .padding(.bottom, DT.Space.xxl + DT.Size.button)
            }
            .scrollIndicators(.hidden)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: DT.Space.xxs) {
                PrimaryButton(title: ctaTitle, symbol: store.busy ? nil : "sparkles") { buy() }
                    .disabled(store.busy || store.product(selected) == nil)
                    .opacity(store.product(selected) == nil ? 0.5 : 1)
            }
            .padding(.horizontal, DT.Space.gutter)
            .padding(.bottom, DT.Space.xs)
            .background(
                LinearGradient(colors: [DT.Palette.background.opacity(0), DT.Palette.background], startPoint: .top, endPoint: .center)
                    .ignoresSafeArea()
            )
        }
        .foregroundStyle(DT.Palette.textPrimary)
        .onAppear { store.message = nil }
        .sheet(item: $legal) { LegalView(document: $0) }
        .onChange(of: store.isPlus) { _, plus in if plus { dismiss() } }
    }

    private var ctaTitle: String {
        if store.busy { return "Chwila…" }
        guard let product = store.product(selected) else { return "Niedostępne w tej wersji" }
        if product.subscription?.introductoryOffer?.paymentMode == .freeTrial { return "Wypróbuj 7 dni za darmo" }
        return "Kup za \(product.displayPrice)"
    }

    private func planCard(_ plan: Plan) -> some View {
        let isOn = selected == plan.id
        let price = store.product(plan.id)?.displayPrice ?? plan.fallbackPrice
        return Button {
            withAnimation(DT.Motion.press) { selected = plan.id }
        } label: {
            HStack(spacing: DT.Space.sm) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(DT.Typography.title3)
                    .foregroundStyle(isOn ? DT.Palette.accent : DT.Palette.textTertiary)
                VStack(alignment: .leading, spacing: DT.Space.xxs) {
                    HStack(spacing: DT.Space.xs) {
                        Text(plan.title).font(DT.Typography.headline)
                        if plan.id == Store.yearlyID {
                            Text("NAJTANIEJ")
                                .font(DT.Typography.overline)
                                .foregroundStyle(DT.Palette.onAccent)
                                .padding(.horizontal, DT.Space.xs)
                                .padding(.vertical, DT.Space.xxs)
                                .background(DT.Palette.accent, in: Capsule())
                        }
                    }
                    Text(plan.note).font(DT.Typography.footnote).foregroundStyle(DT.Palette.textSecondary)
                }
                Spacer(minLength: DT.Space.xs)
                Text(price).font(DT.Typography.headline).monospacedDigit()
            }
            .padding(DT.Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .panel()
            .overlay {
                RoundedRectangle(cornerRadius: DT.Radius.panel, style: .continuous)
                    .strokeBorder(DT.Palette.accent.opacity(isOn ? 1 : 0), lineWidth: DT.Size.hairline * 2)
            }
        }
        .buttonStyle(CardPressStyle())
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func buy() {
        guard let product = store.product(selected) else { return }
        Task {
            if await store.buy(product) {
                Haptics.shared.fire(.renew)
                dismiss()
            }
        }
    }
}
