import SwiftUI
import SwiftData
import UserNotifications

/// Czat z asystentem: pytania o terminy, odpowiedzi z kartami dokumentów.
struct AssistantView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppLock.self) private var lock
    @Query(sort: \Document.expiryDate) private var documents: [Document]
    @AppStorage(NotificationScheduler.reminderHourKey) private var reminderHour = 9
    @State private var notificationsAllowed: Bool?

    struct Message: Identifiable, Equatable {
        let id = UUID()
        let fromUser: Bool
        let text: String
        var documentIDs: [UUID] = []
        var actions: [Assistant.Action] = []
        var upsell = false
    }

    @State private var messages: [Message] = []
    @State private var draft = ""
    @State private var thinking = false
    @FocusState private var inputFocused: Bool
    @State private var paywall: PaywallReason?

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: DT.Space.sm) {
                        ForEach(messages) { message in
                            bubble(message)
                                .id(message.id)
                                .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
                        }
                        if thinking {
                            TypingDots()
                                .padding(.horizontal, DT.Space.md)
                                .frame(height: DT.Size.pill)
                                .background(DT.Palette.surfaceRaised, in: Capsule())
                                .id("typing")
                                .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, DT.Space.gutter)
                    .padding(.vertical, DT.Space.md)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messages.count) {
                    withAnimation(DT.Motion.standard) { proxy.scrollTo(messages.last?.id, anchor: .bottom) }
                }
                .onChange(of: thinking) {
                    if thinking { withAnimation(DT.Motion.standard) { proxy.scrollTo("typing", anchor: .bottom) } }
                }
            }
            suggestions
            inputBar
        }
        .background(AppBackground())
        .foregroundStyle(DT.Palette.textPrimary)
        .sheet(item: $paywall) { reason in PaywallView(reason: reason) }
        .onAppear {
            if messages.isEmpty {
                messages = [Message(fromUser: false, text: greeting)]
            }
        }
        .task {
            let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            notificationsAllowed = status == .notDetermined ? nil : (status == .authorized || status == .provisional)
        }
    }

    private var topBar: some View {
        HStack(spacing: DT.Space.sm) {
            ZStack {
                Circle().fill(LinearGradient(colors: [DT.Palette.accent, DT.Palette.accentAlt], startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "sparkles").font(DT.Typography.headline).foregroundStyle(DT.Palette.onAccent)
            }
            .frame(width: DT.Size.avatar, height: DT.Size.avatar)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text("Asystent").font(DT.Typography.headline)
                Text(subtitle).font(DT.Typography.caption).foregroundStyle(DT.Palette.textSecondary)
            }
            Spacer()
            RoundIconButton(symbol: "xmark", label: "Zamknij") { dismiss() }
        }
        .padding(.horizontal, DT.Space.gutter)
        .padding(.top, DT.Space.md)
        .padding(.bottom, DT.Space.xs)
    }

    // MARK: Dymki

    @ViewBuilder
    private func bubble(_ message: Message) -> some View {
        if message.fromUser {
            HStack {
                Spacer(minLength: DT.Space.xxl)
                Text(message.text)
                    .font(DT.Typography.body)
                    .foregroundStyle(DT.Palette.onAccent)
                    .padding(.horizontal, DT.Space.md)
                    .padding(.vertical, DT.Space.sm)
                    .background(DT.Palette.accent, in: RoundedRectangle(cornerRadius: DT.Radius.panel, style: .continuous))
            }
        } else {
            VStack(alignment: .leading, spacing: DT.Space.sm) {
                Text(message.text)
                    .font(DT.Typography.body)
                    .fixedSize(horizontal: false, vertical: true)
                let docs = message.documentIDs.compactMap { id in documents.first { $0.id == id } }
                if !docs.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(docs.enumerated()), id: \.element.id) { index, doc in
                            if index > 0 {
                                Rectangle().fill(DT.Palette.separator).frame(height: DT.Size.hairline)
                            }
                            Button { open(doc) } label: { DocRow(document: doc) }
                                .buttonStyle(CardPressStyle())
                        }
                    }
                    .background(DT.Palette.surfaceRaised, in: RoundedRectangle(cornerRadius: DT.Radius.card, style: .continuous))
                    .clipShape(RoundedRectangle(cornerRadius: DT.Radius.card, style: .continuous))
                }
                if !message.actions.isEmpty {
                    FlowChips(actions: message.actions, documents: documents) { perform($0) }
                }
                if message.upsell {
                    PrimaryButton(title: "Odblokuj Plus", symbol: "sparkles") { paywall = .assistant }
                }
            }
            .padding(DT.Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .panel()
            .padding(.trailing, DT.Space.lg)
        }
    }

    // MARK: Podpowiedzi i pole

    private var suggestionList: [String] {
        var list: [String] = []
        guard !documents.isEmpty else {
            return ["Jak dodać dokument?", "Jak zeskanować dokument?", "Jakie dokumenty mogę dodać?", "Czy moje dane są bezpieczne?", "Co umiesz?"]
        }
        list.append("Podsumuj moje dokumenty")
        if documents.contains(where: { $0.category == .carInsurance }) { list.append("Kiedy kończy się OC?") }
        list.append("Co mam w tym tygodniu?")
        list.append("Co wygasa w ciągu 30 dni?")
        if documents.contains(where: { $0.daysLeft() < 0 }) { list.append("Co jest po terminie?") }
        if documents.contains(where: { $0.category == .subscription }) { list.append("Ile płacę za subskrypcje?") }
        if documents.contains(where: { $0.category == .idCard }) { list.append("Jak odnowić dowód?") }
        if documents.contains(where: { $0.category == .passport }) { list.append("Kiedy paszport?") }
        list.append("Czego mi brakuje?")
        list.append("Jak zrobić kopię zapasową?")
        list.append("Co umiesz?")
        return list
    }

    private var suggestions: some View {
        ScrollView(.horizontal) {
            HStack(spacing: DT.Space.xs) {
                ForEach(suggestionList, id: \.self) { text in
                    Button { ask(text) } label: {
                        Text(text)
                            .font(DT.Typography.subheadlineEmphasized)
                            .lineLimit(1)
                            .foregroundStyle(DT.Palette.textPrimary)
                            .padding(.horizontal, DT.Space.md)
                            .frame(minHeight: DT.Size.pill)
                            .background(DT.Palette.surfaceRaised, in: Capsule())
                    }
                    .buttonStyle(CardPressStyle())
                }
            }
        }
        .contentMargins(.horizontal, DT.Space.gutter, for: .scrollContent)
        .scrollIndicators(.hidden)
        .padding(.vertical, DT.Space.xs)
    }

    private var inputBar: some View {
        HStack(spacing: DT.Space.xs) {
            TextField("", text: $draft, prompt: Text("Zapytaj o termin…").foregroundStyle(DT.Palette.textTertiary), axis: .vertical)
                .lineLimit(1...4)
                .font(DT.Typography.body)
                .focused($inputFocused)
                .submitLabel(.send)
                .onSubmit { ask(draft) }
                .padding(.horizontal, DT.Space.md)
                .padding(.vertical, DT.Space.sm)
                .frame(minHeight: DT.Size.field)
                .panelCapsule()
            Button { ask(draft) } label: {
                Image(systemName: "arrow.up")
                    .font(DT.Typography.headline)
                    .foregroundStyle(DT.Palette.onAccent)
                    .frame(width: DT.Size.field, height: DT.Size.field)
                    .background(canSend ? DT.Palette.accent : DT.Palette.textTertiary, in: Circle())
            }
            .disabled(!canSend)
            .accessibilityLabel("Wyślij")
        }
        .padding(.horizontal, DT.Space.gutter)
        .padding(.bottom, DT.Space.xs)
    }

    private var subtitle: String {
        let left = Store.shared.assistantQuestionsLeft()
        guard left != Int.max else { return "Działa bez internetu" }
        return left == 0 ? "Dziś bez darmowych pytań" : "Darmowe pytania dziś: \(left)"
    }

    private var canSend: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !thinking }

    // MARK: Logika

    private func ask(_ question: String) {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !thinking else { return }
        draft = ""
        Haptics.shared.fire(.pull)
        withAnimation(DT.Motion.standard) {
            messages.append(Message(fromUser: true, text: text))
            thinking = true
        }
        let store = Store.shared
        guard store.assistantQuestionsLeft() > 0 else {
            Task {
                try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 300))
                withAnimation(DT.Motion.standard) {
                    thinking = false
                    messages.append(Message(fromUser: false,
                                            text: "W darmowym planie możesz zadać \(Store.freeAssistantPerDay) pytania dziennie. Jutro limit się odnowi, a z Plus pytasz bez ograniczeń.",
                                            upsell: true))
                }
            }
            return
        }
        store.recordAssistantQuestion()
        let reply = Assistant(state: appState).answer(text, documents: documents)
        Breadcrumbs.add("Asystent: pytanie (\(reply.actions.count) akcji, \(reply.documentIDs.count) dok.)")
        Task {
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 450))
            withAnimation(DT.Motion.standard) {
                thinking = false
                messages.append(Message(fromUser: false, text: reply.text, documentIDs: reply.documentIDs, actions: reply.actions))
            }
        }
    }

    private var appState: Assistant.AppState {
        Assistant.AppState(
            isPlus: Store.shared.isPlus,
            questionsLeft: Store.shared.isPlus ? nil : Store.shared.assistantQuestionsLeft(),
            usesCloud: TerminyApp.usesCloudKit,
            lockEnabled: lock.isEnabled,
            biometry: lock.biometryName,
            reminderHour: reminderHour,
            offsets: NotificationScheduler.enabledOffsets(),
            lastBackup: UserDefaults.standard.object(forKey: BackupSheet.lastBackupKey) as? Date,
            notificationsAllowed: notificationsAllowed
        )
    }

    /// Pierwsza wiadomość: od razu z tym, co najważniejsze.
    private var greeting: String {
        let expired = documents.filter { $0.daysLeft() < 0 }.count
        let week = documents.filter { (0...7).contains($0.daysLeft()) }.count
        var text = "Cześć! Znam Twoje terminy i całą aplikację."
        if documents.isEmpty {
            text += " Na razie nie masz dokumentów. Zapytaj, jak dodać pierwszy."
        } else if expired > 0 {
            text += " Uwaga: \(Assistant.documentsCount(expired)) po terminie."
        } else if week > 0 {
            text += " W tym tygodniu kończy się: \(Assistant.documentsCount(week))."
        } else {
            text += " W tym tygodniu nic się nie kończy."
        }
        return text + " Wszystko liczę na telefonie, nic nie wysyłam."
    }

    /// Przycisk z odpowiedzi: pytanie od razu, reszta zamyka czat i przechodzi we właściwe miejsce.
    private func perform(_ action: Assistant.Action) {
        switch action {
        case .ask(let question):
            ask(question)
        case .open(let id):
            if let doc = documents.first(where: { $0.id == id }) { open(doc) }
        case .renew(let id):
            guard let doc = documents.first(where: { $0.id == id }) else { return }
            router.renew(doc)
            withAnimation(DT.Motion.standard) {
                messages.append(Message(fromUser: false, text: "Gotowe: „\(doc.displayTitle)” jest ważne do \(PL.date(doc.expiryDate)). Gdyby to była pomyłka, zmienisz datę w edycji.",
                                        documentIDs: [doc.id]))
            }
        case .plus:
            paywall = .manual
        default:
            dismiss()
            Task {
                try? await Task.sleep(for: .milliseconds(350))
                switch action {
                case .add(let category): router.add(category)
                case .scan: router.add(scan: true)
                case .backup, .settings: router.tab = .account
                case .siriHelp:
                    router.tab = .account
                    router.showShortcutsHelp = true
                case .report: BugReportPresenter.present(BugReportRequest())
                default: break
                }
            }
        }
    }

    private func open(_ doc: Document) {
        dismiss()
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            router.open(doc, from: "assistant")
        }
    }
}

/// Trzy kropki „asystent pisze”.
private struct TypingDots: View {
    @State private var phase = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: DT.Space.xxs) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(DT.Palette.textSecondary)
                    .frame(width: DT.Space.xs, height: DT.Space.xs)
                    .opacity(phase ? 1 : 0.3)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.5).repeatForever().delay(Double(i) * 0.15), value: phase)
            }
        }
        .onAppear { phase = true }
        .accessibilityLabel("Asystent pisze")
    }
}

/// Przyciski pod odpowiedzią asystenta, zawijane do kolejnych wierszy.
private struct FlowChips: View {
    let actions: [Assistant.Action]
    let documents: [Document]
    let onTap: (Assistant.Action) -> Void

    var body: some View {
        FlowLayout(spacing: DT.Space.xs) {
            ForEach(actions, id: \.self) { action in
                Button { onTap(action) } label: {
                    Label(title(action), systemImage: action.symbol)
                        .font(DT.Typography.footnoteEmphasized)
                        .lineLimit(1)
                        .foregroundStyle(prominent(action) ? DT.Palette.onAccent : DT.Palette.accentText)
                        .padding(.horizontal, DT.Space.sm)
                        .frame(minHeight: DT.Size.pill)
                        .background(prominent(action) ? DT.Palette.accent : DT.Palette.accent.opacity(0.12), in: Capsule())
                }
                .buttonStyle(CardPressStyle())
            }
        }
    }

    private func prominent(_ action: Assistant.Action) -> Bool {
        if case .ask = action { return false }
        return true
    }

    /// „Odnów” i „Otwórz” z nazwą dokumentu, żeby było wiadomo, czego dotyczą.
    private func title(_ action: Assistant.Action) -> String {
        switch action {
        case .renew(let id):
            guard let doc = documents.first(where: { $0.id == id }) else { return action.title }
            return "Odnów do \(PL.numeric(doc.renewedExpiryDate()))"
        case .open(let id):
            return documents.first(where: { $0.id == id }).map { "Otwórz \($0.displayTitle)" } ?? action.title
        default:
            return action.title
        }
    }
}

/// Prosty układ „zawijany”: elementy obok siebie, a gdy brak miejsca, w nowym wierszu.
struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.init(width: width, height: nil))
            if x > 0, x + size.width > width {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(maxX, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.init(width: bounds.width, height: nil))
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: .init(width: min(size.width, bounds.width), height: size.height))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
