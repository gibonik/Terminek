import SwiftUI
import SwiftData
import PDFKit
import EventKit
import EventKitUI

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
    @State private var editingOffsets = false
    @State private var addingToCalendar = false
    @State private var paywall: PaywallReason?

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
                                    Label(document.scanPageCount > 1 ? "Skan · \(PL.pages(document.scanPageCount))" : "Skan",
                                          systemImage: "doc.viewfinder")
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
        .sheet(isPresented: $editingOffsets, onDismiss: reschedule) {
            ReminderOffsetsSheet(document: document)
        }
        .sheet(isPresented: $addingToCalendar) {
            CalendarEventSheet(document: document) { saved in
                addingToCalendar = false
                if saved { router.show("Dodano do Kalendarza", symbol: "calendar.badge.checkmark") }
            }
            .ignoresSafeArea()
        }
        .sheet(item: $paywall) { PaywallView(reason: $0) }
        .fullScreenCover(isPresented: $showingScan) {
            ScanViewer(pdf: document.scanPDFData, image: document.scanImageData, title: document.displayTitle)
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
            HStack {
                Text("PRZYPOMNIENIA").font(DT.Typography.overline).kerning(DT.Size.hairline).foregroundStyle(DT.Palette.textSecondary)
                if document.customOffsets != nil {
                    Text("WŁASNE").font(DT.Typography.overline).foregroundStyle(DT.Palette.accentText)
                }
                Spacer()
                Button("Zmień") {
                    if Store.shared.isPlus { editingOffsets = true } else { paywall = .reminders }
                }
                .font(DT.Typography.subheadlineEmphasized)
                .foregroundStyle(DT.Palette.accentText)
                .frame(minHeight: DT.Size.touch)
            }
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
            Button {
                if Store.shared.isPlus { addingToCalendar = true } else { paywall = .calendar }
            } label: {
                Label("Dodaj do Kalendarza", systemImage: "calendar.badge.plus")
                    .font(DT.Typography.subheadlineEmphasized)
                    .foregroundStyle(DT.Palette.accentText)
                    .frame(maxWidth: .infinity, minHeight: DT.Size.touch)
                    .background(DT.Palette.surfaceRaised, in: Capsule())
            }
            .buttonStyle(CardPressStyle())
            .padding(.top, DT.Space.xxs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DT.Space.md)
        .panel()
        .animation(DT.Motion.standard, value: document.remindersEnabled)
    }

    private func reschedule() {
        let context = self.context
        Task {
            let all = (try? context.fetch(FetchDescriptor<Document>())) ?? []
            await NotificationScheduler.shared.reschedule(all)
        }
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

/// Skan na pełnym ekranie: wszystkie strony z PDF-a (przewijanie i przybliżanie),
/// a dla starszych dokumentów samo zdjęcie. Można go udostępnić jako PDF.
struct ScanViewer: View {
    let pdf: Data?
    let image: Data?
    let title: String
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var shareFile: URL?

    var body: some View {
        ZStack(alignment: .top) {
            DT.Palette.scrim.ignoresSafeArea()
            if let pdf, ScanStore.pageCount(of: pdf) > 0 {
                PDFPages(data: pdf).ignoresSafeArea(edges: .bottom)
            } else if let image, let uiImage = UIImage(data: image) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .gesture(MagnifyGesture().onChanged { scale = max(1, $0.magnification) }
                        .onEnded { _ in withAnimation(.spring) { scale = 1 } })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack {
                if let file = shareFile {
                    ShareLink(item: file) {
                        Image(systemName: "square.and.arrow.up")
                            .font(DT.Typography.headline)
                            .foregroundStyle(DT.Palette.onScrim)
                            .frame(width: DT.Size.touch, height: DT.Size.touch)
                            .background(DT.Palette.scrim.opacity(0.55), in: Circle())
                    }
                    .accessibilityLabel("Udostępnij skan jako PDF")
                }
                Spacer()
                RoundIconButton(symbol: "xmark", label: "Zamknij") { dismiss() }
            }
            .padding(.horizontal, DT.Space.gutter)
            .padding(.top, DT.Space.xs)
        }
        .task { shareFile = makeShareFile() }
    }

    /// PDF do udostępnienia zapisany tymczasowo pod czytelną nazwą.
    private func makeShareFile() -> URL? {
        guard let pdf else { return nil }
        let name = title.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).pdf")
        do {
            try pdf.write(to: url, options: [.atomic, .completeFileProtection])
            return url
        } catch {
            return nil
        }
    }
}

/// Strony PDF-a jedna pod drugą, z przybliżaniem.
struct PDFPages: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .clear
        view.pageShadowsEnabled = false
        view.document = PDFDocument(data: data)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {}
}

/// Wybór własnych terminów przypomnień dla jednego dokumentu.
struct ReminderOffsetsSheet: View {
    @Bindable var document: Document
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<Int> = []

    static let options = [90, 60, 30, 14, 7, 3, 1, 0]

    var body: some View {
        VStack(alignment: .leading, spacing: DT.Space.lg) {
            HStack {
                Text("Kiedy przypominać?").font(DT.Typography.title3)
                Spacer()
                RoundIconButton(symbol: "xmark", label: "Zamknij") { dismiss() }
            }
            Text("Wybierz dowolne dni przed terminem „\(document.displayTitle)”. Przypomnienie przyjdzie o godzinie z ustawień.")
                .font(DT.Typography.subheadline)
                .foregroundStyle(DT.Palette.textSecondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: DT.Size.tile), spacing: DT.Space.xs)], spacing: DT.Space.xs) {
                ForEach(Self.options, id: \.self) { days in
                    let isOn = selected.contains(days)
                    Button {
                        withAnimation(DT.Motion.press) {
                            if isOn { selected.remove(days) } else { selected.insert(days) }
                        }
                    } label: {
                        Text(label(days))
                            .font(DT.Typography.subheadlineEmphasized)
                            .foregroundStyle(isOn ? DT.Palette.onAccent : DT.Palette.textPrimary)
                            .frame(maxWidth: .infinity, minHeight: DT.Size.pill)
                            .background(isOn ? DT.Palette.accent : DT.Palette.surfaceRaised, in: Capsule())
                    }
                    .buttonStyle(CardPressStyle())
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
            Spacer()
            PrimaryButton(title: "Zapisz", symbol: "checkmark") {
                document.customOffsets = selected.isEmpty ? nil : Array(selected)
                dismiss()
            }
            .disabled(selected.isEmpty)
            .opacity(selected.isEmpty ? 0.5 : 1)
            Button("Jak w ustawieniach") {
                document.customOffsets = nil
                dismiss()
            }
            .font(DT.Typography.subheadlineEmphasized)
            .foregroundStyle(DT.Palette.accentText)
            .frame(maxWidth: .infinity, minHeight: DT.Size.touch)
        }
        .padding(DT.Space.gutter)
        .background(AppBackground())
        .foregroundStyle(DT.Palette.textPrimary)
        .presentationDetents([.medium, .large])
        .onAppear {
            selected = Set(document.customOffsets ?? NotificationScheduler.enabledOffsets())
        }
    }

    private func label(_ days: Int) -> String {
        switch days {
        case 0: "W dniu"
        case 1: "Dzień przed"
        default: "\(days) dni"
        }
    }
}

/// Systemowy formularz nowego wydarzenia w Kalendarzu, wypełniony terminem dokumentu.
/// Nie wymaga zgody na dostęp do kalendarza: użytkownik sam zatwierdza dodanie.
struct CalendarEventSheet: UIViewControllerRepresentable {
    let document: Document
    let onFinish: (Bool) -> Void

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        let isSub = document.category == .subscription
        event.title = (isSub ? "Płatność: " : "Koniec ważności: ") + document.displayTitle
        event.isAllDay = true
        event.startDate = Calendar.current.startOfDay(for: document.expiryDate)
        event.endDate = event.startDate
        event.notes = "Dodane z aplikacji Terminek."
        // Alarmy: tydzień wcześniej i rano w dniu terminu (wydarzenie całodniowe zaczyna się o północy).
        event.alarms = [EKAlarm(relativeOffset: -7 * 24 * 3600 + 9 * 3600), EKAlarm(relativeOffset: 9 * 3600)]
        let controller = EKEventEditViewController()
        controller.eventStore = store
        controller.event = event
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let onFinish: (Bool) -> Void
        init(onFinish: @escaping (Bool) -> Void) { self.onFinish = onFinish }

        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            onFinish(action == .saved)
        }
    }
}
