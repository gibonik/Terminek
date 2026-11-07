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
        candidates(in: text, now: now)
            .max { a, b in a.score == b.score ? a.date < b.date : a.score < b.score }?
            .date
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
            (#"(?<!\d)(\d{4})[-./](\d{1,2})[-./](\d{1,2})(?!\d)"#, (3, 2, 1)),
            (#"(?<!\d)(\d{1,2})[-./](\d{1,2})[-./](\d{4})(?!\d)"#, (1, 2, 3)),
            (#"(?<!\d)(\d{2}) (\d{2}) (\d{4})(?!\d)"#, (1, 2, 3)),
        ]
        return defs.compactMap { pattern, order in
            (try? NSRegularExpression(pattern: pattern)).map { ($0, order) }
        }
    }()

    func dates(in line: String) -> [Date] {
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
