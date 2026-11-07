import SwiftUI
import SwiftData

/// Dodawanie i edycja dokumentu. Najpierw „Co dodajesz?”, potem formularz
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
            AppBackground()
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
        .foregroundStyle(DT.Palette.textPrimary)
        .presentationCornerRadius(DT.Radius.panel + DT.Space.md)
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
                    .font(DT.Typography.headline)
                    .foregroundStyle(DT.Palette.textSecondary)
                    .frame(minHeight: DT.Size.touch)
                Spacer()
                Text(document == nil ? "Nowy dokument" : "Edycja")
                    .font(DT.Typography.headline)
                Spacer()
                if document == nil {
                    Button("Rodzaj") { withAnimation(.spring(duration: 0.4)) { self.category = nil } }
                        .font(DT.Typography.headline)
                        .foregroundStyle(DT.Palette.textSecondary)
                        .frame(minHeight: DT.Size.touch)
                } else {
                    Color.clear.frame(width: DT.Size.touch + DT.Space.md, height: DT.Size.touch)
                }
            }
            .padding(.horizontal, DT.Space.gutter)
            .padding(.top, DT.Space.md)

            ScrollView {
                VStack(spacing: DT.Space.md) {
                    DocCard(data: preview, tilt: false)
                        .scaleEffect(inserting ? 0.86 : 1)
                        .offset(y: inserting ? DT.Size.card.height * 3 : 0)
                        .rotationEffect(.degrees(inserting ? 4 : 0))
                        .animation(.spring(duration: 0.45, bounce: 0.25), value: preview)
                        .padding(.bottom, DT.Space.xxs)

                    field("Nazwa", text: $title, prompt: category.titlePlaceholder, focus: .title)

                    dateSection(category)

                    if category == .subscription {
                        VStack(spacing: DT.Space.sm) {
                            HStack(spacing: DT.Space.sm) {
                                Text("Cena").font(DT.Typography.subheadline).foregroundStyle(DT.Palette.textSecondary)
                                TextField("", text: $priceText, prompt: Text("0").foregroundStyle(DT.Palette.textTertiary))
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .font(DT.Typography.headline)
                                    .focused($focus, equals: .price)
                                Text("zł").foregroundStyle(DT.Palette.textSecondary)
                            }
                            .padding(.horizontal, DT.Space.md)
                            .frame(minHeight: DT.Size.toggleRow)
                            .panel()

                            HStack(spacing: DT.Space.xs) {
                                ForEach(BillingCycle.allCases) { cycle in
                                    pill(cycle.title, isOn: billingCycle == cycle) { billingCycle = cycle }
                                }
                            }
                        }
                    }

                    field(category.ownerLabel, text: $owner, prompt: "Opcjonalnie", focus: .owner)
                    field(category.numberLabel, text: $number, prompt: "Opcjonalnie", focus: .number, characters: true)

                    scanSection

                    VStack(alignment: .leading, spacing: DT.Space.xs) {
                        Text("Notatki").font(DT.Typography.subheadline).foregroundStyle(DT.Palette.textSecondary)
                        TextField("", text: $notes, prompt: Text("Np. gdzie leży oryginał").foregroundStyle(DT.Palette.textTertiary), axis: .vertical)
                            .lineLimit(2...6)
                            .font(DT.Typography.body)
                            .focused($focus, equals: .notes)
                    }
                    .padding(DT.Space.md)
                    .panel()

                    Toggle(isOn: $remindersEnabled) {
                        VStack(alignment: .leading, spacing: DT.Space.xxs) {
                            Text("Przypomnienia").font(DT.Typography.headline)
                            Text(remindersEnabled ? "Przypomnę \(reminderSummary)." : "Wyłączone dla tego dokumentu.")
                                .font(DT.Typography.footnote)
                                .foregroundStyle(DT.Palette.textSecondary)
                        }
                    }
                    .tint(DT.Palette.accent)
                    .padding(DT.Space.md)
                    .panel()
                }
                .padding(.horizontal, DT.Space.gutter)
                .padding(.top, DT.Space.sm)
                .padding(.bottom, DT.Space.xxl)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: document == nil ? "Dodaj dokument" : "Zapisz zmiany",
                       symbol: document == nil ? "plus" : "checkmark") { save() }
                .padding(.horizontal, DT.Space.gutter)
                .padding(.bottom, DT.Space.xs)
                .background(
                    LinearGradient(colors: [DT.Palette.background.opacity(0), DT.Palette.background], startPoint: .top, endPoint: .center)
                        .ignoresSafeArea()
                )
        }
    }

    private func dateSection(_ category: DocumentCategory) -> some View {
        VStack(alignment: .leading, spacing: DT.Space.sm) {
            Button {
                withAnimation(.spring(duration: 0.4, bounce: 0.2)) { showingCalendar.toggle() }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: DT.Space.xxs) {
                        Text(category == .subscription ? "Następna płatność" : "Ważny do")
                            .font(DT.Typography.subheadline).foregroundStyle(DT.Palette.textSecondary)
                        Text(PL.date(expiryDate))
                            .font(DT.Typography.title3)
                            .contentTransition(.numericText())
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(DT.Typography.subheadlineEmphasized)
                        .foregroundStyle(DT.Palette.textSecondary)
                        .rotationEffect(.degrees(showingCalendar ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: DT.Space.xs) {
                quick("+1 mies.", months: 1)
                quick("+1 rok", months: 12)
                quick("+5 lat", months: 60)
                quick("+10 lat", months: 120)
            }

            if showingCalendar {
                DatePicker("Data", selection: $expiryDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .tint(DT.Palette.accent)
                    .environment(\.locale, PL.locale)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if isReading {
                HStack(spacing: DT.Space.sm) {
                    ProgressView().tint(DT.Palette.accent)
                    Text("Odczytuję datę ze skanu…").font(DT.Typography.subheadline).foregroundStyle(DT.Palette.textSecondary)
                }
            } else if let ocrMessage {
                Label(ocrMessage, systemImage: ocrFound ? "text.viewfinder" : "exclamationmark.triangle")
                    .font(DT.Typography.subheadline)
                    .foregroundStyle(ocrFound ? DT.Palette.accent : DT.Palette.warning)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(DT.Space.md)
        .panel()
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
                .font(DT.Typography.subheadlineEmphasized)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(isOn ? DT.Palette.onAccent : DT.Palette.textPrimary)
                .frame(maxWidth: .infinity, minHeight: DT.Size.pill)
                .background(isOn ? DT.Palette.accent : DT.Palette.surfaceRaised, in: Capsule())
        }
        .buttonStyle(CardPressStyle())
    }

    private var scanSection: some View {
        VStack(spacing: DT.Space.sm) {
            if let data = scanImageData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: DT.Size.scanPreview)
                    .clipShape(RoundedRectangle(cornerRadius: DT.Radius.card, style: .continuous))
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .topTrailing) {
                        Button {
                            withAnimation { scanImageData = nil; ocrMessage = nil }
                        } label: {
                            Image(systemName: "xmark")
                                .font(DT.Typography.footnoteEmphasized)
                                .foregroundStyle(DT.Palette.onScrim)
                                .frame(width: DT.Space.xl, height: DT.Space.xl)
                                .background(DT.Palette.scrim.opacity(0.55), in: Circle())
                        }
                        .frame(width: DT.Size.touch, height: DT.Size.touch)
                        .accessibilityLabel("Usuń skan")
                    }
            }
            if DocumentScanner.isSupported {
                Button { showingScanner = true } label: {
                    Label(scanImageData == nil ? "Zeskanuj dokument" : "Zeskanuj ponownie", systemImage: "doc.viewfinder")
                        .font(DT.Typography.headline)
                        .foregroundStyle(DT.Palette.accentText)
                        .frame(maxWidth: .infinity, minHeight: DT.Size.field)
                }
                .buttonStyle(CardPressStyle())
                if scanImageData == nil {
                    Text("Ze skanu odczytam datę ważności. Zdjęcie zostaje na telefonie.")
                        .font(DT.Typography.footnote)
                        .foregroundStyle(DT.Palette.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(DT.Space.md)
        .panel()
    }

    private func field(_ label: String, text: Binding<String>, prompt: String, focus field: Field,
                       characters: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: DT.Space.xxs) {
            Text(label).font(DT.Typography.subheadline).foregroundStyle(DT.Palette.textSecondary)
            TextField("", text: text, prompt: Text(prompt).foregroundStyle(DT.Palette.textTertiary))
                .font(DT.Typography.headline)
                .textInputAutocapitalization(characters ? .characters : .sentences)
                .autocorrectionDisabled(characters)
                .focused($focus, equals: field)
                .submitLabel(.next)
        }
        .padding(.horizontal, DT.Space.md)
        .padding(.vertical, DT.Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
        .overlay {
            RoundedRectangle(cornerRadius: DT.Radius.panel, style: .continuous)
                .strokeBorder(DT.Palette.accent.opacity(focus == field ? 0.7 : 0), lineWidth: DT.Size.hairline * 2)
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
            message = (isNew ? "Dodano „\(name)”. " : "Zapisano. ") + "Przypomnę \(PL.dayMonth(next))."
        } else {
            message = isNew ? "Dodano „\(name)”." : "Zapisano zmiany."
        }

        // O zgodę na powiadomienia pytamy dopiero przy pierwszym dokumencie, kiedy wiadomo po co.
        let context = self.context
        Task {
            await NotificationScheduler.shared.requestAuthorization()
            let all = (try? context.fetch(FetchDescriptor<Document>())) ?? []
            await NotificationScheduler.shared.reschedule(all)
        }

        // Karta „wsuwa się” w dół do portfela, potem arkusz się zamyka.
        Haptics.shared.fire(.insert)
        withAnimation(.spring(duration: 0.45, bounce: 0.15)) { inserting = true }
        Task {
            try? await Task.sleep(for: .milliseconds(380))
            router.show(message, symbol: isNew ? "plus.circle.fill" : "checkmark.circle.fill")
            dismiss()
        }
    }
}

// MARK: - Co dodajesz?

struct CategoryPicker: View {
    let canScan: Bool
    let onPick: (DocumentCategory) -> Void
    let onScan: () -> Void
    let onCancel: () -> Void
    @State private var scanLine = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DT.Space.gutter) {
                HStack {
                    Spacer()
                    Button("Anuluj", action: onCancel)
                        .font(DT.Typography.headline)
                        .foregroundStyle(DT.Palette.textSecondary)
                        .frame(minHeight: DT.Size.touch)
                }
                Text("Co dodajesz?")
                    .font(DT.Typography.largeTitle)
                    .riseIn(0)

                if canScan {
                    Button(action: onScan) {
                        HStack(spacing: DT.Space.md) {
                            ZStack {
                                RoundedRectangle(cornerRadius: DT.Radius.sm, style: .continuous)
                                    .strokeBorder(DT.Palette.accent, lineWidth: DT.Size.hairline * 2)
                                    .frame(width: DT.Size.hologram.width, height: DT.Size.hologram.height)
                                Rectangle()
                                    .fill(DT.Palette.accent)
                                    .frame(width: DT.Size.hologram.height, height: DT.Size.hairline * 2)
                                    .offset(y: scanLine && !reduceMotion ? DT.Space.sm : -DT.Space.sm)
                            }
                            VStack(alignment: .leading, spacing: DT.Space.xxs) {
                                Text("Zeskanuj dokument").font(DT.Typography.headline)
                                Text("Rozpoznam rodzaj i datę ważności")
                                    .font(DT.Typography.subheadline)
                                    .foregroundStyle(DT.Palette.textSecondary)
                            }
                            Spacer()
                        }
                        .padding(DT.Space.md)
                        .panel()
                        .overlay(RoundedRectangle(cornerRadius: DT.Radius.panel, style: .continuous).strokeBorder(DT.Palette.accent.opacity(0.5), lineWidth: DT.Size.hairline))
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
                        VStack(alignment: .leading, spacing: DT.Space.sm) {
                            Text(group.title)
                                .font(DT.Typography.subheadlineEmphasized)
                                .foregroundStyle(DT.Palette.textSecondary)
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: DT.Space.sm), GridItem(.flexible(), spacing: DT.Space.sm)], spacing: DT.Space.sm) {
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
                        Text("Coś innego").font(DT.Typography.headline)
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(DT.Palette.textTertiary)
                    }
                    .foregroundStyle(DT.Palette.textPrimary)
                    .padding(.horizontal, DT.Space.md)
                    .frame(minHeight: DT.Size.toggleRow)
                    .panel()
                }
                .buttonStyle(CardPressStyle())
                .riseIn(7)
            }
            .padding(.horizontal, DT.Space.gutter)
            .padding(.top, DT.Space.md)
            .padding(.bottom, DT.Space.xxl)
        }
        .scrollIndicators(.hidden)
    }
}
