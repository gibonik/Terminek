import Foundation
import SwiftData
import CryptoKit
import CommonCrypto

/// Kopia zapasowa wszystkich dokumentów (ze skanami) w jednym zaszyfrowanym pliku `.terminek`.
///
/// Bez iCloud dane są tylko na tym telefonie, więc kopia to jedyny ratunek przy zmianie telefonu
/// albo ponownej instalacji. Plik jest szyfrowany hasłem (AES-GCM, klucz z PBKDF2), bo zawiera
/// numery dokumentów i skany.
enum Backup {
    static let fileExtension = "terminek"
    private static let magic = Data("TERMINEK1".utf8)
    private static let rounds: UInt32 = 200_000
    static let minPasswordLength = 6

    enum Failure: LocalizedError {
        case notABackup, wrongPassword, unreadable, empty

        var errorDescription: String? {
            switch self {
            case .notABackup: "To nie jest kopia Terminka."
            case .wrongPassword: "Złe hasło albo uszkodzony plik."
            case .unreadable: "Nie udało się odczytać kopii."
            case .empty: "Nie ma czego zapisać. Dodaj najpierw dokument."
            }
        }
    }

    /// Jeden dokument w kopii (wszystkie pola modelu).
    struct Item: Codable {
        var id: UUID
        var title: String
        var categoryRaw: String
        var expiryDate: Date
        var owner: String
        var number: String
        var notes: String
        var remindersEnabled: Bool
        var customOffsetsRaw: String
        var createdAt: Date
        var price: Double?
        var billingCycleRaw: String?
        var scanImageData: Data?
        var scanPDFData: Data?
        var scanPageCount: Int

        init(_ d: Document) {
            id = d.id; title = d.title; categoryRaw = d.categoryRaw; expiryDate = d.expiryDate
            owner = d.owner; number = d.number; notes = d.notes; remindersEnabled = d.remindersEnabled
            customOffsetsRaw = d.customOffsetsRaw; createdAt = d.createdAt; price = d.price
            billingCycleRaw = d.billingCycleRaw; scanImageData = d.scanImageData; scanPDFData = d.scanPDFData
            scanPageCount = d.scanPageCount
        }

        func apply(to d: Document) {
            d.id = id; d.title = title; d.categoryRaw = categoryRaw; d.expiryDate = expiryDate
            d.owner = owner; d.number = number; d.notes = notes; d.remindersEnabled = remindersEnabled
            d.customOffsetsRaw = customOffsetsRaw; d.createdAt = createdAt; d.price = price
            d.billingCycleRaw = billingCycleRaw; d.scanImageData = scanImageData; d.scanPDFData = scanPDFData
            d.scanPageCount = scanPageCount
        }
    }

    struct Payload: Codable {
        var version = 1
        var created: Date
        var documents: [Item]
    }

    struct ImportResult: Equatable {
        var added: Int
        var updated: Int
    }

    // MARK: Zapis

    /// Zaszyfrowany plik z kopią.
    @MainActor
    static func export(_ documents: [Document], password: String, now: Date = .now) throws -> Data {
        try export(items: documents.map(Item.init), password: password, now: now)
    }

    /// Wersja na gotowych danych (bez modeli), żeby dało się ją liczyć poza głównym wątkiem.
    static func export(items: [Item], password: String, now: Date = .now) throws -> Data {
        guard !items.isEmpty else { throw Failure.empty }
        let payload = Payload(created: now, documents: items)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let json = try encoder.encode(payload)
        return try seal(json, password: password)
    }

    static func fileName(now: Date = .now) -> String {
        let day = now.formatted(.iso8601.year().month().day())
        return "Terminek-kopia-\(day).\(fileExtension)"
    }

    // MARK: Odczyt

    static func read(_ data: Data, password: String) throws -> Payload {
        let json = try open(data, password: password)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let payload = try? decoder.decode(Payload.self, from: json) else { throw Failure.unreadable }
        return payload
    }

    /// Wczytuje kopię: dokumenty, których nie ma, dodaje, a te z tym samym identyfikatorem nadpisuje.
    @MainActor
    @discardableResult
    static func restore(_ payload: Payload, into context: ModelContext) throws -> ImportResult {
        let existing = try context.fetch(FetchDescriptor<Document>())
        var byID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var result = ImportResult(added: 0, updated: 0)
        for item in payload.documents {
            if let doc = byID[item.id] {
                item.apply(to: doc)
                result.updated += 1
            } else {
                let doc = Document()
                item.apply(to: doc)
                context.insert(doc)
                byID[item.id] = doc
                result.added += 1
            }
        }
        try context.save()
        return result
    }

    // MARK: Szyfrowanie

    private static func seal(_ plain: Data, password: String) throws -> Data {
        var salt = Data(count: 16)
        let status = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        guard status == errSecSuccess else { throw Failure.unreadable }
        let key = try deriveKey(password, salt: salt)
        let box = try AES.GCM.seal(plain, using: key, authenticating: magic)
        guard let combined = box.combined else { throw Failure.unreadable }
        return magic + salt + combined
    }

    private static func open(_ data: Data, password: String) throws -> Data {
        guard data.count > magic.count + 16, data.prefix(magic.count) == magic else { throw Failure.notABackup }
        let salt = data.dropFirst(magic.count).prefix(16)
        let sealed = data.dropFirst(magic.count + 16)
        let key = try deriveKey(password, salt: Data(salt))
        do {
            let box = try AES.GCM.SealedBox(combined: Data(sealed))
            return try AES.GCM.open(box, using: key, authenticating: magic)
        } catch {
            throw Failure.wrongPassword
        }
    }

    private static func deriveKey(_ password: String, salt: Data) throws -> SymmetricKey {
        let passwordData = Data(password.utf8)
        var key = Data(count: 32)
        let status = key.withUnsafeMutableBytes { keyBytes in
            salt.withUnsafeBytes { saltBytes in
                passwordData.withUnsafeBytes { passwordBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.baseAddress?.assumingMemoryBound(to: Int8.self), passwordData.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), rounds,
                        keyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), 32
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw Failure.unreadable }
        return SymmetricKey(data: key)
    }
}
