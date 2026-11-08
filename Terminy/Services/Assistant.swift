import Foundation

/// Asystent: odpowiada na pytania o dokumenty po polsku. Działa w całości na telefonie,
/// bez internetu i bez wysyłania danych. Rozumie rodzaj dokumentu, osobę, okres
/// („w marcu”, „w tym tygodniu”, „w 2027”) i intencję (kiedy, co wygasa, ile kosztuje,
/// co po terminie, jak odnowić).
struct Assistant {
    struct Reply: Equatable {
        var text: String
        /// Dokumenty pokazane pod odpowiedzią (do otwarcia).
        var documentIDs: [UUID] = []
        /// Przyciski pod odpowiedzią: przejście w miejsce w aplikacji albo gotowe pytanie.
        var actions: [Action] = []
    }

    /// Co można zrobić prosto z odpowiedzi.
    enum Action: Hashable {
        case open(UUID)
        case renew(UUID)
        case add(DocumentCategory?)
        case scan
        case backup
        case plus
        case settings
        case siriHelp
        case report
        case ask(String)

        var title: String {
            switch self {
            case .open: "Otwórz"
            case .renew: "Odnów"
            case .add(let category): category.map { "Dodaj: \(Assistant.categoryName($0))" } ?? "Dodaj dokument"
            case .scan: "Zeskanuj"
            case .backup: "Kopia zapasowa"
            case .plus: "Terminek Plus"
            case .settings: "Ustawienia"
            case .siriHelp: "Siri i skróty"
            case .report: "Zgłoś problem"
            case .ask(let question): question
            }
        }

        var symbol: String {
            switch self {
            case .open: "arrow.up.right"
            case .renew: "arrow.clockwise"
            case .add: "plus"
            case .scan: "doc.viewfinder"
            case .backup: "lock.doc"
            case .plus: "sparkles"
            case .settings: "gearshape"
            case .siriHelp: "mic"
            case .report: "ladybug"
            case .ask: "text.bubble"
            }
        }
    }

    /// Stan aplikacji, o który asystent może być zapytany (ustawienia, plan, kopia).
    struct AppState: Equatable {
        var isPlus = false
        var questionsLeft: Int?
        var usesCloud = false
        var lockEnabled = true
        var biometry = "Face ID"
        var reminderHour = 9
        var offsets = [30, 7, 0]
        var lastBackup: Date?
        var notificationsAllowed: Bool?
    }

    enum Intent: Equatable {
        case help, cost, expired, howToRenew, count, upcoming, when
        case number, details, reminders, renewNow, summary, missing, unknown
    }

    var calendar: Calendar = PL.calendar
    var now: Date = .now
    var state = AppState()

    // MARK: Odpowiedź

    func answer(_ question: String, documents: [Document]) -> Reply {
        let q = Self.fold(question).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return Self.help(documents) }

        let category = Self.category(in: q)
        let owner = Self.ownerMatch(in: q, documents: documents)
        let titled = Self.titleMatches(in: q, documents: documents)
        let mentionsDocument = category != nil || owner != nil || !titled.isEmpty

        // 1. Rzeczy, w których nie pomagamy, i rozmowa (powitanie, podziękowanie).
        if let reply = refusal(q, mentionsDocument: mentionsDocument) { return reply }
        if let reply = smallTalk(q, documents: documents) { return reply }

        let intent = Self.intent(in: q, mentionsDocument: mentionsDocument)
        if intent == .help { return Self.help(documents) }

        // 2. Pytania o samą aplikację (skan, kopia, Plus, Siri…), o ile nie dotyczą konkretnego dokumentu.
        if let reply = knowledge(q, intent: intent, mentionsDocument: mentionsDocument, documents: documents) { return reply }

        let range = period(in: q)
        var docs = documents.sorted { $0.expiryDate < $1.expiryDate }
        if let category { docs = docs.filter { $0.category == category } }
        else if !titled.isEmpty { docs = docs.filter { titled.contains($0.id) } }
        if let owner { docs = docs.filter { Self.fold($0.owner) == owner } }

        if documents.isEmpty, intent != .howToRenew {
            return Reply(text: "Nie masz jeszcze żadnych dokumentów, więc nie mam czego sprawdzić. Dodaj pierwszy (najszybciej skanem), a potem pytaj o terminy.",
                         actions: [.scan, .add(category)])
        }

        switch intent {
        case .howToRenew:
            let target = category ?? docs.first?.category ?? .other
            let mine = mentionsDocument ? Array(docs.prefix(3)) : []
            var text = Self.renewalTip(for: target)
            if let first = mine.first { text += "\n\nTwój termin: " + sentence(for: first) }
            return Reply(text: text, documentIDs: mine.map(\.id), actions: mine.first.map { [.renew($0.id)] } ?? [])

        case .renewNow:
            guard mentionsDocument else {
                return clarify("Który dokument mam odnowić?", documents: documents) { "Odnów \($0.displayTitle)" }
            }
            guard let first = docs.first else { return missingDocument(category) }
            let date = PL.date(first.renewedExpiryDate(now: now, calendar: calendar))
            return Reply(text: "Mogę przesunąć „\(first.displayTitle)” z \(PL.date(first.expiryDate)) na \(date). Stuknij „Odnów”, jeśli masz już nowy dokument albo zapłaconą polisę. Datę możesz też ustawić ręcznie w edycji.",
                         documentIDs: [first.id], actions: [.renew(first.id), .open(first.id)])

        case .cost:
            return costAnswer(q, docs: docs, titled: !titled.isEmpty, documents: documents)

        case .count:
            let expired = documents.filter { days($0) < 0 }.count
            let soon = documents.filter { (0...30).contains(days($0)) }.count
            var text = "Masz \(Self.documentsCount(documents.count))."
            let groups = CategoryGroup.allCases.compactMap { group -> String? in
                let n = documents.filter { $0.group == group }.count
                return n > 0 ? "\(group.title.lowercased()): \(n)" : nil
            }
            if !groups.isEmpty { text += " Z tego " + Self.list(groups) + "." }
            if expired > 0 { text += " Po terminie: \(expired)." }
            if soon > 0 { text += " W ciągu 30 dni kończy się: \(soon)." }
            if !state.isPlus { text += " W darmowym planie zmieścisz \(Store.freeDocuments)." }
            return Reply(text: text)

        case .expired:
            let past = docs.filter { days($0) < 0 }
            guard !past.isEmpty else {
                return Reply(text: mentionsDocument ? "To jest ważne, nic tu nie jest po terminie." : "Wszystko jest ważne. Nic nie jest po terminie.")
            }
            let lines = past.prefix(5).map { "• " + sentence(for: $0) }.joined(separator: "\n")
            return Reply(text: "Po terminie: \(Self.documentsCount(past.count)).\n" + lines + "\n\nPo odnowieniu stuknij „Odnów” na karcie, a przesunę termin.",
                         documentIDs: past.map(\.id), actions: past.first.map { [.renew($0.id)] } ?? [])

        case .number:
            guard mentionsDocument else { return clarify("Numer którego dokumentu?", documents: documents) { "Numer \($0.displayTitle)" } }
            guard let first = docs.first else { return missingDocument(category) }
            let lines = docs.prefix(4).map { doc in
                doc.number.isEmpty ? "• \(doc.displayTitle): nie wpisano numeru." : "• \(doc.displayTitle), \(doc.category.numberLabel.lowercased()): \(doc.number)"
            }
            return Reply(text: lines.joined(separator: "\n"), documentIDs: docs.prefix(4).map(\.id),
                         actions: first.number.isEmpty ? [.open(first.id)] : [])

        case .details:
            guard mentionsDocument else { return clarify("O którym dokumencie mam powiedzieć więcej?", documents: documents) { "Co wiesz o \($0.displayTitle)?" } }
            guard let first = docs.first else { return missingDocument(category) }
            return Reply(text: details(for: first), documentIDs: [first.id], actions: [.open(first.id), .renew(first.id)])

        case .reminders:
            guard mentionsDocument else { return Self.remindersGeneral(state) }
            guard let first = docs.first else { return missingDocument(category) }
            return Reply(text: reminderText(for: first), documentIDs: [first.id], actions: [.open(first.id)])

        case .summary:
            return summary(documents)

        case .missing:
            return missingSuggestions(documents)

        case .upcoming, .when, .unknown:
            if let range {
                let inRange = docs.filter { range.contains($0.expiryDate) }
                let when = range.label.capitalizedFirst
                guard !inRange.isEmpty else {
                    let what = category.map { " (" + Self.categoryName($0) + ")" } ?? ""
                    var text = when + " nic się nie kończy" + what + "."
                    if let next = docs.first(where: { days($0) >= 0 && $0.expiryDate >= range.end }) {
                        text += " Następny termin: " + sentence(for: next)
                    }
                    return Reply(text: text)
                }
                let lines = inRange.prefix(5).map { "• " + sentence(for: $0) }.joined(separator: "\n")
                return Reply(text: when + " kończy się: " + Self.documentsCount(inRange.count) + ".\n" + lines,
                             documentIDs: inRange.map(\.id))
            }

            if mentionsDocument {
                guard let first = docs.first else { return missingDocument(category) }
                if docs.count == 1 {
                    return Reply(text: details(for: first, short: true), documentIDs: [first.id],
                                 actions: days(first) <= 30 ? [.renew(first.id)] : [])
                }
                let lines = docs.prefix(5).map { "• " + sentence(for: $0) }.joined(separator: "\n")
                return Reply(text: "Masz \(Self.documentsCount(docs.count)) tego rodzaju:\n" + lines, documentIDs: docs.prefix(5).map(\.id))
            }

            if intent == .unknown { return fallback(documents) }
            if intent == .when, !Self.has(q, ["najblizsz", "najpierw", "pierwsz", "najszybciej", "co sie konczy", "co wygasa"]) {
                return clarify("O który dokument pytasz?", documents: documents) { "Kiedy kończy się \($0.displayTitle)?" }
            }

            // Najbliższe terminy (i to, co już minęło, bo to najpilniejsze).
            let expired = docs.filter { days($0) < 0 }
            let upcoming = docs.filter { days($0) >= 0 }.prefix(3)
            guard let first = upcoming.first else {
                return Reply(text: expired.isEmpty ? "Nie ma przed Tobą żadnych terminów." : "Przyszłych terminów nie ma, ale \(Self.documentsCount(expired.count)) jest po terminie.",
                             documentIDs: expired.map(\.id))
            }
            var text = "Najbliżej: " + sentence(for: first)
            if upcoming.count > 1 { text += "\nPotem:\n" + upcoming.dropFirst().map { "• " + sentence(for: $0) }.joined(separator: "\n") }
            if !expired.isEmpty { text += "\n\nUwaga: po terminie jest \(Self.documentsCount(expired.count))." }
            return Reply(text: text, documentIDs: (expired + upcoming).map(\.id))

        case .help:
            return Self.help(documents)
        }
    }

    // MARK: Odpowiedzi złożone

    private func days(_ doc: Document) -> Int { doc.daysLeft(from: now, calendar: calendar) }

    /// Pełny opis dokumentu: termin, ile zostało, po odnowieniu, przypomnienie, dane.
    func details(for doc: Document, short: Bool = false) -> String {
        var lines = [sentence(for: doc)]
        let d = days(doc)
        if d > 60 { lines.append("To \(DaysText.long(to: doc.expiryDate, from: now)).") }
        if let next = nextReminder(for: doc) {
            lines.append("Przypomnę \(PL.dayAndMonth(next.fireDate)) o \(state.reminderHour):00.")
        } else if !doc.remindersEnabled {
            lines.append("Przypomnienia dla tego dokumentu są wyłączone.")
        }
        if !short || d <= 30 {
            lines.append("Po odnowieniu termin przesunie się na \(PL.date(doc.renewedExpiryDate(now: now, calendar: calendar))).")
        }
        guard !short else { return lines.joined(separator: " ") }
        if !doc.owner.isEmpty { lines.append("\(doc.category.ownerLabel): \(doc.owner).") }
        if !doc.number.isEmpty { lines.append("\(doc.category.numberLabel): \(doc.number).") }
        if doc.category == .subscription, let price = doc.price {
            lines.append("Cena: \(PL.money(price)) / \((doc.billingCycle ?? .monthly).shortTitle), rocznie ok. \(PL.money(doc.monthlyCost * 12)).")
        }
        if doc.scanPageCount > 0 || doc.scanImageData != nil {
            lines.append("Masz skan (\(PL.pages(max(1, doc.scanPageCount)))).")
        }
        if !doc.notes.isEmpty { lines.append("Notatka: \(doc.notes)") }
        return lines.joined(separator: "\n")
    }

    private func nextReminder(for doc: Document) -> NotificationScheduler.PlannedReminder? {
        NotificationScheduler.plannedReminders(for: [doc], hour: state.reminderHour, now: now,
                                               offsets: state.offsets, calendar: calendar).first
    }

    private func reminderText(for doc: Document) -> String {
        guard doc.remindersEnabled else {
            return "Przypomnienia dla „\(doc.displayTitle)” są wyłączone. Włączysz je dzwonkiem na karcie dokumentu."
        }
        let planned = NotificationScheduler.plannedReminders(for: [doc], hour: state.reminderHour, now: now,
                                                             offsets: state.offsets, calendar: calendar)
        let custom = doc.customOffsets != nil ? " (własne ustawienia tego dokumentu)" : ""
        guard !planned.isEmpty else {
            return "Dla „\(doc.displayTitle)” wszystkie przypomnienia już minęły\(custom). " + sentence(for: doc)
        }
        let lines = planned.prefix(4).map { "• \(PL.dayAndMonth($0.fireDate)), \(state.reminderHour):00" }.joined(separator: "\n")
        var text = "Przypomnienia o „\(doc.displayTitle)”\(custom):\n" + lines
        if state.notificationsAllowed == false {
            text += "\n\nUwaga: powiadomienia są wyłączone w Ustawieniach iPhone'a, więc nie przyjdą."
        }
        return text
    }

    private func costAnswer(_ q: String, docs: [Document], titled: Bool, documents: [Document]) -> Reply {
        let subs = (titled ? docs : documents).filter { $0.category == .subscription }
        guard !subs.isEmpty else {
            return Reply(text: "Nie masz dodanych subskrypcji. Dodaj np. Netflixa z ceną, a policzę, ile wydajesz miesięcznie i rocznie.",
                         actions: [.add(.subscription)])
        }
        let priced = subs.filter { $0.price != nil }
        let monthly = subs.reduce(0) { $0 + $1.monthlyCost }
        if titled, subs.count == 1, let sub = subs.first {
            guard let price = sub.price else {
                return Reply(text: "Przy „\(sub.displayTitle)” nie ma wpisanej ceny. Dopisz ją w edycji.", documentIDs: [sub.id], actions: [.open(sub.id)])
            }
            return Reply(text: "\(sub.displayTitle): \(PL.money(price)) / \((sub.billingCycle ?? .monthly).shortTitle), czyli ok. \(PL.money(sub.monthlyCost)) miesięcznie i \(PL.money(sub.monthlyCost * 12)) rocznie. " + sentence(for: sub),
                         documentIDs: [sub.id])
        }
        var text = "Subskrypcje kosztują Cię ok. \(PL.money(monthly)) miesięcznie, czyli \(PL.money(monthly * 12)) rocznie."
        if let top = priced.max(by: { $0.monthlyCost < $1.monthlyCost }), priced.count > 1 {
            text += " Najdroższa: \(top.displayTitle) (\(PL.money(top.monthlyCost)) mies.)."
        }
        let missing = subs.count - priced.count
        if missing > 0 { text += " Bez ceny: \(missing), więc kwota może być wyższa." }
        if let next = subs.first(where: { days($0) >= 0 }) {
            text += " Najbliższa płatność: \(next.displayTitle), \(DaysText.sentence(days(next)))."
        }
        return Reply(text: text, documentIDs: subs.sorted { $0.monthlyCost > $1.monthlyCost }.map(\.id))
    }

    private func summary(_ documents: [Document]) -> Reply {
        let expired = documents.filter { days($0) < 0 }.sorted { $0.expiryDate < $1.expiryDate }
        let soon = documents.filter { (0...30).contains(days($0)) }.sorted { $0.expiryDate < $1.expiryDate }
        var parts = ["Masz \(Self.documentsCount(documents.count))."]
        if expired.isEmpty && soon.isEmpty {
            parts.append("Wszystko jest ważne i w ciągu 30 dni nic się nie kończy. Spokojnie.")
        }
        if !expired.isEmpty { parts.append("Po terminie: " + Self.list(expired.map(\.displayTitle)) + ". To najpilniejsze.") }
        if !soon.isEmpty { parts.append("W ciągu 30 dni: " + Self.list(soon.map { "\($0.displayTitle) (\(DaysText.sentence(days($0))))" }) + ".") }
        let monthly = documents.reduce(0) { $0 + $1.monthlyCost }
        if monthly > 0 { parts.append("Abonamenty: ok. \(PL.money(monthly)) miesięcznie.") }
        if !state.usesCloud, state.lastBackup == nil {
            parts.append("Nie masz jeszcze kopii zapasowej, a dane są tylko na tym telefonie.")
        }
        var actions: [Action] = (expired + soon).prefix(1).map { .renew($0.id) }
        if !state.usesCloud, state.lastBackup == nil { actions.append(.backup) }
        return Reply(text: parts.joined(separator: " "), documentIDs: (expired + soon).prefix(5).map(\.id), actions: actions)
    }

    private func missingSuggestions(_ documents: [Document]) -> Reply {
        let have = Set(documents.map(\.category))
        var ideas: [(String, DocumentCategory)] = []
        if have.contains(.carInsurance) && !have.contains(.carInspection) { ideas.append(("Masz OC, ale nie przegląd auta", .carInspection)) }
        if have.contains(.carInspection) && !have.contains(.carInsurance) { ideas.append(("Masz przegląd, ale nie OC", .carInsurance)) }
        if (have.contains(.carInsurance) || have.contains(.carInspection)) && !have.contains(.drivingLicense) { ideas.append(("Prawo jazdy też ma termin", .drivingLicense)) }
        if !have.contains(.idCard) { ideas.append(("Dowód osobisty (ważny 10 lat)", .idCard)) }
        if !have.contains(.passport) { ideas.append(("Paszport, jeśli go masz", .passport)) }
        if !have.contains(.homeInsurance) { ideas.append(("Ubezpieczenie mieszkania", .homeInsurance)) }
        if !have.contains(.subscription) { ideas.append(("Abonamenty: Netflix, Spotify, telefon", .subscription)) }
        guard !ideas.isEmpty else {
            return Reply(text: "Masz już wszystkie typowe dokumenty. Możesz jeszcze dodać gwarancje, legitymacje czy kartę EKUZ jako „Inne”.",
                         actions: [.add(.other)])
        }
        let text = "Warto dodać:\n" + ideas.prefix(4).map { "• " + $0.0 }.joined(separator: "\n")
            + "\n\nPrzydadzą się też gwarancje, legitymacje i karta EKUZ (jako „Inne”)."
        return Reply(text: text, actions: ideas.prefix(3).map { .add($0.1) })
    }

    private func missingDocument(_ category: DocumentCategory?) -> Reply {
        let what = category.map(Self.categoryName) ?? "taki dokument"
        return Reply(text: "Nie widzę u Ciebie: \(what). Dodaj go, a będę pilnować terminu.", actions: [.add(category), .scan])
    }

    /// Pytanie doprecyzowujące z gotowymi pytaniami o konkretne dokumenty.
    private func clarify(_ text: String, documents: [Document], question: (Document) -> String) -> Reply {
        let options = documents.sorted { $0.expiryDate < $1.expiryDate }.filter { days($0) >= -30 }.prefix(4)
        guard !options.isEmpty else { return Reply(text: text) }
        return Reply(text: text, actions: options.map { .ask(question($0)) })
    }

    private func fallback(_ documents: [Document]) -> Reply {
        Reply(text: "Nie zrozumiałem tego pytania. Znam Twoje terminy i całą aplikację: skanowanie, przypomnienia, kopię zapasową, Plus i skróty Siri. Zapytaj inaczej albo wybierz poniżej.",
              actions: [.ask("Co mam najbliżej?"), .ask("Podsumuj moje dokumenty"), .ask("Jak zrobić kopię zapasową?"), .ask("Co umiesz?")])
    }

    static func list(_ items: [String]) -> String {
        guard items.count > 1 else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " i " + items[items.count - 1]
    }

    // MARK: Zdania

    func sentence(for doc: Document) -> String {
        let days = doc.daysLeft(from: now, calendar: calendar)
        let date = PL.date(doc.expiryDate)
        let name = doc.displayTitle + (doc.owner.isEmpty || doc.displayTitle.contains(doc.owner) ? "" : " (\(doc.owner))")
        if doc.category == .subscription {
            return days < 0 ? "\(name): płatność minęła \(date)." : "\(name): następna płatność \(date), \(DaysText.sentence(days))."
        }
        switch days {
        case ..<0: return "\(name): termin minął \(date), \(DaysText.sentence(days))."
        case 0: return "\(name): termin mija dziś."
        default: return "\(name): termin \(date), \(DaysText.sentence(days))."
        }
    }

    static func documentsCount(_ n: Int) -> String {
        let ones = n % 10, tens = n % 100
        let word = n == 1 ? "dokument" : (2...4).contains(ones) && !(12...14).contains(tens) ? "dokumenty" : "dokumentów"
        return "\(n) \(word)"
    }

    static let helpText = """
    Pomagam pilnować terminów i obsługiwać Terminka. Zapytaj np.:
    • Kiedy kończy się OC?
    • Co wygasa w marcu?
    • Ile płacę za subskrypcje?
    • Podsumuj moje dokumenty
    • Jaki jest numer mojego paszportu?
    • Jak odnowić dowód?
    • Jak zrobić kopię zapasową?
    Działam na telefonie, bez internetu. Nic nie wysyłam.
    """

    static func help(_ documents: [Document]) -> Reply {
        Reply(text: helpText, actions: documents.isEmpty
              ? [.scan, .add(nil), .ask("Jakie dokumenty mogę dodać?")]
              : [.ask("Co mam najbliżej?"), .ask("Podsumuj moje dokumenty"), .ask("Czego mi brakuje?")])
    }

    // MARK: Rozpoznawanie

    /// Małe litery bez polskich znaków: „Kiedy kończy się OC Ani?” → „kiedy konczy sie oc ani?”.
    static func fold(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "ł", with: "l")
            .folding(options: [.diacriticInsensitive], locale: PL.locale)
    }

    static func intent(in q: String, mentionsDocument: Bool = false) -> Intent {
        if has(q, ["co umiesz", "pomoc", "pomocy", "w czym pomozesz", "co potrafisz", "jak cie uzywac", "jak z toba"]) { return .help }
        if has(q, ["jak odnow", "jak wyrobi", "jak przedluz", "gdzie odnow", "gdzie wyrobi", "co potrzeb", "jak zalatwi", "gdzie zalatwi", "jak wymieni", "gdzie wymieni"]) { return .howToRenew }
        if has(q, ["podsumu", "sytuacj", "status", "jak wyglada", "co waznego", "raport", "co slychac", "wszystko w porzadku", "czy wszystko"]) { return .summary }
        if has(q, ["czego brakuje", "co jeszcze dodac", "co powinienem dodac", "co powinnam dodac", "o czym zapominam", "co warto dodac", "co dodac"]) { return .missing }
        if has(q, ["odnow", "przedluz", "oplacil", "zaplacil", "wymienil", "odebral", "mam nowy", "mam nowa", "mam juz nowy"]) { return .renewNow }
        if has(q, ["numer", " nr ", "nr.", "rejestracj", "tablic"]) && mentionsDocument { return .number }
        if has(q, ["przypomn", "powiadom", "alert"]) { return .reminders }
        if has(q, ["ile plac", "ile kosztuj", "ile wydaj", "koszt", "ile mnie", "suma", "miesiecznie", "rocznie", "cena", "ile place"]) { return .cost }
        if has(q, ["po terminie", "niewazn", "minal", "minely", "minela", "przetermin", "wygasl", "spoznion", "zalegl"]) { return .expired }
        if has(q, ["ile mam", "ile jest", "ile dokument", "ile wszystkich"]) { return .count }
        if has(q, ["szczegol", "info o", "informacje o", "wszystko o", "co wiesz o", "pokaz", "opowiedz o", "dane z"]) && mentionsDocument { return .details }
        if has(q, ["kiedy", "do kiedy", "wazn", "termin", "konczy", "wygasa", "koniec", "platnosc", "ile zostal", "ile dni", "jak dlugo", "zostalo"]) { return .when }
        if has(q, ["co mam", "co dalej", "najblizsz", "co sie konczy", "co nastepne", "najpilniejsz", "co pierwsze", "nadchodz", "kolejn"]) { return .upcoming }
        return mentionsDocument ? .when : .unknown
    }

    static func category(in q: String) -> DocumentCategory? {
        let words = " " + q.replacingOccurrences(of: #"[^a-z0-9 ]"#, with: " ", options: .regularExpression) + " "
        if has(words, ["prawo jazdy", "prawa jazdy", "prawko", "prawka"]) { return .drivingLicense }
        if has(words, ["paszport"]) { return .passport }
        if has(words, ["dowod", "dowodu", "dowodem"]) && !has(words, ["rejestracyj"]) { return .idCard }
        if has(words, ["przeglad", "badani"]) { return .carInspection }
        if has(words, [" oc ", "ubezpieczenie auta", "ubezpieczenie samochodu", "polisa auta", "polisy auta"]) { return .carInsurance }
        if has(words, ["mieszkani", "domu", "nieruchomos"]) { return .homeInsurance }
        if has(words, ["subskrypc", "abonament", "subskrybcj"]) { return .subscription }
        return nil
    }

    /// Osoba z pola „Czyj”, także w odmianie („Ania” → „Ani”, „Anię”, „Anią”).
    static func ownerMatch(in q: String, documents: [Document]) -> String? {
        let owners = Set(documents.map { fold($0.owner) }.filter { $0.count >= 3 && $0 != "ja" })
        let words = q.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        for owner in owners.sorted(by: { $0.count > $1.count }) {
            let stem = String(owner.prefix(max(3, owner.count - 1)))
            if words.contains(where: { $0.hasPrefix(stem) }) { return owner }
        }
        return nil
    }

    /// Dokumenty, których nazwa pada w pytaniu („Netflix”, „Passat”).
    static func titleMatches(in q: String, documents: [Document]) -> Set<UUID> {
        let words = Set(q.split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count >= 4 })
        let skip: Set<String> = ["kiedy", "konczy", "ważny", "wazny", "termin", "dokument", "polisa", "ubezpieczenie"]
        var result: Set<UUID> = []
        for doc in documents {
            let titleWords = fold(doc.title).split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count >= 4 && !skip.contains($0) }
            if titleWords.contains(where: { tw in words.contains { $0.hasPrefix(String(tw.prefix(max(4, tw.count - 2)))) } }) {
                result.insert(doc.id)
            }
        }
        return result
    }

    // MARK: Okres

    struct Period: Equatable {
        let start: Date
        let end: Date   // bez końca
        let label: String
        func contains(_ date: Date) -> Bool { date >= start && date < end }
    }

    private static let monthStems: [(stems: [String], label: String)] = [
        (["styczen", "stycznia", "styczniu"], "w styczniu"), (["luty", "lutego", "lutym"], "w lutym"),
        (["marzec", "marca", "marcu"], "w marcu"), (["kwiecien", "kwietnia", "kwietniu"], "w kwietniu"),
        (["maj", "maja", "maju"], "w maju"), (["czerwiec", "czerwca", "czerwcu"], "w czerwcu"),
        (["lipiec", "lipca", "lipcu"], "w lipcu"), (["sierpien", "sierpnia", "sierpniu"], "w sierpniu"),
        (["wrzesien", "wrzesnia", "wrzesniu"], "we wrześniu"), (["pazdziernik", "pazdziernika", "pazdzierniku"], "w październiku"),
        (["listopad", "listopada", "listopadzie"], "w listopadzie"), (["grudzien", "grudnia", "grudniu"], "w grudniu"),
    ]

    func period(in q: String) -> Period? {
        let today = calendar.startOfDay(for: now)
        let words = q.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        let year = words.compactMap(Int.init).first { (2000...2100).contains($0) }

        for (index, month) in Self.monthStems.enumerated() where words.contains(where: month.stems.contains) {
            let m = index + 1
            let current = calendar.component(.month, from: today)
            var y = year ?? calendar.component(.year, from: today)
            if year == nil, m < current { y += 1 }
            guard let start = calendar.date(from: DateComponents(year: y, month: m, day: 1)),
                  let end = calendar.date(byAdding: .month, value: 1, to: start) else { return nil }
            let label = month.label + (year != nil || y != calendar.component(.year, from: today) ? " \(y)" : "")
            return Period(start: start, end: end, label: label)
        }

        func span(_ start: Date, _ component: Calendar.Component, _ value: Int, _ label: String) -> Period? {
            calendar.date(byAdding: component, value: value, to: start).map { Period(start: start, end: $0, label: label) }
        }
        if Self.has(q, ["dzis", "dzisiaj"]) { return span(today, .day, 1, "dziś") }
        if Self.has(q, ["jutro"]) { return calendar.date(byAdding: .day, value: 1, to: today).flatMap { span($0, .day, 1, "jutro") } }
        if Self.has(q, ["w tym tygodniu", "ten tydzien", "w ciagu tygodnia", "7 dni", "tydzien"]) { return span(today, .day, 7, "w ciągu tygodnia") }
        if Self.has(q, ["przyszlym miesiacu", "nastepnym miesiacu", "przyszly miesiac"]) {
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: today)).flatMap { calendar.date(byAdding: .month, value: 1, to: $0) }
            return start.flatMap { span($0, .month, 1, "w przyszłym miesiącu") }
        }
        if Self.has(q, ["w tym miesiacu", "ten miesiac", "30 dni", "miesiac"]) { return span(today, .day, 30, "w ciągu 30 dni") }
        if Self.has(q, ["do konca roku", "w tym roku", "ten rok"]) {
            let y = calendar.component(.year, from: today)
            return calendar.date(from: DateComponents(year: y + 1, month: 1, day: 1)).map { Period(start: today, end: $0, label: "do końca roku") }
        }
        if Self.has(q, ["w przyszlym roku", "nastepnym roku"]) {
            let y = calendar.component(.year, from: today) + 1
            guard let start = calendar.date(from: DateComponents(year: y, month: 1, day: 1)) else { return nil }
            return span(start, .year, 1, "w \(y)")
        }
        if let year, let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) {
            return span(start, .year, 1, "w \(year)")
        }
        return nil
    }

    // MARK: Podpowiedzi

    static func categoryName(_ category: DocumentCategory) -> String {
        switch category {
        case .carInsurance: "OC"
        case .carInspection: "przegląd"
        case .passport: "paszport"
        case .idCard: "dowód osobisty"
        case .drivingLicense: "prawo jazdy"
        case .homeInsurance: "ubezpieczenie mieszkania"
        case .subscription: "subskrypcje"
        case .other: "inne dokumenty"
        }
    }

    /// Ogólne wskazówki, nie porada prawna. Szczegóły zawsze na gov.pl albo u ubezpieczyciela.
    static func renewalTip(for category: DocumentCategory) -> String {
        switch category {
        case .idCard:
            "Nowy dowód: wniosek złożysz w dowolnym urzędzie gminy albo przez internet na gov.pl (z profilem zaufanym). Odbierasz go osobiście. Zacznij ok. miesiąc przed terminem. Szczegóły sprawdź na gov.pl."
        case .passport:
            "Paszport: wniosek składasz osobiście w punkcie paszportowym, zwykle po umówieniu wizyty. Na paszport czeka się kilka tygodni, więc nie zostawiaj tego na ostatnią chwilę. Szczegóły na gov.pl."
        case .drivingLicense:
            "Prawo jazdy wymienisz w wydziale komunikacji swojego starostwa albo urzędu miasta. Potrzebne będzie zdjęcie jak do dowodu. Szczegóły i opłaty na gov.pl."
        case .carInspection:
            "Przegląd zrobisz na dowolnej stacji kontroli pojazdów. Weź dowód rejestracyjny i miej ważne OC. Stacja wpisze nowy termin do systemu."
        case .carInsurance:
            "OC zwykle przedłuża się samo na kolejny rok, jeśli go nie wypowiesz. Chcesz zmienić ubezpieczyciela? Porównaj oferty i wypowiedz starą umowę przed końcem okresu."
        case .homeInsurance:
            "Polisa mieszkania zwykle nie przedłuża się sama. Sprawdź, czy ubezpieczyciel przysłał ofertę na kolejny rok, albo porównaj inne."
        case .subscription:
            "Subskrypcję odnawia sam serwis. Żeby ją wyłączyć, wejdź w ustawienia konta w serwisie albo w Ustawienia › Twoje imię › Subskrypcje."
        case .other:
            "Dla tego dokumentu nie mam gotowej podpowiedzi. Po odnowieniu kliknij „Odnów” na karcie, a przesunę termin."
        }
    }

    static func has(_ q: String, _ needles: [String]) -> Bool {
        needles.contains { q.contains($0) }
    }
}
