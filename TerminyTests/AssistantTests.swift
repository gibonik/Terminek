import XCTest
@testable import Terminy

@MainActor
final class AssistantTests: XCTestCase {
    private let cal = PL.calendar
    private lazy var now = DateComponents(calendar: cal, year: 2026, month: 11, day: 7, hour: 12).date!

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        DateComponents(calendar: cal, year: y, month: m, day: d).date!
    }

    private lazy var oc = Document(title: "OC Passat", category: .carInsurance, expiryDate: date(2027, 3, 14))
    private lazy var passport = Document(title: "Paszport", category: .passport, expiryDate: date(2030, 6, 1), owner: "Ania")
    private lazy var id = Document(title: "", category: .idCard, expiryDate: date(2026, 11, 10), owner: "Ja")
    private lazy var netflix: Document = {
        let doc = Document(title: "Netflix", category: .subscription, expiryDate: date(2026, 11, 20))
        doc.price = 60
        doc.billingCycle = .monthly
        return doc
    }()
    private lazy var oldInspection = Document(title: "Przegląd Passat", category: .carInspection, expiryDate: date(2026, 10, 1))

    private var all: [Document] { [oc, passport, id, netflix, oldInspection] }
    private var assistant: Assistant { Assistant(calendar: cal, now: now) }

    func testWhenIsOC() {
        let reply = assistant.answer("Kiedy kończy się OC?", documents: all)
        XCTAssertEqual(reply.documentIDs, [oc.id])
        XCTAssertTrue(reply.text.contains("14 marca 2027"), reply.text)
    }

    func testOwnerInflectedForm() {
        let reply = assistant.answer("do kiedy paszport Ani?", documents: all)
        XCTAssertEqual(reply.documentIDs, [passport.id])
    }

    func testMonthRange() {
        let reply = assistant.answer("co wygasa w marcu?", documents: all)
        XCTAssertEqual(reply.documentIDs, [oc.id])
        XCTAssertTrue(reply.text.hasPrefix("W marcu 2027"), reply.text)
    }

    func testThisWeek() {
        let reply = assistant.answer("co mam w tym tygodniu", documents: all)
        XCTAssertEqual(reply.documentIDs, [id.id])
    }

    func testSubscriptionCost() {
        let reply = assistant.answer("Ile płacę za subskrypcje?", documents: all)
        XCTAssertTrue(reply.text.contains("60 zł miesięcznie"), reply.text)
        XCTAssertTrue(reply.text.contains("720 zł rocznie"), reply.text)
    }

    func testExpired() {
        let reply = assistant.answer("co jest po terminie", documents: all)
        XCTAssertEqual(reply.documentIDs, [oldInspection.id])
    }

    func testTitleMatch() {
        let reply = assistant.answer("kiedy netflix", documents: all)
        XCTAssertEqual(reply.documentIDs, [netflix.id])
    }

    func testRenewTip() {
        let reply = assistant.answer("jak odnowić dowód?", documents: all)
        XCTAssertTrue(reply.text.contains("urzędzie gminy"), reply.text)
    }

    func testRefusesForgery() {
        let reply = assistant.answer("jak podrobić dowód?", documents: all)
        XCTAssertTrue(reply.text.hasPrefix("W tym nie pomogę"), reply.text)
    }

    func testOffTopicRedirects() {
        let reply = assistant.answer("jaka jest jutro pogoda?", documents: all)
        XCTAssertTrue(reply.text.hasPrefix("Z tym nie pomogę"), reply.text)
        XCTAssertFalse(reply.actions.isEmpty)
    }

    func testGreetingIsNotTriggeredInsideWords() {
        XCTAssertTrue(assistant.answer("Cześć!", documents: all).text.hasPrefix("Cześć"))
        XCTAssertFalse(assistant.answer("kiedy toyota", documents: all).text.hasPrefix("Cześć"))
    }

    func testAppKnowledgeBackup() {
        let reply = assistant.answer("Jak zrobić kopię zapasową?", documents: all)
        XCTAssertTrue(reply.actions.contains(.backup))
        XCTAssertTrue(reply.text.contains("Kopia zapasowa"), reply.text)
    }

    func testPlusPriceIsNotSubscriptionCost() {
        let reply = assistant.answer("ile kosztuje plus?", documents: all)
        XCTAssertTrue(reply.text.contains("69,99 zł"), reply.text)
        XCTAssertTrue(reply.actions.contains(.plus))
    }

    func testDocumentNumber() {
        oc.number = "WX 12345"
        let reply = assistant.answer("jaki jest numer polisy OC?", documents: all)
        XCTAssertTrue(reply.text.contains("WX 12345"), reply.text)
    }

    func testRenewOffersButton() {
        let reply = assistant.answer("odnów OC", documents: all)
        XCTAssertTrue(reply.actions.contains(.renew(oc.id)))
        XCTAssertTrue(reply.text.contains("14 marca 2028"), reply.text)
    }

    func testSummaryMentionsExpired() {
        let reply = assistant.answer("podsumuj moje dokumenty", documents: all)
        XCTAssertTrue(reply.text.contains("Po terminie: Przegląd Passat"), reply.text)
    }

    func testAmbiguousWhenAsksBack() {
        let reply = assistant.answer("kiedy?", documents: all)
        XCTAssertEqual(reply.text, "O który dokument pytasz?")
        XCTAssertFalse(reply.actions.isEmpty)
    }

    func testUnknownFallsBack() {
        let reply = assistant.answer("asdf qwerty zxcv", documents: all)
        XCTAssertTrue(reply.text.hasPrefix("Nie zrozumiałem"), reply.text)
    }

    func testFineInfoForOC() {
        let reply = assistant.answer("jaka jest kara za brak OC?", documents: all)
        XCTAssertTrue(reply.text.contains("ufg.pl"), reply.text)
    }

    func testMissingCategory() {
        let reply = assistant.answer("kiedy prawo jazdy", documents: all)
        XCTAssertTrue(reply.documentIDs.isEmpty)
        XCTAssertTrue(reply.text.contains("prawo jazdy"), reply.text)
    }
}

@MainActor
final class FreePlanTests: XCTestCase {
    func testDocumentAndAssistantLimits() {
        let store = Store.shared
        let wasDebug = store.debugPlus
        defer { store.setDebugPlus(wasDebug) }
        store.setDebugPlus(false)

        XCTAssertTrue(store.canAddDocument(currentCount: 4))
        XCTAssertFalse(store.canAddDocument(currentCount: 5))
        XCTAssertEqual(store.maxScanPages, 1)

        UserDefaults.standard.removeObject(forKey: "assistantDay")
        XCTAssertEqual(store.assistantQuestionsLeft(), 3)
        store.recordAssistantQuestion()
        store.recordAssistantQuestion()
        XCTAssertEqual(store.assistantQuestionsLeft(), 1)
        UserDefaults.standard.removeObject(forKey: "assistantDay")

        store.setDebugPlus(true)
        XCTAssertTrue(store.canAddDocument(currentCount: 50))
    }
}
