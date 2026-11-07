import SwiftUI
import SwiftData

/// Dodawanie i edycja dokumentu. Nowy dokument zaczyna od pytania „Co dodajesz?”,
/// chyba że rodzaj jest już znany (np. z pustego pulpitu).
struct DocumentEditView: View {
    private let document: Document?
    private let startScanning: Bool

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

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
    @State private var isReading = false
    @State private var ocrMessage: String?
    @State private var ocrFound = false
    @State private var savedTick = 0

    init(request: EditorRequest) {
        let doc = request.document
        document = doc
        startScanning = request.startScanning
        _category = State(initialValue: request.category)
        _title = State(initialValue: doc?.title ?? "")
        _owner = State(initialValue: doc?.owner ?? "")
        _number = State(initialValue: doc?.number ?? "")
        _notes = State(initialValue: doc?.notes ?? "")
        let defaultDate = Calendar.current.date(byAdding: .month, value: 1, to: .now) ?? .now
        _expiryDate = State(initialValue: doc?.expiryDate ?? defaultDate)
        _remindersEnabled = State(initialValue: doc?.remindersEnabled ?? true)
        _priceText = State(initialValue: doc?.price.map { $0.formatted(.number.locale(PL.locale)) } ?? "")
        _billingCycle = State(initialValue: doc?.billingCycle ?? .monthly)
        _scanImageData = State(initialValue: doc?.scanImageData)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let category {
                    form(category)
                } else {
                    CategoryPicker(
                        canScan: DocumentScanner.isSupported,
                        onPick: { picked in withAnimation { category = picked } },
                        onScan: { showingScanner = true }
                    )
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anuluj") { dismiss() }
                }
                if category != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(document == nil ? "Dodaj" : "Zapisz") { save() }
                            .fontWeight(.semibold)
                    }
                }
            }
        }
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
        .sensoryFeedback(.success, trigger: savedTick)
    }

    private var navigationTitle: String {
        if document != nil { return "Edycja" }
        return category == nil ? "Co dodajesz?" : "Nowy dokument"
    }

    private var hasChanges: Bool {
        guard category != nil else { return false }
        if let document {
            return title != document.title || owner != document.owner || number != document.number
                || notes != document.notes || expiryDate != document.expiryDate
        }
        return !title.isEmpty || !owner.isEmpty || !number.isEmpty || !notes.isEmpty || scanImageData != nil
    }

    // MARK: Formularz

    private func form(_ category: DocumentCategory) -> some View {
        Form {
            Section {
                Picker("Rodzaj", selection: Binding(
                    get: { category },
                    set: { newValue in withAnimation { self.category = newValue } }
                )) {
                    ForEach(CategoryGroup.allCases) { group in
                        Section(group.title) {
                            ForEach(group.categories) { item in
                                Label(item.title, systemImage: item.symbol).tag(item)
                            }
                        }
                    }
                }
                field("Nazwa", text: $title, prompt: category.titlePlaceholder)
            }

            Section {
                DatePicker(category == .subscription ? "Następna płatność" : "Ważny do",
                           selection: $expiryDate, displayedComponents: .date)
                    .environment(\.locale, PL.locale)
                if isReading {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Odczytuję datę ze skanu…").foregroundStyle(.secondary)
                    }
                } else if let ocrMessage {
                    Label(ocrMessage, systemImage: ocrFound ? "text.viewfinder" : "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundStyle(ocrFound ? Color.secondary : Palette.soon)
                }
                Toggle("Przypomnienia", isOn: $remindersEnabled)
            } footer: {
                if remindersEnabled {
                    Text("Przypomnimy \(reminderSummary).")
                }
            }

            if category == .subscription {
                Section("Płatność") {
                    LabeledContent("Cena") {
                        HStack(spacing: 4) {
                            TextField("0", text: $priceText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                            Text("zł").foregroundStyle(.secondary)
                        }
                    }
                    Picker("Płacę", selection: $billingCycle) {
                        ForEach(BillingCycle.allCases) { Text($0.title).tag($0) }
                    }
                }
            }

            Section {
                field(category.ownerLabel, text: $owner, prompt: "Opcjonalnie")
                field(category.numberLabel, text: $number, prompt: "Opcjonalnie", characters: true)
            }

            Section {
                if let data = scanImageData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .frame(maxWidth: .infinity)
                    Button("Usuń skan", role: .destructive) {
                        withAnimation { scanImageData = nil; ocrMessage = nil }
                    }
                }
                if DocumentScanner.isSupported {
                    Button {
                        showingScanner = true
                    } label: {
                        Label(scanImageData == nil ? "Zeskanuj dokument" : "Zeskanuj ponownie",
                              systemImage: "doc.viewfinder")
                    }
                }
            } header: {
                Text("Skan")
            } footer: {
                if scanImageData == nil && DocumentScanner.isSupported {
                    Text("Ze skanu odczytamy datę ważności. Zdjęcie zostaje na telefonie.")
                }
            }

            Section("Notatki") {
                TextField("Np. gdzie leży oryginał", text: $notes, axis: .vertical)
                    .lineLimit(2...6)
            }
        }
    }

    private func field(_ label: String, text: Binding<String>, prompt: String, characters: Bool = false) -> some View {
        LabeledContent(label) {
            TextField(label, text: text, prompt: Text(prompt))
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(characters ? .characters : .sentences)
                .autocorrectionDisabled(characters)
        }
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

        withAnimation {
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
            let normalized = priceText.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: " ", with: "")
            target.price = Double(normalized)
            target.billingCycle = billingCycle
        } else {
            target.price = nil
            target.billingCycle = nil
        }
        if document == nil { context.insert(target) }
        savedTick += 1
        dismiss()
    }
}

// MARK: - Co dodajesz?

struct CategoryPicker: View {
    let canScan: Bool
    let onPick: (DocumentCategory) -> Void
    let onScan: () -> Void

    var body: some View {
        List {
            if canScan {
                Section {
                    Button(action: onScan) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Zeskanuj dokument").foregroundStyle(.primary)
                                Text("Rozpoznamy rodzaj i datę ważności")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "doc.viewfinder")
                        }
                    }
                }
            }

            ForEach(CategoryGroup.allCases) { group in
                Section(group.title) {
                    ForEach(group.categories.filter { $0 != .other }) { item in
                        row(item, color: group.color)
                    }
                }
            }

            Section {
                row(.other, color: .secondary)
            }
        }
        .listStyle(.insetGrouped)
    }

    private func row(_ item: DocumentCategory, color: Color) -> some View {
        Button { onPick(item) } label: {
            HStack {
                Label {
                    Text(item.title).foregroundStyle(.primary)
                } icon: {
                    Image(systemName: item.symbol).foregroundStyle(color)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
    }
}
