import XCTest
@testable import Terminy

final class DateExtractorTests: XCTestCase {
    private let extractor = DateExtractor()
    private let now = DateComponents(calendar: .current, year: 2026, month: 11, day: 6).date!

    private func ymd(_ date: Date?) -> String? {
        guard let date else { return nil }
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    func testIDCardPicksFutureExpiryOverBirthAndIssueDates() {
        let text = """
        RZECZPOSPOLITA POLSKA
        DATA URODZENIA 14.05.1990
        DATA WYDANIA 03.02.2021
        DATA WAŻNOŚCI
        03.02.2031
        """
        XCTAssertEqual(ymd(extractor.bestExpiryDate(in: text, now: now)), "2031-02-03")
    }

    func testInsurancePeriodPicksEndDate() {
        let text = "Okres ubezpieczenia: od 15-03-2026 do 14-03-2027"
        XCTAssertEqual(ymd(extractor.bestExpiryDate(in: text, now: now)), "2027-03-14")
    }

    func testISODateAndSpacedFormat() {
        XCTAssertEqual(ymd(extractor.bestExpiryDate(in: "Valid until 2028-07-01", now: now)), "2028-07-01")
        XCTAssertEqual(ymd(extractor.bestExpiryDate(in: "DATE OF EXPIRY 12 09 2033", now: now)), "2033-09-12")
    }

    func testRejectsImpossibleDates() {
        XCTAssertNil(extractor.bestExpiryDate(in: "31.02.2027 i 45.13.2027", now: now))
    }
}

@MainActor
final class NotificationPlanTests: XCTestCase {
    func testPlansThirtySevenAndZeroDaysBefore() {
        let cal = Calendar.current
        let now = DateComponents(calendar: cal, year: 2026, month: 11, day: 6, hour: 12).date!
        let expiry = DateComponents(calendar: cal, year: 2027, month: 1, day: 31).date!
        let doc = Document(title: "OC Passat", category: .carInsurance, expiryDate: expiry)

        let plan = NotificationScheduler.plannedReminders(for: [doc], hour: 9, now: now)
        let days = plan.map { cal.dateComponents([.day], from: cal.startOfDay(for: $0.fireDate), to: expiry).day! }

        XCTAssertEqual(plan.count, 3)
        XCTAssertEqual(plan.map { cal.component(.hour, from: $0.fireDate) }, [9, 9, 9])
        XCTAssertEqual(days, [30, 7, 0])
    }

    func testSkipsPastRemindersAndDisabledDocuments() {
        let cal = Calendar.current
        let now = DateComponents(calendar: cal, year: 2026, month: 11, day: 6, hour: 12).date!
        let soon = Document(title: "Przegląd", category: .carInspection,
                            expiryDate: cal.date(byAdding: .day, value: 10, to: now)!)
        let muted = Document(title: "Netflix", category: .subscription,
                             expiryDate: cal.date(byAdding: .day, value: 60, to: now)!)
        muted.remindersEnabled = false

        let plan = NotificationScheduler.plannedReminders(for: [soon, muted], hour: 9, now: now)
        XCTAssertEqual(plan.map(\.identifier), ["\(soon.id.uuidString)-7", "\(soon.id.uuidString)-0"])
    }

    func testRespectsChosenOffsets() {
        let cal = Calendar.current
        let now = DateComponents(calendar: cal, year: 2026, month: 11, day: 6, hour: 12).date!
        let expiry = DateComponents(calendar: cal, year: 2027, month: 1, day: 31).date!
        let doc = Document(title: "OC", category: .carInsurance, expiryDate: expiry)

        let plan = NotificationScheduler.plannedReminders(for: [doc], hour: 9, now: now, offsets: [7])
        XCTAssertEqual(plan.count, 1)
    }
}

final class CategoryGroupTests: XCTestCase {
    func testEveryCategoryHasAGroup() {
        let grouped = CategoryGroup.allCases.flatMap(\.categories)
        XCTAssertEqual(Set(grouped), Set(DocumentCategory.allCases))
        XCTAssertEqual(DocumentCategory.homeInsurance.group, .home)
        XCTAssertEqual(DocumentCategory.drivingLicense.group, .auto)
    }

    func testPolishYearForms() {
        XCTAssertEqual(DaysText.short(1549), "4 lata")
        XCTAssertEqual(DaysText.short(2480), "6 lat")
        XCTAssertEqual(DaysText.short(-2), "2 dni po")
        XCTAssertEqual(DaysText.short(6), "6 dni")
    }

    func testLongCountdownInYearsMonthsDays() {
        let cal = Calendar.current
        let now = DateComponents(calendar: cal, year: 2026, month: 11, day: 7).date!
        let date = DateComponents(calendar: cal, year: 2029, month: 2, day: 12).date!
        XCTAssertEqual(DaysText.long(to: date, from: now), "2 lata, 3 miesiące i 5 dni")
        XCTAssertEqual(DaysText.headline(to: date, from: now).big, "2 lata")
        XCTAssertEqual(DaysText.compact(to: date, from: now), "2 l. 3 mies.")
        let soon = DateComponents(calendar: cal, year: 2026, month: 11, day: 13).date!
        XCTAssertEqual(DaysText.compact(to: soon, from: now), "6 dni")
    }

    @MainActor
    func testGuessesCategoryFromScanText() {
        XCTAssertEqual(DocumentEditView.guessCategory(in: "RZECZPOSPOLITA POLSKA\nDOWÓD OSOBISTY"), .idCard)
        XCTAssertEqual(DocumentEditView.guessCategory(in: "Passport / Paszport"), .passport)
        XCTAssertNil(DocumentEditView.guessCategory(in: "Faktura VAT"))
    }
}
