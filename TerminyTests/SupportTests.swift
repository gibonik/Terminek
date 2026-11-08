import XCTest
import SwiftData
@testable import Terminy

@MainActor
final class SupportTests: XCTestCase {
    func testBreadcrumbsKeepOnlyRecentSteps() {
        Breadcrumbs.clear()
        for i in 0..<75 { Breadcrumbs.add("krok \(i)") }
        let lines = Breadcrumbs.read().split(separator: "\n")
        XCTAssertEqual(lines.count, 60)
        XCTAssertTrue(lines.last?.hasSuffix("krok 74") ?? false)
        XCTAssertFalse(lines.contains { $0.hasSuffix("krok 0") })
        Breadcrumbs.clear()
    }

    func testReportDoesNotLeakDocumentData() async throws {
        let context = try XCTUnwrap(TerminyApp.sharedContainer?.mainContext)
        let doc = Document(title: "Paszport Ani", category: .passport, owner: "Anna Nowak", number: "EA1234567")
        context.insert(doc)
        defer { context.delete(doc) }
        Breadcrumbs.clear()
        Breadcrumbs.add("Dodano dokument (passport, skan: 0 str.)")

        let report = BugReport(kind: .bug, message: "Nie działa skan", includeDevice: true, includeSteps: true)
        let body = await report.body()
        XCTAssertTrue(body.hasPrefix("Nie działa skan"))
        XCTAssertTrue(body.contains("Wersja:"))
        XCTAssertTrue(body.contains("Dokumenty:"))
        for secret in ["EA1234567", "Anna", "Nowak", "Paszport Ani"] {
            XCTAssertFalse(body.contains(secret), "Zgłoszenie zawiera: \(secret)")
        }
        Breadcrumbs.clear()
    }

    func testSiriEntityHasNoDocumentNumber() {
        let doc = Document(title: "OC Passat", category: .carInsurance, owner: "PZU", number: "WX 12345")
        let entity = DocumentEntity(doc)
        let mirror = Mirror(reflecting: entity).children.map { "\($0.value)" }
        XCTAssertFalse(mirror.contains { $0.contains("WX 12345") })
        XCTAssertEqual(entity.title, "OC Passat")
    }

    func testDocumentQueryMatchesWithoutPolishLetters() async throws {
        let context = try XCTUnwrap(TerminyApp.sharedContainer?.mainContext)
        let doc = Document(title: "Prawo jazdy", category: .drivingLicense, owner: "Łukasz")
        context.insert(doc)
        defer { context.delete(doc) }
        let found = try await DocumentQuery().entities(matching: "lukasz")
        XCTAssertTrue(found.contains { $0.id == doc.id })
    }
}

@MainActor
final class BackupTests: XCTestCase {
    func testRoundTripWithScanAndWrongPassword() throws {
        let doc = Document(title: "OC Passat", category: .carInsurance, owner: "PZU", number: "WX 12345")
        doc.scanPDFData = Data([1, 2, 3, 4])
        doc.scanPageCount = 1
        doc.customOffsets = [60, 7]
        let file = try Backup.export([doc], password: "sekret1")

        // Plik nie zawiera danych jawnym tekstem.
        XCTAssertNil(file.range(of: Data("WX 12345".utf8)))
        XCTAssertThrowsError(try Backup.read(file, password: "zle-haslo"))
        XCTAssertThrowsError(try Backup.read(Data("cos innego".utf8), password: "sekret1"))

        let payload = try Backup.read(file, password: "sekret1")
        XCTAssertEqual(payload.documents.count, 1)
        let item = try XCTUnwrap(payload.documents.first)
        XCTAssertEqual(item.id, doc.id)
        XCTAssertEqual(item.number, "WX 12345")
        XCTAssertEqual(item.scanPDFData, Data([1, 2, 3, 4]))
        XCTAssertEqual(item.customOffsetsRaw, "60,7")
    }

    func testRestoreAddsAndReplaces() throws {
        let container = try ModelContainer(for: Document.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let existing = Document(title: "Stary", category: .passport)
        context.insert(existing)
        let changed = Document(title: "Nowy tytuł", category: .passport)
        changed.id = existing.id
        let fresh = Document(title: "Netflix", category: .subscription)
        let payload = try Backup.read(try Backup.export([changed, fresh], password: "haslo123"), password: "haslo123")

        let result = try Backup.restore(payload, into: context)
        XCTAssertEqual(result, Backup.ImportResult(added: 1, updated: 1))
        let all = try context.fetch(FetchDescriptor<Document>())
        XCTAssertEqual(all.count, 2)
        XCTAssertTrue(all.contains { $0.title == "Nowy tytuł" })
    }
}

final class WidgetSnapshotTests: XCTestCase {
    func testExpiredFirstThenSoonest() {
        let cal = Calendar.current
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: 12))!
        func item(_ title: String, _ days: Int) -> WidgetSnapshot.Item {
            WidgetSnapshot.Item(id: UUID(), title: title, categoryRaw: "other", expiryDate: cal.date(byAdding: .day, value: days, to: now)!)
        }
        let snapshot = WidgetSnapshot(items: [item("za rok", 365), item("wczoraj", -1), item("jutro", 1), item("dziś", 0)], updated: now)
        XCTAssertEqual(snapshot.upcoming(now: now).map(\.title), ["wczoraj", "dziś", "jutro", "za rok"])
    }
}

@MainActor
final class HomeGreetingTests: XCTestCase {
    func testGreetingFollowsTimeOfDay() {
        let cal = Calendar.current
        func at(_ hour: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: hour))! }
        XCTAssertEqual(HomeView.greeting(at: at(9)), "Dzień dobry")
        XCTAssertEqual(HomeView.greeting(at: at(20)), "Dobry wieczór")
        XCTAssertEqual(HomeView.greeting(at: at(2)), "Dobranoc")
    }
}
