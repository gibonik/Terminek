import SwiftUI
import SwiftData

/// Czat z asystentem: pytania o terminy, odpowiedzi z kartami dokumentów.
struct AssistantView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \Document.expiryDate) private var documents: [Document]

    struct Message: Identifiable, Equatable {
        let id = UUID()
        let fromUser: Bool
        let text: String
        var documentIDs: [UUID] = []
    }

    @State private var messages: [Message] = []
    @State private var draft = ""
    @State private var thinking = false
    @FocusState private var inputFocused: Bool

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
        .onAppear {
            if messages.isEmpty {
                messages = [Message(fromUser: false, text: "Cześć! Zapytaj mnie o swoje terminy. Liczę wszystko na telefonie, nic nie wysyłam.")]
            }
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
                Text("Działa bez internetu").font(DT.Typography.caption).foregroundStyle(DT.Palette.textSecondary)
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
        if documents.contains(where: { $0.category == .carInsurance }) { list.append("Kiedy kończy się OC?") }
        list.append("Co mam w tym tygodniu?")
        list.append("Co wygasa w ciągu 30 dni?")
        if documents.contains(where: { $0.daysLeft() < 0 }) { list.append("Co jest po terminie?") }
        if documents.contains(where: { $0.category == .subscription }) { list.append("Ile płacę za subskrypcje?") }
        if documents.contains(where: { $0.category == .idCard }) { list.append("Jak odnowić dowód?") }
        if documents.contains(where: { $0.category == .passport }) { list.append("Kiedy paszport?") }
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
        let reply = Assistant().answer(text, documents: documents)
        Task {
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 450))
            withAnimation(DT.Motion.standard) {
                thinking = false
                messages.append(Message(fromUser: false, text: reply.text, documentIDs: reply.documentIDs))
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
