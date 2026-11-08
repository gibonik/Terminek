import SwiftUI

/// Regulamin i polityka prywatności w aplikacji. Ten sam tekst co na stronie www
/// (pliki `docs/legal/*.md` są dołączone do aplikacji).
enum LegalDocument: String, Identifiable, CaseIterable {
    case terms = "regulamin"
    case privacy = "prywatnosc"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .terms: "Regulamin"
        case .privacy: "Polityka prywatności"
        }
    }

    var symbol: String {
        switch self {
        case .terms: "doc.plaintext"
        case .privacy: "hand.raised"
        }
    }

    var text: String {
        guard let url = Bundle.main.url(forResource: rawValue, withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "# \(title)\n\nNie udało się wczytać dokumentu." }
        return text
    }
}

struct LegalView: View {
    let document: LegalDocument
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                RoundIconButton(symbol: "xmark", label: "Zamknij") { dismiss() }
            }
            .padding(.horizontal, DT.Space.gutter)
            .padding(.top, DT.Space.md)
            ScrollView {
                MarkdownBlocks(text: document.text)
                    .padding(.horizontal, DT.Space.gutter)
                    .padding(.bottom, DT.Space.xxl)
            }
            .scrollIndicators(.hidden)
        }
        .background(AppBackground())
        .foregroundStyle(DT.Palette.textPrimary)
    }
}

/// Prosty widok Markdownu: nagłówki, akapity, listy i tabele (jako wiersze z kropkami).
struct MarkdownBlocks: View {
    let text: String

    private enum Block: Hashable {
        case title(String), heading(String), paragraph(String), bullet(String), row([String], header: Bool)
    }

    private var blocks: [Block] {
        var result: [Block] = []
        var inTable = false
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if !line.hasPrefix("|") { inTable = false }
            if line.isEmpty { continue }
            if line.hasPrefix("# ") { result.append(.title(String(line.dropFirst(2)))) }
            else if line.hasPrefix("## ") { result.append(.heading(String(line.dropFirst(3)))) }
            else if line.hasPrefix("- ") { result.append(.bullet(String(line.dropFirst(2)))) }
            else if line.hasPrefix("|") {
                let cells = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                if cells.allSatisfy({ $0.allSatisfy { $0 == "-" || $0 == ":" } }) { continue }
                result.append(.row(cells, header: !inTable))
                inTable = true
            } else { result.append(.paragraph(line)) }
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DT.Space.sm) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .title(let t):
                    Text(inline(t)).font(DT.Typography.title2).padding(.bottom, DT.Space.xs)
                case .heading(let t):
                    Text(inline(t)).font(DT.Typography.headline).padding(.top, DT.Space.sm)
                case .paragraph(let t):
                    Text(inline(t)).font(DT.Typography.body).foregroundStyle(DT.Palette.textSecondary)
                case .bullet(let t):
                    HStack(alignment: .firstTextBaseline, spacing: DT.Space.xs) {
                        Text("•").foregroundStyle(DT.Palette.accentText)
                        Text(inline(t)).foregroundStyle(DT.Palette.textSecondary)
                    }
                    .font(DT.Typography.body)
                case .row(let cells, let header):
                    if !header {
                        VStack(alignment: .leading, spacing: DT.Space.xxs) {
                            Text(inline(cells.first ?? "")).font(DT.Typography.subheadlineEmphasized)
                            Text(inline(cells.dropFirst().joined(separator: " · ")))
                                .font(DT.Typography.footnote)
                                .foregroundStyle(DT.Palette.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(DT.Space.sm)
                        .panel()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tint(DT.Palette.accentText)
    }

    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}
