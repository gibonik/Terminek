import XCTest
@testable import Terminy

final class MRZParserTests: XCTestCase {
    private func ymd(_ date: Date?) -> String? {
        guard let date else { return nil }
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    /// Przykładowy paszport z dokumentacji ICAO 9303.
    func testPassportTD3() {
        let text = """
        PASSPORT
        P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<
        L898902C36UTO7408122F1204159ZE184226B<<<<<10
        """
        let result = MRZParser().parse(text)
        XCTAssertEqual(result?.kind, .passport)
        XCTAssertEqual(result?.documentNumber, "L898902C3")
        XCTAssertEqual(ymd(result?.expiry), "2012-04-15")
        XCTAssertEqual(result?.displayName, "Anna Eriksson")
    }

    /// Przykładowy dowód z dokumentacji ICAO 9303, z typowymi błędami OCR (spacje, O zamiast 0).
    func testIDCardTD1WithOCRNoise() {
        let text = """
        I<UTOD231458907<<<<<<<<<<<<<<<
        74O8122F12O4159UTO<<<<<<<<<<<6
        ERIKSSON<<ANNA<MARIA<<<<<<<<<<
        """
        let result = MRZParser().parse(text)
        XCTAssertEqual(result?.kind, .idCard)
        XCTAssertEqual(result?.documentNumber, "D23145890")
        XCTAssertEqual(ymd(result?.expiry), "2012-04-15")
        XCTAssertEqual(result?.surname, "ERIKSSON")
    }

    func testRejectsWrongCheckDigits() {
        let text = """
        P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<
        L898902C35UTO7408122F1204158ZE184226B<<<<<10
        """
        XCTAssertNil(MRZParser().parse(text))
    }

    func testCheckDigit() {
        XCTAssertEqual(MRZParser.checkDigit("L898902C3"), 6)
        XCTAssertEqual(MRZParser.checkDigit("740812"), 2)
    }
}

final class ScanAnalyzerTests: XCTestCase {
    private let now = DateComponents(calendar: .current, year: 2026, month: 11, day: 7).date!

    private func ymd(_ date: Date?) -> String? {
        guard let date else { return nil }
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    func testPolishIDNumberChecksum() {
        XCTAssertTrue(ScanAnalyzer.isValidPolishID("ABA300000"))
        XCTAssertFalse(ScanAnalyzer.isValidPolishID("ABA300001".replacingOccurrences(of: "3", with: "4")))
    }

    func testIDCardFrontReadsNumberAndDate() {
        let text = """
        RZECZPOSPOLITA POLSKA
        DOWÓD OSOBISTY
        NUMER DOWODU ABA 300000
        DATA URODZENIA 14.05.1990
        DATA WAŻNOŚCI 03.02.2031
        """
        let result = ScanAnalyzer().analyze(text, now: now)
        XCTAssertEqual(result.category, .idCard)
        XCTAssertEqual(result.number, "ABA300000")
        XCTAssertEqual(ymd(result.expiry), "2031-02-03")
    }

    func testCarPolicyReadsInsurerNumberAndPlate() {
        let text = """
        Polisa ubezpieczenia OC posiadaczy pojazdów
        PZU SA
        Nr polisy: 123456789012
        Numer rejestracyjny: WA 12345
        Okres ubezpieczenia: od 15-03-2026 do 14-03-2027
        """
        let result = ScanAnalyzer().analyze(text, knownCategory: .carInsurance, now: now)
        XCTAssertEqual(result.owner, "PZU")
        XCTAssertEqual(result.number, "123456789012")
        XCTAssertEqual(result.title, "OC WA 12345")
        XCTAssertEqual(ymd(result.expiry), "2027-03-14")
    }

    func testDrivingLicenceUsesField4b() {
        let text = """
        PRAWO JAZDY
        4a. 12.03.2018
        4b. 12.03.2033
        5. 01234/18/1234
        """
        let result = ScanAnalyzer().analyze(text, now: now)
        XCTAssertEqual(result.category, .drivingLicense)
        XCTAssertEqual(ymd(result.expiry), "2033-03-12")
        XCTAssertEqual(result.number, "01234/18/1234")
    }

    func testNeverUsesPESELAsNumber() {
        XCTAssertTrue(ScanAnalyzer.isPESEL("44051401359"))
        let text = "Polisa mieszkania\nNr polisy: 44051401359\nkoniec 01.01.2027"
        let result = ScanAnalyzer().analyze(text, knownCategory: .homeInsurance, now: now)
        XCTAssertNil(result.number)
    }

    func testIgnoresLonePastDate() {
        // Data wydania odczytana, a data ważności w nieczytelnym miejscu: nie oznaczamy jako nieważny.
        let text = "Data wydania 03.02.2019\nNumer 12345"
        XCTAssertNil(DateExtractor().bestExpiryDate(in: text, now: now))
    }

    func testReadsMonthNamesSpacedAndOCRNoise() {
        let e = DateExtractor()
        XCTAssertEqual(ymd(e.bestExpiryDate(in: "Data ważności / Date of expiry\n12 MAR/MAR 2029", now: now)), "2029-03-12")
        XCTAssertEqual(ymd(e.bestExpiryDate(in: "ważny do 14. 03. 2029 r.", now: now)), "2029-03-14")
        XCTAssertEqual(ymd(e.bestExpiryDate(in: "ważny do 14.03.2O29", now: now)), "2029-03-14")
        XCTAssertEqual(ymd(e.bestExpiryDate(in: "Expiry 05 LIS/NOV 2029", now: now)), "2029-11-05")
    }

    func testPolishPagePlurals() {
        XCTAssertEqual(PL.pages(1), "1 strona")
        XCTAssertEqual(PL.pages(3), "3 strony")
        XCTAssertEqual(PL.pages(5), "5 stron")
        XCTAssertEqual(PL.pages(12), "12 stron")
        XCTAssertEqual(PL.pages(22), "22 strony")
    }
}
