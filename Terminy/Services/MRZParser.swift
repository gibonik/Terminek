import Foundation

/// Odczyt strefy MRZ (dwa albo trzy wiersze z „<<<” na dole paszportu i dowodu).
///
/// - Paszport (TD3): 2 wiersze po 44 znaki.
/// - Dowód osobisty (TD1): 3 wiersze po 30 znaków.
///
/// Każde pole liczbowe ma cyfrę kontrolną (wagi 7, 3, 1). Numer i datę ważności
/// zwracamy tylko wtedy, gdy cyfra kontrolna się zgadza, żeby błąd OCR nie wpisał
/// złych danych. PESEL-u (pole opcjonalne) celowo nie czytamy.
struct MRZParser {
    enum Kind: Equatable { case passport, idCard }

    struct Result: Equatable {
        var kind: Kind
        var documentNumber: String?
        var expiry: Date?
        var surname: String
        var givenNames: String
        var country: String

        /// „Anna Eriksson”: pierwsze imię i nazwisko, z wielkiej litery.
        var displayName: String {
            let first = givenNames.split(separator: " ").first.map(String.init) ?? ""
            return [first, surname]
                .filter { !$0.isEmpty }
                .map { $0.lowercased().split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: "-") }
                .joined(separator: " ")
        }
    }

    var calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        return cal
    }()

    func parse(_ text: String) -> Result? {
        let lines = text
            .components(separatedBy: .newlines)
            .map(Self.normalize)
            .filter { $0.count >= 27 && $0.contains("<") }

        for i in lines.indices {
            if i + 1 < lines.count, let line1 = Self.fit(lines[i], 44), let line2 = Self.fit(lines[i + 1], 44),
               line1.first == "P", let result = parseTD3(line1, line2) {
                return result
            }
            if i + 2 < lines.count, let l1 = Self.fit(lines[i], 30), let l2 = Self.fit(lines[i + 1], 30),
               let l3 = Self.fit(lines[i + 2], 30), let result = parseTD1(l1, l2, l3) {
                return result
            }
        }
        return nil
    }

    // MARK: Formaty

    private func parseTD3(_ l1: [Character], _ l2: [Character]) -> Result? {
        let number = Self.field(l2, 0, 9, digits: false)
        let numberOK = Self.check(number, l2[9])
        let expiryRaw = Self.field(l2, 21, 6, digits: true)
        let expiryOK = Self.check(expiryRaw, l2[27])
        guard numberOK || expiryOK else { return nil }
        let (surname, given) = Self.names(String(l1[5...]))
        return Result(
            kind: .passport,
            documentNumber: numberOK ? Self.clean(number) : nil,
            expiry: expiryOK ? date(expiryRaw) : nil,
            surname: surname, givenNames: given,
            country: Self.clean(String(l1[2..<5]))
        )
    }

    private func parseTD1(_ l1: [Character], _ l2: [Character], _ l3: [Character]) -> Result? {
        guard l1.first == "I" || l1.first == "A" || l1.first == "C" else { return nil }
        let number = Self.field(l1, 5, 9, digits: false)
        let numberOK = Self.check(number, l1[14])
        let expiryRaw = Self.field(l2, 8, 6, digits: true)
        let expiryOK = Self.check(expiryRaw, l2[14])
        guard numberOK || expiryOK else { return nil }
        let (surname, given) = Self.names(String(l3))
        return Result(
            kind: .idCard,
            documentNumber: numberOK ? Self.clean(number) : nil,
            expiry: expiryOK ? date(expiryRaw) : nil,
            surname: surname, givenNames: given,
            country: Self.clean(String(l1[2..<5]))
        )
    }

    // MARK: Pomocnicze

    /// Data ważności RRMMDD. Ważność jest zawsze w XXI wieku.
    private func date(_ raw: String) -> Date? {
        let digits = raw.compactMap(\.wholeNumberValue)
        guard digits.count == 6 else { return nil }
        let year = 2000 + digits[0] * 10 + digits[1]
        let month = digits[2] * 10 + digits[3]
        let day = digits[4] * 10 + digits[5]
        guard (1...12).contains(month), (1...31).contains(day),
              let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
              calendar.component(.day, from: date) == day
        else { return nil }
        return date
    }

    static func normalize(_ line: String) -> String {
        var text = line.uppercased()
            .replacingOccurrences(of: "«", with: "<<")
            .replacingOccurrences(of: "»", with: "<<")
            .replacingOccurrences(of: "‹", with: "<")
            .replacingOccurrences(of: "〈", with: "<")
            .replacingOccurrences(of: "く", with: "<")
            .filter { !$0.isWhitespace }
        // OCR często czyta ciąg „<<<<” jako „KKKK”, „CCCC” albo ich mieszankę.
        if let regex = try? NSRegularExpression(pattern: "[<KC]{4,}") {
            let ns = text as NSString
            for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed() {
                let run = ns.substring(with: match.range)
                guard run.contains("<") || run.count >= 6 else { continue }
                text = (text as NSString).replacingCharacters(in: match.range, with: String(repeating: "<", count: run.count))
            }
        }
        return text
    }

    /// OCR potrafi zgubić albo dodać znak wypełnienia na końcu wiersza.
    static func fit(_ line: String, _ length: Int) -> [Character]? {
        guard abs(line.count - length) <= 2,
              line.allSatisfy({ $0 == "<" || $0.isASCII && ($0.isLetter || $0.isNumber) })
        else { return nil }
        var chars = Array(line)
        while chars.count > length, chars.last == "<" { chars.removeLast() }
        guard chars.count <= length else { return nil }
        while chars.count < length { chars.append("<") }
        return chars
    }

    /// W polach liczbowych OCR myli litery z cyframi (O↔0, I↔1, S↔5, B↔8).
    static func field(_ chars: [Character], _ start: Int, _ length: Int, digits: Bool) -> String {
        let slice = String(chars[start..<(start + length)])
        guard digits else { return slice }
        let map: [Character: Character] = ["O": "0", "D": "0", "Q": "0", "I": "1", "L": "1", "Z": "2", "S": "5", "B": "8", "G": "6"]
        return String(slice.map { map[$0] ?? $0 })
    }

    static func checkDigit(_ value: String) -> Int {
        let weights = [7, 3, 1]
        var sum = 0
        for (i, ch) in value.enumerated() {
            let v: Int
            if let d = ch.wholeNumberValue { v = d }
            else if let ascii = ch.asciiValue, ch.isLetter { v = Int(ascii) - 55 }
            else { v = 0 }
            sum += v * weights[i % 3]
        }
        return sum % 10
    }

    static func check(_ value: String, _ digit: Character) -> Bool {
        let fixed: Character = digit == "O" ? "0" : digit == "<" ? "0" : digit
        guard let d = fixed.wholeNumberValue else { return false }
        return checkDigit(value) == d && value.contains(where: { $0 != "<" })
    }

    static func clean(_ value: String) -> String {
        value.replacingOccurrences(of: "<", with: "")
    }

    static func names(_ raw: String) -> (surname: String, given: String) {
        let parts = raw.components(separatedBy: "<<")
        let surname = parts.first.map { $0.replacingOccurrences(of: "<", with: "-") } ?? ""
        let given = parts.dropFirst()
            .joined(separator: "<")
            .split(separator: "<")
            .joined(separator: " ")
        return (surname.trimmingCharacters(in: CharacterSet(charactersIn: "-")), given)
    }
}
