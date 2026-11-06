import SwiftUI
import SwiftData
import PhotosUI

struct DocumentEditView: View {
    let document: Document?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var allDocuments: [Document]

    @State private var category: DocumentCategory
    @State private var title: String
    @State private var owner: String
    @State private var number: String
    @State private var expiryDate: Date
    @State private var notes: String
    @State private var remindersEnabled: Bool
    @State private var price: Double?
    @State private var billingCycle: BillingCycle
    @State private var scanImageData: Data?

    @State private var showingScanner = false
    @State private var photoItem: PhotosPickerItem?
    @State private var isReading = false
    @State private var ocrMessage: String?

    init(document: Document?, initialCategory: DocumentCategory = .other) {
        self.document = document
        let cat = document?.category ?? initialCategory
        _category = State(initialValue: cat)
        _title = State(initialValue: document?.title ?? "")
        _owner = State(initialValue: document?.owner ?? "")
        _number = State(initialValue: document?.number ?? "")
        _expiryDate = State(initialValue: document?.expiryDate
            ?? Calendar.current.date(byAdding: cat.defaultRenewal, to: .now) ?? .now)
        _notes = State(initialValue: document?.notes ?? "")
        _remindersEnabled = State(initialValue: document?.remindersEnabled ?? true)
        _price = State(initialValue: document?.price)
        _billingCycle = State(initialValue: document?.billingCycle ?? .monthly)
        _scanImageData = State(initialValue: document?.scanImageData)
    }

    private var knownOwners: [String] {
        Array(Set(allDocuments.map(\.owner).filter { !$0.isEmpty })).sorted()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Rodzaj", selection: $category) {
                        ForEach(DocumentCategory.allCases) { cat in
                            Label(cat.title, systemImage: cat.symbol).tag(cat)
                        }
                    }
                    TextField(category.title, text: $title)
                    HStack {
                        TextField("Czyje (np. Ja, Ania, Passat)", text: $owner)
                        if !knownOwners.isEmpty {
                            Menu {
                                ForEach(knownOwners, id: \.self) { name in
                                    Button(name) { owner = name }
                                }
                            } label: {
                                Image(systemName: "person.crop.circle.badge.checkmark")
                            }
                        }
                    }
                    TextField(numberPlaceholder, text: $number)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }

                Section {
                    DatePicker(category == .subscription ? "Następne odnowienie" : "Ważne do",
                               selection: $expiryDate, displayedComponents: .date)
                    Toggle("Przypomnij 30 i 7 dni przed", isOn: $remindersEnabled)
                } footer: {
                    if let ocrMessage {
                        Text(ocrMessage)
                    }
                }

                if category == .subscription {
                    Section("Subskrypcja") {
                        TextField("Cena", value: $price, format: .currency(code: "PLN"))
                            .keyboardType(.decimalPad)
                        Picker("Rozliczenie", selection: $billingCycle) {
                            ForEach(BillingCycle.allCases) { Text($0.title).tag($0) }
                        }
                    }
                }

                Section("Skan i odczyt daty") {
                    if let data = scanImageData, let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    if DocumentScanner.isSupported {
                        Button {
                            showingScanner = true
                        } label: {
                            Label("Skanuj dokument", systemImage: "doc.viewfinder")
                        }
                    }
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Wybierz zdjęcie", systemImage: "photo")
                    }
                    if isReading {
                        HStack { ProgressView(); Text("Odczytuję datę…").foregroundStyle(.secondary) }
                    }
                    if scanImageData != nil {
                        Button("Usuń skan", role: .destructive) { scanImageData = nil }
                    }
                }

                Section("Notatki") {
                    TextField("Np. ubezpieczyciel, numer polisy, gdzie leży oryginał", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .navigationTitle(document == nil ? "Nowy dokument" : "Edycja")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anuluj") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Zapisz", action: save)
                }
            }
            .fullScreenCover(isPresented: $showingScanner) {
                DocumentScanner { pages in
                    Task { await handle(images: pages) }
                }
                .ignoresSafeArea()
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        await handle(images: [image])
                    }
                    photoItem = nil
                }
            }
        }
    }

    private var numberPlaceholder: String {
        switch category {
        case .carInsurance: "Numer polisy"
        case .carInspection: "Numer rejestracyjny"
        case .passport, .idCard, .drivingLicense: "Numer dokumentu"
        case .subscription: "Konto / e-mail"
        case .other: "Numer (opcjonalnie)"
        }
    }

    private func handle(images: [UIImage]) async {
        guard let first = images.first else { return }
        scanImageData = first.downscaled(maxDimension: 1600).jpegData(compressionQuality: 0.6)

        isReading = true
        defer { isReading = false }

        var text = ""
        for image in images {
            if let pageText = try? await TextRecognizer.recognizeText(in: image) {
                text += pageText + "\n"
            }
        }

        if let date = DateExtractor().bestExpiryDate(in: text) {
            expiryDate = date
            ocrMessage = "Odczytano datę \(date.formatted(date: .long, time: .omitted)). Sprawdź, czy się zgadza."
        } else {
            ocrMessage = "Nie udało się odczytać daty – ustaw ją ręcznie."
        }
    }

    private func save() {
        let target = document ?? Document()
        target.category = category
        target.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        target.owner = owner.trimmingCharacters(in: .whitespacesAndNewlines)
        target.number = number.trimmingCharacters(in: .whitespacesAndNewlines)
        target.expiryDate = expiryDate
        target.notes = notes
        target.remindersEnabled = remindersEnabled
        target.scanImageData = scanImageData
        if category == .subscription {
            target.price = price
            target.billingCycle = billingCycle
        } else {
            target.price = nil
            target.billingCycle = nil
        }
        if document == nil { context.insert(target) }
        dismiss()
    }
}

private extension UIImage {
    func downscaled(maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return self }
        let scale = maxDimension / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
