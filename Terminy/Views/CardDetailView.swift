import SwiftUI
import SwiftData

/// Karta wyciągnięta z portfela: na górze sama karta (przechyla się z telefonem), pod nią szczegóły.
struct CardDetailView: View {
    @Bindable var document: Document
    let cards: Namespace.ID

    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(NotificationScheduler.reminderHourKey) private var reminderHour = 9
    @State private var confirmDelete = false
    @State private var showingScan = false
    @State private var flip: Double = 0
    @State private var bursts = 0
    @State private var drag: CGFloat = 0
    @State private var shown = false

    var body: some View {
        let days = document.daysLeft()
        ZStack(alignment: .top) {
            WalletBackground()
                .opacity(shown ? 1 : 0)
                .onTapGesture { router.close() }

            ScrollView {
                VStack(spacing: 18) {
                    HStack {
                        RoundIconButton(symbol: "chevron.down", label: "Schowaj do portfela") { router.close() }
                        Spacer()
                        Button { router.edit(document) } label: {
                            Text("Edytuj")
                                .font(.brico(16, .bold))
                                .foregroundStyle(W.cream)
                                .padding(.horizontal, 18)
                                .frame(height: 44)
                                .background(W.surfaceHi, in: Capsule())
                        }
                        .buttonStyle(CardPressStyle())
                    }
                    .opacity(shown ? 1 : 0)

                    DocCard(data: CardData(document))
                        .matchedGeometryEffect(id: document.id, in: cards)
                        .rotation3DEffect(.degrees(flip), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
                        .modifier(TiltCard(active: !reduceMotion))
                        .offset(y: drag)
                        .overlay { RenewBurst(trigger: bursts) }
                        .gesture(
                            DragGesture()
                                .onChanged { drag = max(0, $0.translation.height) }
                                .onEnded { value in
                                    if value.translation.height > 110 { router.close() }
                                    withAnimation(.spring(duration: 0.35)) { drag = 0 }
                                }
                        )

                    VStack(spacing: 14) {
                        countdown(days)
                            .riseIn(0)

                        GoldButton(title: "Odnów do \(PL.date(document.renewedExpiryDate()))", symbol: "arrow.clockwise") {
                            if !reduceMotion {
                                withAnimation(.spring(duration: 0.85, bounce: 0.15)) { flip += 360 }
                                // Iskry, kiedy karta kończy obrót i pokazuje nową datę.
                                Task {
                                    try? await Task.sleep(for: .milliseconds(380))
                                    bursts += 1
                                }
                            }
                            router.renew(document)
                        }
                        .riseIn(1)

                        infoPanel.riseIn(2)
                        remindersPanel.riseIn(3)

                        if let data = document.scanImageData, let image = UIImage(data: data) {
                            Button { showingScan = true } label: {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxHeight: 220)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .frame(maxWidth: .infinity)
                                    .padding(12)
                                    .walletPanel()
                            }
                            .buttonStyle(CardPressStyle())
                            .accessibilityLabel("Pokaż skan na pełnym ekranie")
                            .riseIn(4)
                        }

                        if !document.notes.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Notatki").font(.brico(13, .medium, relativeTo: .caption)).foregroundStyle(W.muted)
                                Text(document.notes).font(.body).foregroundStyle(W.cream)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .walletPanel()
                            .riseIn(5)
                        }

                        Button { confirmDelete = true } label: {
                            Text("Wyjmij z portfela")
                                .font(.brico(16, .bold))
                                .foregroundStyle(Palette.expired)
                                .frame(maxWidth: .infinity, minHeight: 52)
                        }
                        .riseIn(6)
                    }
                    .opacity(shown ? 1 : 0)
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .onAppear {
            Tilt.shared.start()
            withAnimation(.easeOut(duration: 0.3)) { shown = true }
        }
        .onDisappear { Tilt.shared.stop() }
        .confirmationDialog("Wyjąć „\(document.displayTitle)” z portfela?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Wyjmij i usuń", role: .destructive) { delete() }
        } message: {
            Text("Dokument i jego przypomnienia znikną.")
        }
        .fullScreenCover(isPresented: $showingScan) {
            ScanViewer(data: document.scanImageData)
        }
    }

    private func countdown(_ days: Int) -> some View {
        let head = DaysText.headline(to: document.expiryDate)
        let color: Color = days < 0 ? Palette.expired : days <= 7 ? Palette.soon : W.cream
        return VStack(alignment: .leading, spacing: 4) {
            Text(days < 0 ? "Po terminie od" : days == 0 ? "Termin" : "Do terminu zostało")
                .font(.brico(14, .medium, relativeTo: .subheadline))
                .foregroundStyle(W.muted)
            Text(days == 0 ? "Dziś" : head.big)
                .font(.brico(40, .heavy, relativeTo: .largeTitle))
                .tracking(-1)
                .foregroundStyle(color)
                .contentTransition(.numericText())
            if let rest = head.rest, days != 0 {
                Text("i " + rest)
                    .font(.brico(17, .medium))
                    .foregroundStyle(W.muted)
                    .contentTransition(.numericText())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .walletPanel()
    }

    private var infoPanel: some View {
        VStack(spacing: 0) {
            infoRow(document.category == .subscription ? "Następna płatność" : "Ważny do", PL.date(document.expiryDate))
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
        .walletPanel()
    }

    private var remindersPanel: some View {
        VStack(spacing: 0) {
            Toggle(isOn: $document.remindersEnabled) {
                Text("Przypominaj o terminie").font(.brico(16, .bold)).foregroundStyle(W.cream)
            }
            .tint(W.gold)
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            if document.remindersEnabled {
                divider
                if let next = nextReminder {
                    infoRow("Najbliższe", PL.dayAndMonth(next) + ", \(reminderHour):00")
                } else {
                    infoRow("Najbliższe", "wszystkie już minęły")
                }
            }
        }
        .walletPanel()
        .animation(.snappy, value: document.remindersEnabled)
    }

    private var divider: some View {
        Rectangle().fill(W.stroke).frame(height: 1).padding(.leading, 16)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).font(.subheadline).foregroundStyle(W.muted)
            Spacer(minLength: 8)
            Text(value)
                .font(.brico(16, .bold))
                .foregroundStyle(W.cream)
                .multilineTextAlignment(.trailing)
                .contentTransition(.numericText())
                .textSelection(.enabled)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .accessibilityElement(children: .combine)
    }

    private var nextReminder: Date? {
        NotificationScheduler.plannedReminders(
            for: [document], hour: reminderHour, now: .now,
            offsets: NotificationScheduler.enabledOffsets()
        ).first?.fireDate
    }

    private func delete() {
        let doc = document
        router.show("Wyjęto z portfela „\(doc.displayTitle)”", symbol: "trash.circle.fill")
        router.close()
        // Usuwamy po schowaniu karty, żeby widok nie czytał już skasowanego obiektu.
        Task {
            try? await Task.sleep(for: .milliseconds(550))
            Haptics.shared.fire(.remove)
            withAnimation(.snappy) { context.delete(doc) }
        }
    }
}

/// Karta lekko pochyla się za przechyleniem telefonu, jak prawdziwy plastik w dłoni.
struct TiltCard: ViewModifier {
    var active: Bool

    func body(content: Content) -> some View {
        let tilt = Tilt.shared
        content
            .rotation3DEffect(.degrees(active ? tilt.x * 8 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
            .rotation3DEffect(.degrees(active ? -tilt.y * 6 : 0), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
    }
}

/// Złote iskry rozpryskujące się spod karty po odnowieniu. Rysowane w Canvas, bez widoków na każdą iskrę.
struct RenewBurst: View {
    let trigger: Int
    @State private var start: Date?

    private struct Spark {
        let angle: Double
        let speed: Double
        let size: Double
        let spin: Double
        let delay: Double
        let warm: Bool
    }

    private static let sparks: [Spark] = {
        var rng = SeededRandom(seed: 42)
        return (0..<46).map { _ in
            Spark(angle: rng.next() * .pi * 2,
                  speed: 170 + rng.next() * 260,
                  size: 3 + rng.next() * 5,
                  spin: (rng.next() - 0.5) * 12,
                  delay: rng.next() * 0.08,
                  warm: rng.next() > 0.35)
        }
    }()

    private let duration = 0.95

    var body: some View {
        TimelineView(.animation(paused: start == nil)) { timeline in
            Canvas { context, size in
                guard let start else { return }
                let t = timeline.date.timeIntervalSince(start)
                guard t < duration else { return }
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                for spark in Self.sparks {
                    let local = max(0, t - spark.delay)
                    let progress = local / duration
                    // Szybki wylot i hamowanie, lekka grawitacja w dół.
                    let distance = spark.speed * (1 - pow(1 - min(progress, 1), 3)) * 0.9
                    let x = center.x + cos(spark.angle) * distance * 1.25
                    let y = center.y + sin(spark.angle) * distance * 0.8 + 140 * progress * progress
                    let alpha = 1 - progress
                    let side = spark.size * (1 - progress * 0.5)
                    var piece = context
                    piece.opacity = alpha
                    piece.translateBy(x: x, y: y)
                    piece.rotate(by: .radians(spark.spin * local))
                    let rect = CGRect(x: -side / 2, y: -side / 2, width: side, height: side * (spark.warm ? 1 : 2.2))
                    piece.fill(Path(roundedRect: rect, cornerRadius: side / 3),
                               with: .color(spark.warm ? W.gold : W.cream))
                }
            }
        }
        .frame(width: 900, height: 900)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: trigger) {
            start = .now
            Task {
                try? await Task.sleep(for: .seconds(duration + 0.1))
                start = nil
            }
        }
    }
}

/// Skan na pełnym ekranie z przybliżaniem.
struct ScanViewer: View {
    let data: Data?
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
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
                .padding(20)
        }
    }
}
