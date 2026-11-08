import Foundation

/// Wyciąga z rozpoznanego tekstu (OCR) najbardziej prawdopodobną datę ważności.
///
/// Heurystyka:
/// 1. Szukamy wszystkich dat w formatach dd.MM.yyyy, dd-MM-yyyy, dd/MM/yyyy, dd MM yyyy, yyyy-MM-dd.
/// 2. Data w linii ze słowem kluczowym („ważny do”, „data ważności”, „expiry”…) lub zaraz pod nią dostaje premię.
/// 3. Daty z przeszłości dostają karę (to zwykle data wydania lub urodzenia).
/// 4. Przy remisie wygrywa późniejsza data.
struct DateExtractor {
    static let keywords = [
        "ważn", "wazn", "ważny do", "termin", "do dnia", "koniec", "okres ubezpieczenia",
        "expiry", "expiration", "valid until", "valid to", "date of expiry", "odnowienie", "renews",
        "następne badanie", "nastepne badanie", "następnego badania", "data następnego"
    ]

    /// Daty przy tych słowach to na pewno nie ważność: wydanie, urodzenie, wystawienie.
    static let otherDateKeywords = [
        "wydan", "issue", "urodz", "birth", "wystaw", "zawarcia", "podpis", "sprzedaż", "sprzedaz"
    ]

    var calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        return cal
    }()

    struct Candidate: Equatable {
        let date: Date
        let score: Int
    }

    func bestExpiryDate(in text: String, now: Date = .now) -> Date? {
        guard let best = candidates(in: text, now: now)
            .max(by: { a, b in a.score == b.score ? a.date < b.date : a.score < b.score })
        else { return nil }
        // Data z przeszłości bez słowa „ważny do” obok to prawie zawsze data wydania albo urodzenia.
        // Lepiej nic nie wpisać (zostaje domyślna data) niż oznaczyć ważny dokument jako nieważny.
        if best.date < calendar.startOfDay(for: now) && best.score < 10 { return nil }
        return best.date
    }

    func candidates(in text: String, now: Date = .now) -> [Candidate] {
        let lines = text.components(separatedBy: .newlines)
        let today = calendar.startOfDay(for: now)
        var result: [Candidate] = []

        for (index, line) in lines.enumerated() {
            let lower = line.lowercased()
            let previous = index > 0 ? lines[index - 1].lowercased() : ""
            let hasKeyword = Self.keywords.contains { lower.contains($0) }
            let keywordAbove = Self.keywords.contains { previous.contains($0) }
            let otherHere = Self.otherDateKeywords.contains { lower.contains($0) }
            let otherAbove = Self.otherDateKeywords.contains { previous.contains($0) }
            // „Data wydania 03.02.2019” albo etykieta „DATA WYDANIA” nad samą datą.
            if otherHere && !hasKeyword { continue }
            if otherAbove && !hasKeyword && !keywordAbove { continue }

            let datesInLine = dates(in: line)
            for (position, date) in datesInLine.enumerated() {
                var score = 0
                if hasKeyword { score += 10 }
                if keywordAbove { score += 6 }
                if date >= today { score += 5 } else { score -= 5 }
                // „od 01.01.2026 do 31.12.2026” – druga data w linii to zwykle koniec okresu.
                if datesInLine.count > 1 && position == datesInLine.count - 1 { score += 2 }
                result.append(Candidate(date: date, score: score))
            }
        }
        return result
    }

    private static let patterns: [(regex: NSRegularExpression, order: (Int, Int, Int))] = {
        // order = indeksy grup (dzień, miesiąc, rok)
        let defs: [(String, (Int, Int, Int))] = [
            (#"(?<!\d)(\d{4}) ?[-./,] ?(\d{1,2}) ?[-./,] ?(\d{1,2})(?!\d)"#, (3, 2, 1)),
            (#"(?<!\d)(\d{1,2}) ?[-./,] ?(\d{1,2}) ?[-./,] ?(\d{4})(?!\d)"#, (1, 2, 3)),
            (#"(?<!\d)(\d{2}) (\d{2}) (\d{4})(?!\d)"#, (1, 2, 3)),
        ]
        return defs.compactMap { pattern, order in
            (try? NSRegularExpression(pattern: pattern)).map { ($0, order) }
        }
    }()

    /// Skróty miesięcy po polsku i angielsku („12 MAR 2029”, „12 LIS/NOV 2029”).
    private static let monthNames: [(String, Int)] = [
        ("sty", 1), ("jan", 1), ("lut", 2), ("feb", 2), ("mar", 3), ("kwi", 4), ("apr", 4),
        ("maj", 5), ("may", 5), ("cze", 6), ("jun", 6), ("lip", 7), ("jul", 7), ("sie", 8), ("aug", 8),
        ("wrz", 9), ("sep", 9), ("pa[zź]", 10), ("oct", 10), ("lis", 11), ("nov", 11), ("gru", 12), ("dec", 12),
    ]

    /// Poprawia typowe błędy OCR w datach i zamienia nazwy miesięcy na liczby.
    static func normalize(_ line: String) -> String {
        var text = line
        // „2O29” → „2029”: litera O między cyframi albo przy kropce daty.
        text = text.replacingOccurrences(of: #"(?<=[0-9])[Oo](?=[0-9.])|(?<=[0-9.])[Oo](?=[0-9])"#, with: "0", options: .regularExpression)
        for (name, number) in monthNames {
            let pattern = #"(?i)(?<!\d)(\d{1,2})[ .-]*"# + name + #"[a-ząćęłńóśźż]*\.?(?:/[a-z]+\.?)?[ .-]*(\d{4})(?!\d)"#
            text = text.replacingOccurrences(of: pattern, with: "$1.\(number).$2", options: .regularExpression)
        }
        return text
    }

    func dates(in rawLine: String) -> [Date] {
        let line = Self.normalize(rawLine)
        let ns = line as NSString
        var found: [(location: Int, date: Date)] = []
        var taken: [NSRange] = []

        for (regex, order) in Self.patterns {
            for match in regex.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
                if taken.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) { continue }
                func int(_ group: Int) -> Int? { Int(ns.substring(with: match.range(at: group))) }
                guard let day = int(order.0), let month = int(order.1), let year = int(order.2),
                      let date = makeDate(day: day, month: month, year: year)
                else { continue }
                taken.append(match.range)
                found.append((match.range.location, date))
            }
        }
        return found.sorted { $0.location < $1.location }.map(\.date)
    }

    private func makeDate(day: Int, month: Int, year: Int) -> Date? {
        guard (1900...2100).contains(year), (1...12).contains(month), (1...31).contains(day) else { return nil }
        let comps = DateComponents(year: year, month: month, day: day)
        guard let date = calendar.date(from: comps),
              calendar.component(.day, from: date) == day // odrzuca np. 31.02
        else { return nil }
        return date
    }
}
