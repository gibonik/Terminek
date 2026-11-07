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
    }

    enum Intent: Equatable { case help, cost, expired, howToRenew, count, upcoming, when }

    var calendar: Calendar = PL.calendar
    var now: Date = .now

    // MARK: Odpowiedź

    func answer(_ question: String, documents: [Document]) -> Reply {
        let q = Self.fold(question)
        let intent = Self.intent(in: q)
        let category = Self.category(in: q)
        let owner = Self.ownerMatch(in: q, documents: documents)
        let titled = Self.titleMatches(in: q, documents: documents)
        let range = period(in: q)

        if intent == .help || q.trimmingCharacters(in: .whitespaces).isEmpty {
            return Reply(text: Self.helpText)
        }

        var docs = documents.sorted { $0.expiryDate < $1.expiryDate }
        if let category { docs = docs.filter { $0.category == category } }
        else if !titled.isEmpty { docs = docs.filter { titled.contains($0.id) } }
        if let owner { docs = docs.filter { Self.fold($0.owner) == owner } }

        if documents.isEmpty {
            return Reply(text: "Nie masz jeszcze żadnych dokumentów. Dodaj pierwszy plusem na dole, a potem pytaj o terminy.")
        }

        switch intent {
        case .howToRenew:
            let target = category ?? docs.first?.category ?? .other
            return Reply(text: Self.renewalTip(for: target), documentIDs: docs.prefix(3).map(\.id))

        case .cost:
            let subs = documents.filter { $0.category == .subscription }
            guard !subs.isEmpty else { return Reply(text: "Nie masz dodanych subskrypcji z ceną.") }
            let monthly = subs.reduce(0) { $0 + $1.monthlyCost }
            let text = "Subskrypcje kosztują Cię ok. \(PL.money(monthly)) miesięcznie, czyli \(PL.money(monthly * 12)) rocznie."
            return Reply(text: text, documentIDs: subs.sorted { $0.monthlyCost > $1.monthlyCost }.map(\.id))

        case .count:
            let expired = documents.filter { $0.daysLeft(from: now, calendar: calendar) < 0 }.count
            var text = "Masz \(Self.documentsCount(documents.count))."
            if expired > 0 { text += " Po terminie: \(expired)." }
            return Reply(text: text)

        case .expired:
            let past = docs.filter { $0.daysLeft(from: now, calendar: calendar) < 0 }
            guard !past.isEmpty else { return Reply(text: "Wszystko jest ważne. Nic nie jest po terminie.") }
            return Reply(text: "Po terminie: \(Self.documentsCount(past.count)).", documentIDs: past.map(\.id))

        case .upcoming, .when:
            if let range {
                let inRange = docs.filter { range.contains($0.expiryDate) }
                let when = range.label.prefix(1).uppercased() + range.label.dropFirst()
                guard !inRange.isEmpty else {
                    let what = category.map { " (" + Self.categoryName($0) + ")" } ?? ""
                    return Reply(text: when + " nic się nie kończy" + what + ".")
                }
                return Reply(text: when + " kończy się: " + Self.documentsCount(inRange.count) + ".",
                             documentIDs: inRange.map(\.id))
            }

            if intent == .when, category != nil || owner != nil || !titled.isEmpty {
                guard let first = docs.first else {
                    let what = category.map(Self.categoryName) ?? "taki dokument"
                    return Reply(text: "Nie widzę u Ciebie: \(what). Możesz go dodać plusem na dole.")
                }
                if docs.count == 1 { return Reply(text: sentence(for: first), documentIDs: [first.id]) }
                let lines = docs.prefix(4).map { "• " + sentence(for: $0) }.joined(separator: "\n")
                return Reply(text: lines, documentIDs: docs.prefix(4).map(\.id))
            }

            // Najbliższe terminy.
            let upcoming = docs.filter { $0.daysLeft(from: now, calendar: calendar) >= 0 }.prefix(3)
            guard let first = upcoming.first else { return Reply(text: "Nie ma przed Tobą żadnych terminów.") }
            var text = "Najbliżej: " + sentence(for: first)
            if upcoming.count > 1 { text += " Potem \(upcoming.dropFirst().map { $0.displayTitle }.joined(separator: " i "))." }
            return Reply(text: text, documentIDs: upcoming.map(\.id))

        case .help:
            return Reply(text: Self.helpText)
        }
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
    Pytaj o swoje terminy, np.:
    • Kiedy kończy się OC?
    • Co wygasa w marcu?
    • Co mam w tym tygodniu?
    • Ile płacę za subskrypcje?
    • Co jest po terminie?
    • Jak odnowić dowód?
    Wszystko liczę na telefonie, nic nie wysyłam.
    """

    // MARK: Rozpoznawanie

    /// Małe litery bez polskich znaków: „Kiedy kończy się OC Ani?” → „kiedy konczy sie oc ani?”.
    static func fold(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "ł", with: "l")
            .folding(options: [.diacriticInsensitive], locale: PL.locale)
    }

    static func intent(in q: String) -> Intent {
        if has(q, ["co umiesz", "pomoc", "pomocy", "jak dziala", "w czym pomozesz"]) { return .help }
        if has(q, ["jak odnow", "jak wyrobi", "jak przedluz", "gdzie odnow", "gdzie wyrobi", "co potrzeb", "jak zalatwi", "jak zrobic"]) { return .howToRenew }
        if has(q, ["ile plac", "ile kosztuj", "ile wydaj", "koszt", "ile mnie", "suma", "miesiecznie"]) { return .cost }
        if has(q, ["po terminie", "niewazn", "minal", "minely", "minela", "przetermin", "wygasl", "spoznion"]) { return .expired }
        if has(q, ["ile mam", "ile jest", "ile dokument"]) { return .count }
        if has(q, ["kiedy", "do kiedy", "wazn", "termin", "konczy", "wygasa", "koniec", "platnosc"]) { return .when }
        return .upcoming
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
