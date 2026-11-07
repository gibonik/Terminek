import UIKit
import PDFKit

/// Zapis skanów: wszystkie strony w jednym PDF-ie, pierwsza strona jako miniatura,
/// prosta ocena jakości zdjęcia i ochrona plików na dysku.
enum ScanStore {
    /// Długość dłuższego boku strony w PDF-ie (wystarcza do czytania drobnego druku).
    static let pageDimension: CGFloat = 2000
    static let thumbnailDimension: CGFloat = 1200

    // MARK: PDF

    static func makePDF(from pages: [UIImage]) -> Data? {
        guard !pages.isEmpty else { return nil }
        let prepared = pages.map { $0.downscaled(maxDimension: pageDimension) }
        let first = prepared[0]
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: first.size))
        return renderer.pdfData { ctx in
            for page in prepared {
                let bounds = CGRect(origin: .zero, size: page.size)
                ctx.beginPage(withBounds: bounds, pageInfo: [:])
                // JPEG zamiast surowej bitmapy: PDF jest kilka razy mniejszy.
                if let jpeg = page.jpegData(compressionQuality: 0.7), let image = UIImage(data: jpeg) {
                    image.draw(in: bounds)
                } else {
                    page.draw(in: bounds)
                }
            }
        }
    }

    static func thumbnail(of page: UIImage) -> Data? {
        page.downscaled(maxDimension: thumbnailDimension).jpegData(compressionQuality: 0.6)
    }

    static func pageCount(of pdf: Data?) -> Int {
        guard let pdf, let document = PDFDocument(data: pdf) else { return 0 }
        return document.pageCount
    }

    /// Strony PDF-a jako obrazki (do miniatur w formularzu i dokładania kolejnych stron).
    static func images(from pdf: Data?, maxDimension: CGFloat = pageDimension) -> [UIImage] {
        guard let pdf, let document = PDFDocument(data: pdf) else { return [] }
        return (0..<document.pageCount).compactMap { index in
            guard let page = document.page(at: index) else { return nil }
            let rect = page.bounds(for: .mediaBox)
            let longest = max(rect.width, rect.height)
            let scale = longest > maxDimension ? maxDimension / longest : 1
            return page.thumbnail(of: CGSize(width: rect.width * scale, height: rect.height * scale), for: .mediaBox)
        }
    }

    // MARK: Jakość

    enum Issue: Hashable {
        case blurry, dark

        var message: String {
            switch self {
            case .blurry: "Zdjęcie może być nieostre. Jeśli tekst jest rozmazany, zeskanuj jeszcze raz."
            case .dark: "Zdjęcie jest ciemne. Zeskanuj przy lepszym świetle."
            }
        }
    }

    /// Szybka ocena na zmniejszonej, szarej kopii: jasność (średnia) i ostrość (wariancja laplasjanu).
    /// Progi są ostrożne, żeby nie straszyć przy dobrych skanach.
    static func issues(in image: UIImage) -> [Issue] {
        guard let gray = grayscale(image, width: 256) else { return [] }
        let (pixels, w, h) = gray
        guard w > 2, h > 2 else { return [] }

        var sum = 0.0
        for p in pixels { sum += Double(p) }
        let mean = sum / Double(pixels.count)

        var lapSum = 0.0, lapSq = 0.0, n = 0.0
        for y in 1..<(h - 1) {
            for x in 1..<(w - 1) {
                let c = Double(pixels[y * w + x])
                let v = Double(pixels[(y - 1) * w + x]) + Double(pixels[(y + 1) * w + x])
                    + Double(pixels[y * w + x - 1]) + Double(pixels[y * w + x + 1]) - 4 * c
                lapSum += v; lapSq += v * v; n += 1
            }
        }
        let lapMean = lapSum / n
        let variance = lapSq / n - lapMean * lapMean

        var result: [Issue] = []
        if variance < 30 { result.append(.blurry) }
        if mean < 55 { result.append(.dark) }
        return result
    }

    private static func grayscale(_ image: UIImage, width: Int) -> ([UInt8], Int, Int)? {
        guard let cg = image.cgImage, cg.width > 0 else { return nil }
        let height = max(1, Int(Double(cg.height) * Double(width) / Double(cg.width)))
        var pixels = [UInt8](repeating: 0, count: width * height)
        let ok = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return ok ? (pixels, width, height) : nil
    }

    // MARK: Ochrona plików

    /// Skany SwiftData trzyma jako osobne pliki obok bazy. Dajemy im ochronę „Complete”:
    /// są zaszyfrowane zawsze, gdy telefon jest zablokowany. Sama baza zostaje przy domyślnej
    /// ochronie, żeby akcje z powiadomień (np. „Odnów” na zablokowanym ekranie) dalej działały.
    static func protectScanFiles() {
        let fm = FileManager.default
        guard let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
              let walker = fm.enumerator(at: support, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
        for case let url as URL in walker where url.lastPathComponent.contains("_EXTERNAL_DATA") {
            setComplete(url)
            if let files = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
                files.forEach(setComplete)
            }
        }
    }

    private static func setComplete(_ url: URL) {
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
    }
}
