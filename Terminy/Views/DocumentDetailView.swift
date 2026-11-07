import SwiftUI
import SwiftData

struct DocumentDetailView: View {
    @Bindable var document: Document
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(NotificationScheduler.reminderHourKey) private var reminderHour = 9
    @State private var confirmDelete = false
    @State private var showingScan = false
    @State private var flip: Double = 0

    var body: some View {
        let days = document.daysLeft()
        List {
            Section {
                DocumentCard(document: document)
                    .rotation3DEffect(.degrees(flip), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section {
                LabeledContent(document.category == .subscription ? "Następna płatność" : "Ważny do",
                               value: PL.date(document.expiryDate))
                    .contentTransition(.numericText())
                LabeledContent(days < 0 ? "Po terminie od" : "Zostało") {
                    Text(days == 0 ? "dziś" : DaysText.long(to: document.expiryDate))
                        .foregroundStyle(days <= 7 ? Urgency(days: days).color : Color.secondary)
                        .contentTransition(.numericText())
                }
                if document.category == .subscription, let price = document.price {
                    LabeledContent("Cena", value: PL.money(price) + " / " + (document.billingCycle ?? .monthly).shortTitle)
                }
                if !document.owner.isEmpty {
                    LabeledContent(document.category.ownerLabel, value: document.owner)
                }
                if !document.number.isEmpty {
                    LabeledContent(document.category.numberLabel, value: document.number)
                        .textSelection(.enabled)
                }
            }

            Section {
                Button {
                    withAnimation(.spring(duration: 0.8, bounce: 0.2)) { flip += 360 }
                    router.renew(document)
                } label: {
                    Label("Odnów do \(PL.date(document.renewedExpiryDate()))", systemImage: "arrow.clockwise")
                        .contentTransition(.numericText())
                }
            } footer: {
                Text(renewFooter)
            }

            Section("Przypomnienia") {
                Toggle("Przypominaj o terminie", isOn: $document.remindersEnabled)
                if document.remindersEnabled {
                    if let next = nextReminder {
                        LabeledContent("Najbliższe", value: PL.dayAndMonth(next) + ", \(reminderHour):00")
                    } else {
                        Text("Wszystkie przypomnienia już minęły.")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let data = document.scanImageData, let image = UIImage(data: data) {
                Section("Skan") {
                    Button { showingScan = true } label: {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Pokaż skan na pełnym ekranie")
                }
            }

            if !document.notes.isEmpty {
                Section("Notatki") {
                    Text(document.notes)
                }
            }

            Section {
                Button("Usuń dokument", role: .destructive) { confirmDelete = true }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .navigationTitle(document.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edytuj") { router.edit(document) }
            }
        }
        .confirmationDialog("Usunąć „\(document.displayTitle)”?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Usuń", role: .destructive) { delete() }
        } message: {
            Text("Przypomnienia o tym dokumencie też znikną.")
        }
        .fullScreenCover(isPresented: $showingScan) {
            ScanViewer(data: document.scanImageData)
        }
    }

    private var nextReminder: Date? {
        NotificationScheduler.plannedReminders(
            for: [document], hour: reminderHour, now: .now,
            offsets: NotificationScheduler.enabledOffsets()
        ).first?.fireDate
    }

    private var renewFooter: String {
        if document.category == .subscription {
            return "Przesuwa termin o jeden okres rozliczeniowy."
        }
        let period = document.category.defaultRenewal
        if let years = period.year {
            return "Przesuwa termin o \(years) \(DaysText.lata(years)). Datę możesz potem zmienić w edycji."
        }
        return "Przesuwa termin o typowy okres. Datę możesz potem zmienić w edycji."
    }

    private func delete() {
        let doc = document
        router.show("Usunięto „\(doc.displayTitle)”", symbol: "trash.circle.fill")
        dismiss()
        // Usuwamy po zamknięciu ekranu, żeby widok nie czytał już skasowanego obiektu.
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            context.delete(doc)
        }
    }
}

// MARK: - Karta dokumentu

/// Dokument narysowany jak plastikowa karta: kolor grupy, giloszowy wzór jak na prawdziwych
/// dokumentach i „Ważny do” w rogu. Po terminie dostaje pieczątkę.
struct DocumentCard: View {
    let document: Document

    var body: some View {
        let group = document.group
        let expired = document.daysLeft() < 0
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(group.color)
                .shadow(color: group.color.opacity(0.35), radius: 18, y: 10)

            GuillocheShape()
                .stroke(group.ink.opacity(0.09), lineWidth: 0.8)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: document.category.symbol)
                        .font(.subheadline.weight(.semibold))
                    Text(document.category.title)
                        .font(.subheadline.weight(.medium))
                }
                .opacity(0.75)

                Spacer(minLength: 12)

                Text(document.displayTitle)
                    .font(.title2.weight(.bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                if !document.owner.isEmpty {
                    Text(document.owner)
                        .font(.body)
                        .opacity(0.8)
                }

                Spacer(minLength: 12)

                HStack(alignment: .lastTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(document.category == .subscription ? "Płatność" : "Ważny do")
                            .font(.caption)
                            .opacity(0.7)
                        Text(PL.numeric(document.expiryDate))
                            .font(.headline)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                    Spacer()
                    if !document.number.isEmpty {
                        Text(document.number)
                            .font(.subheadline.weight(.medium))
                            .monospacedDigit()
                            .opacity(0.8)
                            .lineLimit(1)
                    }
                }
            }
            .foregroundStyle(group.ink)
            .padding(20)

            if expired {
                ExpiredStamp()
                    .transition(.scale(scale: 1.8).combined(with: .opacity))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .padding(.trailing, 22)
                    .offset(y: -6)
            }
        }
        .aspectRatio(1.586, contentMode: .fit)
        .animation(.spring(duration: 0.4), value: expired)
        .accessibilityElement(children: .combine)
    }
}

/// Fale jak na banknotach i dowodach.
struct GuillocheShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let lines = 16
        let amplitude = rect.height * 0.09
        for i in 0..<lines {
            let base = rect.height * (0.18 + 0.045 * CGFloat(i))
            let phase = Double(i) * 0.42
            path.move(to: CGPoint(x: 0, y: base))
            var x: CGFloat = 0
            while x <= rect.width {
                let t = Double(x / rect.width) * .pi * 2.6 + phase
                let y = base + CGFloat(sin(t)) * amplitude
                path.addLine(to: CGPoint(x: x, y: y))
                x += 4
            }
        }
        return path
    }
}

/// Pieczątka „Nieważny” na karcie po terminie.
struct ExpiredStamp: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var landed = false

    var body: some View {
        Text("Nieważny")
            .font(.headline.weight(.heavy))
            .foregroundStyle(Palette.expired)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Palette.expired, lineWidth: 2.5)
            }
            .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .rotationEffect(.degrees(-9))
            // Pieczątka „spada” na kartę po wejściu na ekran.
            .scaleEffect(landed || reduceMotion ? 1 : 1.9)
            .opacity(landed || reduceMotion ? 1 : 0)
            .sensoryFeedback(.impact(weight: .heavy), trigger: landed) { _, new in new }
            .task {
                guard !landed else { return }
                try? await Task.sleep(for: .milliseconds(380))
                withAnimation(.spring(duration: 0.32, bounce: 0.35)) { landed = true }
            }
            .accessibilityLabel("Po terminie")
    }
}

/// Skan na pełnym ekranie z przybliżaniem.
struct ScanViewer: View {
    let data: Data?
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let data, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale)
                        .gesture(MagnifyGesture().onChanged { scale = max(1, $0.magnification) }
                            .onEnded { _ in withAnimation(.spring) { scale = 1 } })
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zamknij") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
