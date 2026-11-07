import Foundation

/// Z tekstu skanu (OCR) wyciąga to, co da się wpisać do formularza: rodzaj, datę ważności,
/// numer, osobę albo ubezpieczyciela i podpowiedź nazwy. Działa w całości na telefonie.
///
/// PESEL rozpoznajemy tylko po to, żeby go NIE wpisać jako numeru dokumentu.
struct ScanAnalyzer {
    enum Field: Hashable { case category, date, number, owner, title }

    struct Result: Equatable {
        var category: DocumentCategory?
        var expiry: Date?
        var number: String?
        var owner: String?
        var title: String?

        var found: Set<Field> {
            var set: Set<Field> = []
            if category != nil { set.insert(.category) }
            if expiry != nil { set.insert(.date) }
            if number != nil { set.insert(.number) }
            if owner != nil { set.insert(.owner) }
            if title != nil { set.insert(.title) }
            return set
        }
    }

    var calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        return cal
    }()

    static let insurers: [(match: String, name: String)] = [
        ("PZU", "PZU"), ("WARTA", "Warta"), ("HESTIA", "Ergo Hestia"), ("ALLIANZ", "Allianz"),
        ("GENERALI", "Generali"), ("LINK4", "Link4"), ("UNIQA", "Uniqa"), ("COMPENSA", "Compensa"),
        ("WIENER", "Wiener"), ("PROAMA", "Proama"), ("TUZ", "TUZ"), ("TRASTI", "Trasti"),
        ("BEESAFE", "beesafe"), ("BALCIA", "Balcia"), ("INTERRISK", "InterRisk"), ("AVIVA", "Aviva"),
        ("MTU", "mtu"), ("YOU CAN DRIVE", "You Can Drive"), ("AXA", "AXA"), ("CUK", "CUK"),
    ]

    func analyze(_ text: String, knownCategory: DocumentCategory? = nil, now: Date = .now) -> Result {
        var result = Result()

        // 1. MRZ jest najpewniejsza: ma cyfry kontrolne.
        if let mrz = MRZParser(calendar: calendar).parse(text) {
            result.category = mrz.kind == .passport ? .passport : .idCard
            result.expiry = mrz.expiry
            result.number = mrz.documentNumber
            let name = mrz.displayName
            if !name.isEmpty { result.owner = name }
        }

        let category = knownCategory ?? result.category ?? Self.guessCategory(in: text)
        if knownCategory == nil, result.category == nil { result.category = category }

        // 2. Data ważności z tekstu, gdy MRZ jej nie dała.
        if result.expiry == nil {
            result.expiry = drivingLicenseExpiry(in: text) ?? DateExtractor(calendar: calendar).bestExpiryDate(in: text, now: now)
        }

        // 3. Numer i reszta zależnie od rodzaju.
        switch category ?? .other {
        case .idCard:
            if result.number == nil { result.number = Self.polishIDNumber(in: text) }
        case .passport:
            if result.number == nil { result.number = Self.firstMatch(#"\b[A-Z]{2} ?\d{7}\b"#, in: text.uppercased())?.replacingOccurrences(of: " ", with: "") }
        case .drivingLicense:
            result.number = Self.drivingLicenseNumber(in: text)
        case .carInsurance, .homeInsurance:
            if let insurer = Self.insurer(in: text) {
                result.owner = insurer
                result.title = category == .carInsurance ? "OC \(insurer)" : "Polisa \(insurer)"
            }
            result.number = Self.valueAfter(keywords: ["nr polisy", "numer polisy", "polisa nr", "polisa numer", "nr dokumentu"], in: text)
            if category == .carInsurance, let plate = Self.plate(in: text) {
                result.title = "OC \(plate)"
            }
        case .carInspection:
            result.number = Self.plate(in: text)
        default:
            break
        }

        if let number = result.number, Self.isPESEL(number) { result.number = nil }
        return result
    }

    // MARK: Rodzaj

    static func guessCategory(in text: String) -> DocumentCategory? {
        let t = text.uppercased()
        if t.contains("PASZPORT") || t.contains("PASSPORT") { return .passport }
        if t.contains("DOWÓD OSOBISTY") || t.contains("DOWOD OSOBISTY") || t.contains("IDENTITY CARD") || t.contains("IDPOL") { return .idCard }
        if t.contains("PRAWO JAZDY") || t.contains("DRIVING LICENCE") { return .drivingLicense }
        if t.contains("BADANIE TECHNICZNE") || t.contains("PRZEGLĄD") || t.contains("STACJA KONTROLI") || t.contains("NASTĘPNE BADANIE") { return .carInspection }
        if t.contains("ODPOWIEDZIALNOŚCI CYWILNEJ") || t.contains(" OC ") || t.contains("POJAZD") { return .carInsurance }
        if t.contains("MIESZKANI") || t.contains("NIERUCHOMOŚ") || t.contains("DOMU") { return .homeInsurance }
        return nil
    }

    // MARK: Prawo jazdy

    /// Pole „4b.” to data ważności, „4a.” to data wydania.
    func drivingLicenseExpiry(in text: String) -> Date? {
        let extractor = DateExtractor(calendar: calendar)
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces).lowercased()
            if trimmed.hasPrefix("4b"), let date = extractor.dates(in: line).first { return date }
        }
        return nil
    }

    /// Pole „5.”: np. 01234/15/1234.
    static func drivingLicenseNumber(in text: String) -> String? {
        firstMatch(#"\b\d{5}/\d{2}/\d{4}\b"#, in: text)
    }

    // MARK: Dowód osobisty

    /// Seria i numer dowodu: 3 litery + 6 cyfr, z cyfrą kontrolną na 4. pozycji.
    static func polishIDNumber(in text: String) -> String? {
        let upper = text.uppercased()
        guard let regex = try? NSRegularExpression(pattern: #"\b([A-Z]{3}) ?(\d{6})\b"#) else { return nil }
        let ns = upper as NSString
        for match in regex.matches(in: upper, range: NSRange(location: 0, length: ns.length)) {
            let candidate = ns.substring(with: match.range(at: 1)) + ns.substring(with: match.range(at: 2))
            if isValidPolishID(candidate) { return candidate }
        }
        return nil
    }

    static func isValidPolishID(_ value: String) -> Bool {
        let chars = Array(value)
        guard chars.count == 9 else { return false }
        let weights = [7, 3, 1, 9, 7, 3, 1, 7, 3]
        var sum = 0
        for (i, ch) in chars.enumerated() where i != 3 {
            let v: Int
            if i < 3 {
                guard let ascii = ch.asciiValue, ch.isLetter else { return false }
                v = Int(ascii) - 55
            } else {
                guard let d = ch.wholeNumberValue else { return false }
                v = d
            }
            sum += v * weights[i]
        }
        return chars[3].wholeNumberValue == sum % 10
    }

    // MARK: Ubezpieczenia i auto

    static func insurer(in text: String) -> String? {
        let upper = " " + text.uppercased().replacingOccurrences(of: "\n", with: " ") + " "
        return insurers.first { item in
            upper.range(of: #"[^A-Z0-9]"# + NSRegularExpression.escapedPattern(for: item.match) + #"[^A-Z0-9]"#, options: .regularExpression) != nil
        }?.name
    }

    /// Numer rejestracyjny z linii „nr rejestracyjny …” albo pod nią.
    static func plate(in text: String) -> String? {
        let lines = text.components(separatedBy: .newlines)
        for (i, line) in lines.enumerated() {
            let lower = line.lowercased()
            guard lower.contains("rejestr") || lower.contains("nr rej") else { continue }
            let rest = [after(colonIn: line), i + 1 < lines.count ? lines[i + 1] : ""]
            for chunk in rest {
                if let plate = firstMatch(#"\b[A-Z]{1,3} ?[0-9][0-9A-Z]{2,4}\b"#, in: chunk.uppercased()) {
                    return plate
                }
            }
        }
        return nil
    }

    /// Wartość po słowie kluczowym w tej samej linii albo w następnej: najdłuższy ciąg z cyframi.
    static func valueAfter(keywords: [String], in text: String) -> String? {
        let lines = text.components(separatedBy: .newlines)
        for (i, line) in lines.enumerated() {
            let lower = line.lowercased()
            guard let key = keywords.first(where: { lower.contains($0) }),
                  let range = lower.range(of: key) else { continue }
            let tail = String(line[range.upperBound...])
            for chunk in [tail, i + 1 < lines.count ? lines[i + 1] : ""] {
                let tokens = chunk
                    .components(separatedBy: CharacterSet(charactersIn: " :;,\t"))
                    .filter { $0.count >= 5 && $0.contains(where: \.isNumber) && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "/" || $0 == "-" } }
                if let best = tokens.max(by: { $0.count < $1.count }) { return best.uppercased() }
            }
        }
        return nil
    }

    // MARK: PESEL

    static func isPESEL(_ value: String) -> Bool {
        let digits = value.compactMap(\.wholeNumberValue)
        guard digits.count == 11, value.count == 11 else { return false }
        let weights = [1, 3, 7, 9, 1, 3, 7, 9, 1, 3]
        let sum = zip(digits, weights).map(*).reduce(0, +)
        return (10 - sum % 10) % 10 == digits[10]
    }

    // MARK: Pomocnicze

    private static func after(colonIn line: String) -> String {
        guard let index = line.firstIndex(of: ":") else { return line }
        return String(line[line.index(after: index)...])
    }

    static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
        return String(text[range])
    }
}
