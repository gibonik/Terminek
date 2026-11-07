import SwiftUI
import SwiftData

/// Dokument na pełnym ekranie: tło w kolorach karty, karta przechylająca się z telefonem,
/// odliczanie, okrągłe akcje i szczegóły.
struct CardDetailView: View {
    @Bindable var document: Document

    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(NotificationScheduler.reminderHourKey) private var reminderHour = 9
    @State private var confirmDelete = false
    @State private var showingScan = false
    @State private var flip: Double = 0
    @State private var bursts = 0
    @State private var drag: CGFloat = 0

    var body: some View {
        let days = document.daysLeft()
        ZStack(alignment: .top) {
            DT.Palette.background.ignoresSafeArea()

            // Tło z kolorów karty, które gaśnie ku dołowi.
            LiveGradient(colors: document.category.heroGradient)
                .saturation(days < 0 ? 0.5 : 1)
                .frame(height: DT.Size.detailHeader)
                .mask(LinearGradient(colors: [DT.Palette.scrim, DT.Palette.scrim.opacity(0)], startPoint: .top, endPoint: .bottom))
                .opacity(0.9)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: DT.Space.lg) {
                    topBar

                    DocCard(data: CardData(document))
                        .rotation3DEffect(.degrees(flip), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
                        .modifier(TiltCard(active: !reduceMotion))
                        .overlay { RenewBurst(trigger: bursts) }
                        .offset(y: drag)
                        .gesture(
                            DragGesture()
                                .onChanged { drag = max(0, $0.translation.height) }
                                .onEnded { value in
                                    if value.translation.height > DT.Size.card.height / 2 { close() }
                                    withAnimation(DT.Motion.standard) { drag = 0 }
                                }
                        )
                        .padding(.top, DT.Space.xs)

                    titleBlock(days).riseIn(0)
                    actions.riseIn(1)
                    infoPanel.riseIn(2)
                    remindersPanel.riseIn(3)

                    if let data = document.scanImageData, let image = UIImage(data: data) {
                        Button { showingScan = true } label: {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(height: DT.Size.scanPreview)
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: DT.Radius.panel, style: .continuous))
                                .overlay(alignment: .bottomLeading) {
                                    Label("Skan", systemImage: "doc.viewfinder")
                                        .font(DT.Typography.footnoteEmphasized)
                                        .foregroundStyle(DT.Palette.onScrim)
                                        .padding(.horizontal, DT.Space.sm)
                                        .frame(minHeight: DT.Size.pill)
                                        .background(DT.Palette.scrim.opacity(0.5), in: Capsule())
                                        .padding(DT.Space.sm)
                                }
                        }
                        .buttonStyle(CardPressStyle())
                        .accessibilityLabel("Pokaż skan na pełnym ekranie")
                        .riseIn(4)
                    }

                    if !document.notes.isEmpty {
                        VStack(alignment: .leading, spacing: DT.Space.xs) {
                            Text("NOTATKI").font(DT.Typography.overline).kerning(DT.Size.hairline).foregroundStyle(DT.Palette.textSecondary)
                            Text(document.notes).font(DT.Typography.body).foregroundStyle(DT.Palette.textPrimary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(DT.Space.md)
                        .panel()
                        .riseIn(5)
                    }
                }
                .padding(.horizontal, DT.Space.gutter)
                .padding(.bottom, DT.Space.xxl)
            }
            .scrollIndicators(.hidden)
        }
        .foregroundStyle(DT.Palette.textPrimary)
        .onAppear { Tilt.shared.start() }
        .onDisappear { Tilt.shared.stop() }
        .confirmationDialog("Usunąć „\(document.displayTitle)”?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Usuń dokument", role: .destructive) { delete() }
        } message: {
            Text("Dokument i jego przypomnienia znikną.")
        }
        .fullScreenCover(isPresented: $showingScan) {
            ScanViewer(data: document.scanImageData)
        }
        .sheet(item: Binding(get: { router.opened == nil ? nil : router.editor }, set: { router.editor = $0 })) { request in
            DocumentEditView(request: request)
                .environment(router)
        }
    }

    private var topBar: some View {
        HStack {
            RoundIconButton(symbol: "chevron.down", label: "Zamknij") { close() }
            Spacer()
            Text(document.category.group.title.uppercased())
                .font(DT.Typography.overline)
                .kerning(DT.Size.hairline)
                .foregroundStyle(DT.Palette.textSecondary)
            Spacer()
            RoundIconButton(symbol: "square.and.arrow.up", label: "Udostępnij termin") { share() }
        }
        .padding(.top, DT.Space.xs)
    }

    private func titleBlock(_ days: Int) -> some View {
        let head = DaysText.headline(to: document.expiryDate)
        let color: Color = days < 0 ? DT.Palette.danger : days <= 7 ? DT.Palette.warning : DT.Palette.textPrimary
        return VStack(spacing: DT.Space.xxs) {
            Text(document.displayTitle)
                .font(DT.Typography.title)
                .multilineTextAlignment(.center)
            Text(days < 0 ? "Po terminie od" : days == 0 ? "Termin" : "Do terminu")
                .font(DT.Typography.subheadline)
                .foregroundStyle(DT.Palette.textSecondary)
                .padding(.top, DT.Space.xs)
            Text(days == 0 ? "Dziś" : head.big)
                .font(DT.Typography.largeTitle)
                .foregroundStyle(color)
                .contentTransition(.numericText())
            if let rest = head.rest, days != 0 {
                Text("i " + rest)
                    .font(DT.Typography.subheadline)
                    .foregroundStyle(DT.Palette.textSecondary)
                    .contentTransition(.numericText())
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var actions: some View {
        HStack(alignment: .top, spacing: DT.Space.xs) {
            ActionCircle(symbol: "arrow.clockwise", title: "Odnów", prominent: true) { renew() }
            ActionCircle(symbol: "pencil", title: "Edytuj") { router.edit(document) }
            ActionCircle(symbol: document.remindersEnabled ? "bell.fill" : "bell.slash",
                         title: document.remindersEnabled ? "Przypomina" : "Wyciszony") {
                withAnimation(DT.Motion.standard) { document.remindersEnabled.toggle() }
            }
            ActionCircle(symbol: "trash", title: "Usuń", tint: DT.Palette.danger) { confirmDelete = true }
        }
        .sensoryFeedback(.selection, trigger: document.remindersEnabled)
    }

    private var infoPanel: some View {
        VStack(spacing: 0) {
            infoRow(document.category == .subscription ? "Następna płatność" : "Ważny do", PL.date(document.expiryDate))
            divider
            infoRow("Po odnowieniu", PL.date(document.renewedExpiryDate()))
            if document.category == .subscription, let price = document.price {
                divider
                infoRow("Cena", PL.money(price) + " / " + (document.billingCycle ?? .monthly).shortTitle)
            }
            if !document.owner.isEmpty {
                divider
                infoRow(document.category.ownerLabel, document.owner)
            }
            if !document.number.isEmpty {
                divider
                infoRow(document.category.numberLabel, document.number)
            }
        }
        .panel()
    }

    private var remindersPanel: some View {
        let planned = NotificationScheduler.plannedReminders(
            for: [document], hour: reminderHour, now: .now, offsets: NotificationScheduler.enabledOffsets()
        )
        return VStack(alignment: .leading, spacing: DT.Space.sm) {
            Text("PRZYPOMNIENIA").font(DT.Typography.overline).kerning(DT.Size.hairline).foregroundStyle(DT.Palette.textSecondary)
            if !document.remindersEnabled {
                Text("Wyciszone dla tego dokumentu.")
                    .font(DT.Typography.subheadline)
                    .foregroundStyle(DT.Palette.textSecondary)
            } else if planned.isEmpty {
                Text("Wszystkie przypomnienia już minęły.")
                    .font(DT.Typography.subheadline)
                    .foregroundStyle(DT.Palette.textSecondary)
            } else {
                ForEach(Array(planned.prefix(3).enumerated()), id: \.element.identifier) { index, reminder in
                    HStack(spacing: DT.Space.sm) {
                        Image(systemName: index == 0 ? "bell.badge.fill" : "bell")
                            .font(DT.Typography.subheadlineEmphasized)
                            .foregroundStyle(index == 0 ? DT.Palette.accentText : DT.Palette.textSecondary)
                            .frame(width: DT.Size.iconBadge, height: DT.Size.iconBadge)
                            .background((index == 0 ? DT.Palette.accent : DT.Palette.textSecondary).opacity(0.14), in: Circle())
                        VStack(alignment: .leading, spacing: 0) {
                            Text(PL.dayAndMonth(reminder.fireDate))
                                .font(DT.Typography.subheadlineEmphasized)
                            Text(reminder.body)
                                .font(DT.Typography.footnote)
                                .foregroundStyle(DT.Palette.textSecondary)
                                .lineLimit(2)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DT.Space.md)
        .panel()
        .animation(DT.Motion.standard, value: document.remindersEnabled)
    }

    private var divider: some View {
        Rectangle().fill(DT.Palette.separator).frame(height: DT.Size.hairline).padding(.leading, DT.Space.md)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DT.Space.sm) {
            Text(label).font(DT.Typography.subheadline).foregroundStyle(DT.Palette.textSecondary)
            Spacer(minLength: DT.Space.xs)
            Text(value)
                .font(DT.Typography.headline)
                .multilineTextAlignment(.trailing)
                .contentTransition(.numericText())
                .textSelection(.enabled)
        }
        .padding(.horizontal, DT.Space.md)
        .frame(minHeight: DT.Size.toggleRow)
        .accessibilityElement(children: .combine)
    }

    // MARK: Akcje

    private func renew() {
        if !reduceMotion {
            withAnimation(.spring(duration: 0.85, bounce: 0.15)) { flip += 360 }
            Task {
                try? await Task.sleep(for: .milliseconds(380))
                bursts += 1
            }
        }
        router.renew(document)
    }

    private func close() {
        router.close()
        dismiss()
    }

    private func share() {
        let text = "\(document.displayTitle): ważne do \(PL.date(document.expiryDate))"
        let controller = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        top?.present(controller, animated: true)
    }

    private func delete() {
        let doc = document
        router.show("Usunięto „\(doc.displayTitle)”", symbol: "trash.circle.fill")
        close()
        // Usuwamy po zamknięciu ekranu, żeby widok nie czytał już skasowanego obiektu.
        Task {
            try? await Task.sleep(for: .milliseconds(550))
            Haptics.shared.fire(.remove)
            withAnimation(.snappy) { context.delete(doc) }
        }
    }
}

/// Karta lekko pochyla się za przechyleniem telefonu.
struct TiltCard: ViewModifier {
    var active: Bool

    func body(content: Content) -> some View {
        let tilt = Tilt.shared
        content
            .rotation3DEffect(.degrees(active ? tilt.x * 8 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
            .rotation3DEffect(.degrees(active ? -tilt.y * 6 : 0), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
    }
}

/// Skan na pełnym ekranie z przybliżaniem.
struct ScanViewer: View {
    let data: Data?
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1

    var body: some View {
        ZStack(alignment: .topTrailing) {
            DT.Palette.scrim.ignoresSafeArea()
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .gesture(MagnifyGesture().onChanged { scale = max(1, $0.magnification) }
                        .onEnded { _ in withAnimation(.spring) { scale = 1 } })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            RoundIconButton(symbol: "xmark", label: "Zamknij") { dismiss() }
                .padding(DT.Space.gutter)
        }
    }
}
