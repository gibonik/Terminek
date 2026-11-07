import SwiftUI
import SwiftData

/// Dodawanie i edycja dokumentu. Najpierw „Co wkładasz do portfela?”, potem formularz
/// z kartą na górze, która na żywo pokazuje to, co wpisujesz.
struct DocumentEditView: View {
    private let document: Document?
    private let startScanning: Bool

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router

    @State private var category: DocumentCategory?
    @State private var title: String
    @State private var owner: String
    @State private var number: String
    @State private var notes: String
    @State private var expiryDate: Date
    @State private var remindersEnabled: Bool
    @State private var priceText: String
    @State private var billingCycle: BillingCycle
    @State private var scanImageData: Data?

    @State private var showingScanner = false
    @State private var showingCalendar = false
    @State private var isReading = false
    @State private var ocrMessage: String?
    @State private var ocrFound = false
    @State private var inserting = false
    @FocusState private var focus: Field?

    enum Field { case title, owner, number, price, notes }

    init(request: EditorRequest) {
        let doc = request.document
        document = doc
        startScanning = request.startScanning
        _category = State(initialValue: request.category)
        _title = State(initialValue: doc?.title ?? "")
        _owner = State(initialValue: doc?.owner ?? "")
        _number = State(initialValue: doc?.number ?? "")
        _notes = State(initialValue: doc?.notes ?? "")
        let defaultDate = Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now
        _expiryDate = State(initialValue: doc?.expiryDate ?? defaultDate)
        _remindersEnabled = State(initialValue: doc?.remindersEnabled ?? true)
        _priceText = State(initialValue: doc?.price.map { $0.formatted(.number.locale(PL.locale)) } ?? "")
        _billingCycle = State(initialValue: doc?.billingCycle ?? .monthly)
        _scanImageData = State(initialValue: doc?.scanImageData)
    }

    var body: some View {
        ZStack(alignment: .top) {
            WalletBackground()
            if let category {
                form(category)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .opacity))
            } else {
                CategoryPicker(
                    canScan: DocumentScanner.isSupported,
                    onPick: { picked in
                        withAnimation(.spring(duration: 0.45, bounce: 0.2)) { category = picked }
                        if picked == .subscription { expiryDate = Calendar.current.date(byAdding: .month, value: 1, to: .now) ?? .now }
                    },
                    onScan: { showingScanner = true },
                    onCancel: { dismiss() }
                )
                .transition(.asymmetric(insertion: .opacity,
                                        removal: .move(edge: .leading).combined(with: .opacity)))
            }
        }
        .foregroundStyle(W.cream)
        .presentationCornerRadius(34)
        .interactiveDismissDisabled(hasChanges)
        .fullScreenCover(isPresented: $showingScanner) {
            DocumentScanner { pages in
                Task { await handle(images: pages) }
            }
            .ignoresSafeArea()
        }
        .onAppear {
            if startScanning && DocumentScanner.isSupported { showingScanner = true }
        }
    }

    private var hasChanges: Bool {
        guard category != nil else { return false }
        if let document {
            return title != document.title || owner != document.owner || number != document.number
                || notes != document.notes || expiryDate != document.expiryDate
        }
        return !title.isEmpty || !owner.isEmpty || !number.isEmpty || !notes.isEmpty || scanImageData != nil
    }

    private var preview: CardData {
        CardData(category: category ?? .other, title: title, owner: owner, number: number,
                 expiryDate: expiryDate, price: Self.parsePrice(priceText),
                 billingCycle: category == .subscription ? billingCycle : nil)
    }

    // MARK: Formularz

    private func form(_ category: DocumentCategory) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button("Anuluj") { dismiss() }
                    .font(.brico(16, .bold))
                    .foregroundStyle(W.muted)
                    .frame(minHeight: 44)
                Spacer()
                Text(document == nil ? "Nowy dokument" : "Edycja")
                    .font(.brico(17, .bold))
                Spacer()
                if document == nil {
                    Button("Rodzaj") { withAnimation(.spring(duration: 0.4)) { self.category = nil } }
                        .font(.brico(16, .bold))
                        .foregroundStyle(W.muted)
                        .frame(minHeight: 44)
                } else {
                    Color.clear.frame(width: 60, height: 44)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)

            ScrollView {
                VStack(spacing: 14) {
                    DocCard(data: preview, tilt: false)
                        .scaleEffect(inserting ? 0.86 : 1)
                        .offset(y: inserting ? 700 : 0)
                        .rotationEffect(.degrees(inserting ? 4 : 0))
                        .animation(.spring(duration: 0.45, bounce: 0.25), value: preview)
                        .padding(.bottom, 4)

                    field("Nazwa", text: $title, prompt: category.titlePlaceholder, focus: .title)

                    dateSection(category)

                    if category == .subscription {
                        VStack(spacing: 10) {
                            HStack(spacing: 10) {
                                Text("Cena").font(.subheadline).foregroundStyle(W.muted)
                                TextField("", text: $priceText, prompt: Text("0").foregroundStyle(W.faint))
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .font(.brico(18, .bold))
                                    .focused($focus, equals: .price)
                                Text("zł").foregroundStyle(W.muted)
                            }
                            .padding(.horizontal, 16)
                            .frame(minHeight: 54)
                            .walletPanel(radius: 16)

                            HStack(spacing: 8) {
                                ForEach(BillingCycle.allCases) { cycle in
                                    pill(cycle.title, isOn: billingCycle == cycle) { billingCycle = cycle }
                                }
                            }
                        }
                    }

                    field(category.ownerLabel, text: $owner, prompt: "Opcjonalnie", focus: .owner)
                    field(category.numberLabel, text: $number, prompt: "Opcjonalnie", focus: .number, characters: true)

                    scanSection

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notatki").font(.subheadline).foregroundStyle(W.muted)
                        TextField("", text: $notes, prompt: Text("Np. gdzie leży oryginał").foregroundStyle(W.faint), axis: .vertical)
                            .lineLimit(2...6)
                            .font(.body)
                            .focused($focus, equals: .notes)
                    }
                    .padding(16)
                    .walletPanel(radius: 16)

                    Toggle(isOn: $remindersEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Przypomnienia").font(.brico(16, .bold))
                            Text(remindersEnabled ? "Przypomnę \(reminderSummary)." : "Wyłączone dla tego dokumentu.")
                                .font(.footnote)
                                .foregroundStyle(W.muted)
                        }
                    }
                    .tint(W.gold)
                    .padding(16)
                    .walletPanel(radius: 16)
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 110)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom) {
            GoldButton(title: document == nil ? "Włóż do portfela" : "Zapisz zmiany",
                       symbol: document == nil ? "wallet.pass" : "checkmark") { save() }
                .padding(.horizontal, 18)
                .padding(.bottom, 8)
                .background(
                    LinearGradient(colors: [W.leather.opacity(0), W.leather], startPoint: .top, endPoint: .center)
                        .ignoresSafeArea()
                )
        }
    }

    private func dateSection(_ category: DocumentCategory) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.spring(duration: 0.4, bounce: 0.2)) { showingCalendar.toggle() }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(category == .subscription ? "Następna płatność" : "Ważny do")
                            .font(.subheadline).foregroundStyle(W.muted)
                        Text(PL.date(expiryDate))
                            .font(.brico(20, .heavy))
                            .contentTransition(.numericText())
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(W.muted)
                        .rotationEffect(.degrees(showingCalendar ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                quick("+1 mies.", months: 1)
                quick("+1 rok", months: 12)
                quick("+5 lat", months: 60)
                quick("+10 lat", months: 120)
            }

            if showingCalendar {
                DatePicker("Data", selection: $expiryDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .tint(W.gold)
                    .environment(\.locale, PL.locale)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if isReading {
                HStack(spacing: 10) {
                    ProgressView().tint(W.gold)
                    Text("Odczytuję datę ze skanu…").font(.subheadline).foregroundStyle(W.muted)
                }
            } else if let ocrMessage {
                Label(ocrMessage, systemImage: ocrFound ? "text.viewfinder" : "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(ocrFound ? W.gold : Palette.soon)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(16)
        .walletPanel(radius: 16)
        .sensoryFeedback(.selection, trigger: expiryDate)
    }

    private func quick(_ title: String, months: Int) -> some View {
        pill(title, isOn: false) {
            let base = Calendar.current.startOfDay(for: .now)
            if let date = Calendar.current.date(byAdding: .month, value: months, to: base) {
                withAnimation(.snappy) { expiryDate = date }
            }
        }
    }

    private func pill(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.brico(14, .bold, relativeTo: .subheadline))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(isOn ? W.goldInk : W.cream)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(isOn ? W.gold : W.surfaceHi, in: Capsule())
        }
        .buttonStyle(CardPressStyle())
    }

    private var scanSection: some View {
        VStack(spacing: 12) {
            if let data = scanImageData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .topTrailing) {
                        Button {
                            withAnimation { scanImageData = nil; ocrMessage = nil }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(W.cream)
                                .frame(width: 32, height: 32)
                                .background(.black.opacity(0.55), in: Circle())
                        }
                        .frame(width: 44, height: 44)
                        .accessibilityLabel("Usuń skan")
                    }
            }
            if DocumentScanner.isSupported {
                Button { showingScanner = true } label: {
                    Label(scanImageData == nil ? "Zeskanuj dokument" : "Zeskanuj ponownie", systemImage: "doc.viewfinder")
                        .font(.brico(16, .bold))
                        .foregroundStyle(W.gold)
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(CardPressStyle())
                if scanImageData == nil {
                    Text("Ze skanu odczytam datę ważności. Zdjęcie zostaje na telefonie.")
                        .font(.footnote)
                        .foregroundStyle(W.muted)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(16)
        .walletPanel(radius: 16)
    }

    private func field(_ label: String, text: Binding<String>, prompt: String, focus field: Field,
                       characters: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.subheadline).foregroundStyle(W.muted)
            TextField("", text: text, prompt: Text(prompt).foregroundStyle(W.faint))
                .font(.brico(18, .bold))
                .textInputAutocapitalization(characters ? .characters : .sentences)
                .autocorrectionDisabled(characters)
                .focused($focus, equals: field)
                .submitLabel(.next)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .walletPanel(radius: 16)
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(W.gold.opacity(focus == field ? 0.7 : 0), lineWidth: 1.5)
        }
        .animation(.snappy, value: focus)
        .contentShape(Rectangle())
        .onTapGesture { focus = field }
    }

    private var reminderSummary: String {
        let offsets = NotificationScheduler.enabledOffsets()
        guard !offsets.isEmpty else { return "według ustawień, ale wszystkie są teraz wyłączone" }
        let parts = offsets.map { offset -> String in
            switch offset {
            case 0: return "w dniu terminu"
            case 7: return "tydzień wcześniej"
            case 30: return "30 dni wcześniej"
            default: return "\(offset) dni wcześniej"
            }
        }
        guard parts.count > 1 else { return parts[0] }
        return parts.dropLast().joined(separator: ", ") + " i " + parts[parts.count - 1]
    }

    // MARK: Logika

    static func parsePrice(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: " ", with: ""))
    }

    private func handle(images: [UIImage]) async {
        guard let first = images.first else { return }
        withAnimation { scanImageData = first.downscaled(maxDimension: 1600).jpegData(compressionQuality: 0.6) }

        withAnimation { isReading = true }
        defer { withAnimation { isReading = false } }

        var text = ""
        for image in images {
            if let pageText = try? await TextRecognizer.recognizeText(in: image) {
                text += pageText + "\n"
            }
        }

        withAnimation(.spring(duration: 0.45, bounce: 0.2)) {
            if category == nil {
                category = Self.guessCategory(in: text) ?? .other
            }
            if let date = DateExtractor().bestExpiryDate(in: text) {
                expiryDate = date
                ocrFound = true
                ocrMessage = "Odczytano \(PL.date(date)). Sprawdź, czy się zgadza."
            } else {
                ocrFound = false
                ocrMessage = "Nie udało się odczytać daty. Ustaw ją ręcznie."
            }
        }
    }

    /// Prosta podpowiedź rodzaju na podstawie tekstu ze skanu.
    static func guessCategory(in text: String) -> DocumentCategory? {
        let t = text.uppercased()
        if t.contains("PASZPORT") || t.contains("PASSPORT") { return .passport }
        if t.contains("DOWÓD OSOBISTY") || t.contains("DOWOD OSOBISTY") || t.contains("IDENTITY CARD") { return .idCard }
        if t.contains("PRAWO JAZDY") || t.contains("DRIVING LICENCE") { return .drivingLicense }
        if t.contains("BADANIE TECHNICZNE") || t.contains("PRZEGLĄD") || t.contains("STACJA KONTROLI") { return .carInspection }
        if t.contains("ODPOWIEDZIALNOŚCI CYWILNEJ") || t.contains(" OC ") || t.contains("POJAZD") { return .carInsurance }
        if t.contains("MIESZKANI") || t.contains("NIERUCHOMOŚ") || t.contains("DOMU") { return .homeInsurance }
        return nil
    }

    private func save() {
        guard let category else { return }
        focus = nil
        let target = document ?? Document()
        target.category = category
        target.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        target.owner = owner.trimmingCharacters(in: .whitespacesAndNewlines)
        target.number = number.trimmingCharacters(in: .whitespacesAndNewlines)
        target.expiryDate = expiryDate
        target.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        target.remindersEnabled = remindersEnabled
        target.scanImageData = scanImageData
        if category == .subscription {
            target.price = Self.parsePrice(priceText)
            target.billingCycle = billingCycle
        } else {
            target.price = nil
            target.billingCycle = nil
        }
        let isNew = document == nil
        if isNew { context.insert(target) }

        let name = target.displayTitle
        let next = remindersEnabled ? NotificationScheduler.plannedReminders(
            for: [target], hour: NotificationScheduler.shared.reminderHour, now: .now,
            offsets: NotificationScheduler.enabledOffsets()
        ).first?.fireDate : nil
        let message: String
        if let next {
            message = (isNew ? "„\(name)” jest w portfelu. " : "Zapisano. ") + "Przypomnę \(PL.dayMonth(next))."
        } else {
            message = isNew ? "„\(name)” jest w portfelu." : "Zapisano zmiany."
        }

        // O zgodę na powiadomienia pytamy dopiero przy pierwszym dokumencie, kiedy wiadomo po co.
        let context = self.context
        Task {
            await NotificationScheduler.shared.requestAuthorization()
            let all = (try? context.fetch(FetchDescriptor<Document>())) ?? []
            await NotificationScheduler.shared.reschedule(all)
        }

        // Karta „wsuwa się” w dół do portfela, potem arkusz się zamyka.
        withAnimation(.spring(duration: 0.45, bounce: 0.15)) { inserting = true }
        Task {
            try? await Task.sleep(for: .milliseconds(380))
            router.show(message, symbol: isNew ? "wallet.pass.fill" : "checkmark.circle.fill")
            dismiss()
        }
    }
}

// MARK: - Co wkładasz do portfela?

struct CategoryPicker: View {
    let canScan: Bool
    let onPick: (DocumentCategory) -> Void
    let onScan: () -> Void
    let onCancel: () -> Void
    @State private var scanLine = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Spacer()
                    Button("Anuluj", action: onCancel)
                        .font(.brico(16, .bold))
                        .foregroundStyle(W.muted)
                        .frame(minHeight: 44)
                }
                Text("Co wkładasz\ndo portfela?")
                    .font(.brico(36, .heavy, relativeTo: .largeTitle))
                    .tracking(-1)
                    .riseIn(0)

                if canScan {
                    Button(action: onScan) {
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(W.gold, lineWidth: 2)
                                    .frame(width: 52, height: 40)
                                Rectangle()
                                    .fill(W.gold)
                                    .frame(width: 40, height: 2)
                                    .offset(y: scanLine && !reduceMotion ? 12 : -12)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Zeskanuj dokument").font(.brico(18, .bold))
                                Text("Rozpoznam rodzaj i datę ważności")
                                    .font(.subheadline)
                                    .foregroundStyle(W.muted)
                            }
                            Spacer()
                        }
                        .padding(16)
                        .walletPanel(radius: 20)
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(W.gold.opacity(0.5), lineWidth: 1))
                    }
                    .buttonStyle(CardPressStyle())
                    .riseIn(1)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { scanLine = true }
                    }
                }

                ForEach(Array(CategoryGroup.allCases.enumerated()), id: \.element) { index, group in
                    let items = group.categories.filter { $0 != .other }
                    if !items.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(group.title)
                                .font(.brico(15, .bold, relativeTo: .subheadline))
                                .foregroundStyle(W.muted)
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                                ForEach(items) { item in
                                    CategoryTile(category: item) { onPick(item) }
                                }
                            }
                        }
                        .riseIn(2 + index)
                    }
                }

                Button { onPick(.other) } label: {
                    HStack {
                        Image(systemName: DocumentCategory.other.symbol)
                        Text("Coś innego").font(.brico(16, .bold))
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(W.faint)
                    }
                    .foregroundStyle(W.cream)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 54)
                    .walletPanel(radius: 16)
                }
                .buttonStyle(CardPressStyle())
                .riseIn(7)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
    }
}
