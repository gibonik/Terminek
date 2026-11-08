import Foundation
import MetricKit
import os

/// Logi z kategoriami (bez danych osobowych) i raporty awarii z MetricKit.
/// Raporty zostają na telefonie; użytkownik może je wysłać z menu deweloperskiego.
enum Log {
    static let scan = Logger(subsystem: "pl.terminy.app", category: "skan")
    static let reminders = Logger(subsystem: "pl.terminy.app", category: "przypomnienia")
    static let store = Logger(subsystem: "pl.terminy.app", category: "zakupy")
}

final class Diagnostics: NSObject, MXMetricManagerSubscriber {
    static let shared = Diagnostics()

    private var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Diagnostics", isDirectory: true)
    }

    func start() {
        MXMetricManager.shared.add(self)
    }

    /// Zapisane raporty awarii (najnowsze na początku).
    var reports: [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey])) ?? []
        return files.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    func clear() {
        try? FileManager.default.removeItem(at: folder)
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for payload in payloads {
            let stamp = ISO8601DateFormatter().string(from: payload.timeStampEnd).replacingOccurrences(of: ":", with: "-")
            let url = folder.appendingPathComponent("awaria-\(stamp).json")
            try? payload.jsonRepresentation().write(to: url, options: .atomic)
        }
        // Trzymamy najwyżej 20 ostatnich.
        for old in reports.dropFirst(20) { try? FileManager.default.removeItem(at: old) }
    }
}
