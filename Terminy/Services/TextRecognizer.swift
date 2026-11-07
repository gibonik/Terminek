import UIKit
import Vision

/// OCR na urządzeniu (Vision). Nic nie wychodzi poza telefon.
enum TextRecognizer {
    static func recognizeText(in image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else { return "" }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)

        // Vision jest synchroniczny i ciężki – odpalamy go poza głównym wątkiem.
        return try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            // Języki, których Vision nie obsługuje na danym iOS, wywalają cały odczyt błędem,
            // więc bierzemy tylko obsługiwane (polski doszedł dopiero w nowszych wersjach).
            let wanted = ["pl-PL", "en-US"]
            let supported = (try? request.supportedRecognitionLanguages()) ?? ["en-US"]
            let languages = wanted.filter(supported.contains)
            request.recognitionLanguages = languages.isEmpty ? ["en-US"] : languages
            request.usesLanguageCorrection = false // autokorekta psuje daty i numery

            try VNImageRequestHandler(cgImage: cgImage, orientation: orientation).perform([request])
            return (request.results ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
        }.value
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
