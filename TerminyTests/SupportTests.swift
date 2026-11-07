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
