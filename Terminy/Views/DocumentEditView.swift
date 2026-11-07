import SwiftUI
import SwiftData
import PhotosUI

/// Dodawanie i edycja dokumentu: własny ekran z podglądem karty na żywo.
struct DocumentEditView: View {
    let document: Document?
    var startScanning = false

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
    @State private var autoScanDone = false
    @State private var photoItem: PhotosPickerItem?
    @State private var isReading = false
    @State private var ocrMessage: String?
    @State private var ocrFound = false
    @State private var showCalendar = false
    @State private var savedTick = 0
    @FocusState private var focused: Field?

    private enum Field { case title, owner, number, price, notes }

    init(document: Document?, initialCategory: DocumentCategory = .other, startScanning: Bool = false) {
        self.document = document
        self.startScanning = startScanning
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

    private var group: CategoryGroup { category.group }

    private var knownOwners: [String] {
        Array(Set(allDocuments.map(\.owner).filter { !$0.isEmpty })).sorted()
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Palette.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    topBar
                    preview
                    scanSection
                    categorySection
                    detailsSection
                    dateSection
                    if category == .subscription { subscriptionSection }
                    notesSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 110)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)

            saveBar
        }
        .presentationDetents([.large])
        .presentationCornerRadius(34)
        .presentationBackground(Palette.bg)
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.selection, trigger: category)
        .sensoryFeedback(.success, trigger: savedTick)
        .onAppear {
            guard startScanning, !autoScanDone else { return }
            autoScanDone = true
            if DocumentScanner.isSupported { showingScanner = true }
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

    // MARK: Pasek u góry

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 44, height: 44)
                    .background(Palette.panel, in: Circle())
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel("Zamknij")
            Spacer()
            Text(document == nil ? "Nowy dokument" : "Edycja")
                .font(.system(size: 17, weight: .heavy))
                .foregroundStyle(Palette.ink)
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
    }

    // MARK: Podgląd karty na żywo

    private var preview: some View {
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now),
                                                   to: Calendar.current.startOfDay(for: expiryDate)).day ?? 0
        let headline = DaysText.headline(to: expiryDate)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(category.title.uppercased())
                    .font(.system(size: 12, weight: .heavy)).tracking(0.5).opacity(0.75)
                Spacer()
                Image(systemName: category.symbol)
                    .font(.system(size: 18, weight: .bold))
                    .opacity(0.8)
                    .contentTransition(.symbolEffect(.replace))
            }
            Text(title.isEmpty ? category.title : title)
                .font(.system(size: 24, weight: .heavy)).tracking(-0.6)
                .lineLimit(1)
                .opacity(title.isEmpty ? 0.55 : 1)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(days < 0 ? "\(-days) \(DaysText.dni(-days)) po" : (days == 0 ? "Dziś" : headline.big))
                    .font(.system(size: 40, weight: .heavy).monospacedDigit()).tracking(-1.5)
                    .contentTransition(.numericText())
                if days > 0, let rest = headline.rest {
                    Text("i " + rest)
                        .font(.system(size: 15, weight: .heavy))
                        .opacity(0.8)
                        .lineLimit(2)
                        .contentTransition(.numericText())
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                Text("do " + PL.date(expiryDate))
                if !owner.isEmpty { Text("· " + owner) }
            }
            .font(.system(size: 13, weight: .bold))
            .opacity(0.8)
        }
        .foregroundStyle(days < 0 ? Color.white : group.ink)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(days < 0 ? Palette.alert : group.color,
                    in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: group.color.opacity(0.35), radius: 16, y: 10)
        .animation(.spring(duration: 0.45, bounce: 0.25), value: category)
        .animation(.spring(duration: 0.45, bounce: 0.25), value: expiryDate)
    }

    // MARK: Skan

    private var scanSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if DocumentScanner.isSupported {
                    Button { showingScanner = true } label: {
                        bigAction(symbol: "doc.viewfinder", title: "Skanuj", caption: "data odczyta się sama",
                                  fg: Palette.bg, bg: Palette.ink, iconBg: Palette.accent, iconFg: Palette.accentInk)
                    }
                    .buttonStyle(PressScaleStyle())
                }
                PhotosPicker(selection: $photoItem, matching: .images) {
                    bigAction(symbol: "photo.fill", title: "Z galerii", caption: "zdjęcie dokumentu",
                              fg: Palette.ink, bg: Palette.panel, iconBg: Palette.tile, iconFg: Palette.ink)
                }
                .buttonStyle(PressScaleStyle())
            }

            if isReading {
                HStack(spacing: 10) {
                    ProgressView().tint(Palette.ink)
                    Text("Odczytuję datę…").font(.system(size: 14, weight: .bold))
                }
                .foregroundStyle(Palette.ink)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else if let ocrMessage {
                HStack(spacing: 10) {
                    Image(systemName: ocrFound ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .font(.system(size: 18, weight: .bold))
                    Text(ocrMessage).font(.system(size: 13, weight: .bold))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(ocrFound ? CategoryGroup.personal.ink : Color.white)
                .padding(14)
                .background(ocrFound ? CategoryGroup.personal.color : Palette.alert,
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .transition(.scale(scale: 0.95).combined(with: .opacity))
            }

            if let data = scanImageData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 150)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        Button {
                            withAnimation { scanImageData = nil; ocrMessage = nil }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .heavy))
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .background(.black.opacity(0.55), in: Circle())
                        }
                        .padding(10)
                        .accessibilityLabel("Usuń skan")
                    }
            }
        }
    }

    private func bigAction(symbol: String, title: String, caption: String,
                           fg: Color, bg: Color, iconBg: Color, iconFg: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(iconFg)
                .frame(width: 40, height: 40)
                .background(iconBg, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 16, weight: .heavy))
                Text(caption).font(.system(size: 12, weight: .semibold)).opacity(0.65).lineLimit(1)
            }
        }
        .foregroundStyle(fg)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(bg, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    // MARK: Rodzaj

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Rodzaj")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(DocumentCategory.allCases) { cat in
                    let isOn = cat == category
                    Button {
                        withAnimation(.spring(duration: 0.35, bounce: 0.3)) { pick(cat) }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: cat.symbol)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(isOn ? cat.group.ink : cat.group.color)
                                .frame(width: 20)
                            Text(cat == .other ? "Inny" : cat.title)
                                .font(.system(size: 13, weight: .heavy))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(isOn ? cat.group.ink : Palette.ink)
                        .padding(.horizontal, 12)
                        .frame(height: 46)
                        .background(isOn ? cat.group.color : Palette.panel,
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(PressScaleStyle())
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
        }
    }

    private func pick(_ cat: DocumentCategory) {
        let old = category
        category = cat
        // Nowy dokument: termin podąża za typowym okresem ważności, dopóki nie zmienisz go ręcznie.
        if document == nil, scanImageData == nil,
           let oldDefault = Calendar.current.date(byAdding: old.defaultRenewal, to: .now),
           Calendar.current.isDate(oldDefault, inSameDayAs: expiryDate) {
            expiryDate = Calendar.current.date(byAdding: cat.defaultRenewal, to: .now) ?? expiryDate
        }
    }

    // MARK: Dane

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Dane")
            panel {
                field("Nazwa", placeholder: "np. \(examplePlaceholder)", text: $title, focus: .title)
                divider
                field("Czyje", placeholder: "np. Ja, Ania, Passat", text: $owner, focus: .owner)
                if !knownOwners.isEmpty && focused == .owner {
                    ScrollView(.horizontal) {
                        HStack(spacing: 6) {
                            ForEach(knownOwners, id: \.self) { name in
                                Button { owner = name; focused = nil } label: {
                                    Text(name)
                                        .font(.system(size: 13, weight: .heavy))
                                        .foregroundStyle(owner == name ? Palette.bg : Palette.ink)
                                        .padding(.horizontal, 12).frame(height: 32)
                                        .background(owner == name ? Palette.ink : Palette.tile, in: Capsule())
                                }
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .padding(.bottom, 10)
                }
                divider
                field(numberLabel, placeholder: "opcjonalnie", text: $number, focus: .number, characters: true)
            }
        }
    }

    private var examplePlaceholder: String {
        switch category {
        case .carInsurance: "OC Passat"
        case .carInspection: "Przegląd Passat"
        case .drivingLicense: "Prawo jazdy"
        case .homeInsurance: "Polisa mieszkania"
        case .passport: "Paszport"
        case .idCard: "Dowód osobisty"
        case .subscription: "Netflix"
        case .other: "Gwarancja pralki"
        }
    }

    private var numberLabel: String {
        switch category {
        case .carInsurance, .homeInsurance: "Numer polisy"
        case .carInspection: "Rejestracja"
        case .passport, .idCard, .drivingLicense: "Numer dokumentu"
        case .subscription: "Konto / e-mail"
        case .other: "Numer"
        }
    }

    // MARK: Termin

    private var dateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(category == .subscription ? "Następne odnowienie" : "Ważne do")
            panel {
                Button {
                    withAnimation(.spring(duration: 0.4, bounce: 0.2)) { showCalendar.toggle(); focused = nil }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(PL.date(expiryDate))
                                .font(.system(size: 20, weight: .heavy)).tracking(-0.4)
                                .contentTransition(.numericText())
                            Text("wygasa za " + DaysText.long(to: expiryDate))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Palette.muted)
                        }
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 13, weight: .heavy))
                            .rotationEffect(.degrees(showCalendar ? 180 : 0))
                    }
                    .foregroundStyle(Palette.ink)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        quick("+1 mies.", DateComponents(month: 1))
                        quick("+1 rok", DateComponents(year: 1))
                        quick("+2 lata", DateComponents(year: 2))
                        quick("+5 lat", DateComponents(year: 5))
                        quick("+10 lat", DateComponents(year: 10))
                    }
                }
                .scrollIndicators(.hidden)
                .padding(.bottom, 12)

                if showCalendar {
                    divider
                    MonthPicker(date: $expiryDate, accent: group.color, accentInk: group.ink)
                        .padding(.vertical, 12)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                divider
                HStack(spacing: 12) {
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Palette.alert, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Toggle(isOn: $remindersEnabled) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Przypomnienia").font(.system(size: 15, weight: .bold))
                            Text("30 i 7 dni przed oraz w dniu terminu")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Palette.muted)
                        }
                    }
                    .tint(Palette.switchOn)
                }
                .foregroundStyle(Palette.ink)
                .padding(.vertical, 12)
            }
        }
    }

    private func quick(_ label: String, _ period: DateComponents) -> some View {
        let target = Calendar.current.date(byAdding: period, to: Calendar.current.startOfDay(for: .now)) ?? .now
        let isOn = Calendar.current.isDate(target, inSameDayAs: expiryDate)
        return Button {
            withAnimation(.spring(duration: 0.4, bounce: 0.3)) { expiryDate = target }
        } label: {
            Text(label)
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(isOn ? group.ink : Palette.ink)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(isOn ? group.color : Palette.tile, in: Capsule())
        }
        .buttonStyle(PressScaleStyle())
    }

    // MARK: Abonament

    private var subscriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Abonament")
            panel {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        fieldLabel("Cena")
                        TextField("0", value: $price, format: .number.precision(.fractionLength(0...2)))
                            .font(.system(size: 22, weight: .heavy))
                            .keyboardType(.decimalPad)
                            .focused($focused, equals: .price)
                    }
                    Text("zł").font(.system(size: 17, weight: .heavy)).foregroundStyle(Palette.muted)
                }
                .foregroundStyle(Palette.ink)
                .padding(.vertical, 12)
                divider
                HStack(spacing: 6) {
                    ForEach(BillingCycle.allCases) { cycle in
                        let isOn = cycle == billingCycle
                        Button {
                            withAnimation(.spring(duration: 0.3)) { billingCycle = cycle }
                        } label: {
                            Text(cycle.title)
                                .font(.system(size: 13, weight: .heavy))
                                .foregroundStyle(isOn ? Palette.bg : Palette.ink)
                                .frame(maxWidth: .infinity)
                                .frame(height: 38)
                                .background(isOn ? Palette.ink : Palette.tile, in: Capsule())
                        }
                        .buttonStyle(PressScaleStyle())
                    }
                }
                .padding(.vertical, 12)
            }
        }
    }

    // MARK: Notatki

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Notatki")
            panel {
                TextField("Np. ubezpieczyciel, gdzie leży oryginał", text: $notes, axis: .vertical)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(3...8)
                    .focused($focused, equals: .notes)
                    .padding(.vertical, 14)
            }
        }
    }

    // MARK: Zapis

    private var saveBar: some View {
        HStack(spacing: 8) {
            if focused != nil {
                Button { focused = nil } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 56, height: 56)
                        .background(Palette.panel, in: Circle())
                }
                .accessibilityLabel("Schowaj klawiaturę")
            }
            Button(action: save) {
                Label(document == nil ? "Zapisz dokument" : "Zapisz zmiany", systemImage: "checkmark")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(Palette.bg)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Palette.ink, in: Capsule())
                    .shadow(color: Color(hex: 0x0A0C14).opacity(0.25), radius: 14, y: 8)
            }
        }
        .buttonStyle(PressScaleStyle())
        .padding(.horizontal, 16)
        .padding(.top, 24)
        .padding(.bottom, 8)
        .background {
            LinearGradient(colors: [Palette.bg.opacity(0), Palette.bg], startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }

    // MARK: Klocki

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .heavy)).tracking(0.6)
            .foregroundStyle(Palette.muted)
            .padding(.horizontal, 6)
            .padding(.top, 4)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .heavy)).tracking(0.5)
            .foregroundStyle(Palette.muted)
    }

    private func panel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(.horizontal, 16)
            .background(Palette.panel, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var divider: some View {
        Rectangle().fill(Palette.line).frame(height: 1)
    }

    private func field(_ label: String, placeholder: String, text: Binding<String>,
                       focus: Field, characters: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            fieldLabel(label)
            TextField(placeholder, text: text)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Palette.ink)
                .focused($focused, equals: focus)
                .textInputAutocapitalization(characters ? .characters : .sentences)
                .autocorrectionDisabled(characters)
                .submitLabel(.next)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture { focused = focus }
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

        withAnimation(.spring(duration: 0.45, bounce: 0.25)) {
            if let date = DateExtractor().bestExpiryDate(in: text) {
                expiryDate = date
                ocrFound = true
                ocrMessage = "Odczytano datę \(PL.date(date)). Sprawdź, czy się zgadza."
            } else {
                ocrFound = false
                ocrMessage = "Nie udało się odczytać daty. Ustaw ją niżej."
            }
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
        savedTick += 1
        dismiss()
    }
}

// MARK: - Własny wybór daty

/// Miesiąc z dniami do wyboru, z przewijaniem miesięcy i lat.
struct MonthPicker: View {
    @Binding var date: Date
    let accent: Color
    let accentInk: Color

    @State private var month: Date = .now
    private let cal = PL.calendar

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                arrow("chevron.left.2", "Rok wcześniej") { move(year: -1) }
                arrow("chevron.left", "Miesiąc wcześniej") { move(month: -1) }
                Spacer()
                Text(title)
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(Palette.ink)
                    .contentTransition(.numericText())
                Spacer()
                arrow("chevron.right", "Miesiąc później") { move(month: 1) }
                arrow("chevron.right.2", "Rok później") { move(year: 1) }
            }

            let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(PL.weekdays, id: \.self) { name in
                    Text(name).font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.muted)
                }
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    if let day {
                        let isOn = cal.isDate(day, inSameDayAs: date)
                        let isToday = cal.isDateInToday(day)
                        Button {
                            withAnimation(.spring(duration: 0.3, bounce: 0.3)) { date = day }
                        } label: {
                            Text("\(cal.component(.day, from: day))")
                                .font(.system(size: 15, weight: isOn || isToday ? .heavy : .semibold).monospacedDigit())
                                .foregroundStyle(isOn ? accentInk : Palette.ink)
                                .frame(maxWidth: .infinity)
                                .frame(height: 38)
                                .background {
                                    if isOn {
                                        Circle().fill(accent)
                                    } else if isToday {
                                        Circle().strokeBorder(Palette.line, lineWidth: 2)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear.frame(height: 38)
                    }
                }
            }
        }
        .onAppear { month = cal.dateInterval(of: .month, for: date)?.start ?? date }
        .onChange(of: date) { _, new in
            let start = cal.dateInterval(of: .month, for: new)?.start ?? new
            if start != month { withAnimation(.spring(duration: 0.3)) { month = start } }
        }
        .sensoryFeedback(.selection, trigger: date)
    }

    private var title: String {
        let c = cal.dateComponents([.year, .month], from: month)
        return "\(PL.months[(c.month ?? 1) - 1]) \(c.year ?? 0)"
    }

    private var days: [Date?] {
        guard let range = cal.range(of: .day, in: .month, for: month) else { return [] }
        let leading = (cal.component(.weekday, from: month) + 5) % 7
        var result: [Date?] = Array(repeating: nil, count: leading)
        for day in range { result.append(cal.date(byAdding: .day, value: day - 1, to: month)) }
        while result.count % 7 != 0 { result.append(nil) }
        return result
    }

    private func move(month delta: Int = 0, year: Int = 0) {
        withAnimation(.spring(duration: 0.3)) {
            month = cal.date(byAdding: DateComponents(year: year, month: delta), to: month) ?? month
        }
    }

    private func arrow(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(Palette.ink)
                .frame(width: 34, height: 34)
                .background(Palette.tile, in: Circle())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(label)
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
