import SwiftUI

/// Jeden wiersz w odpowiedzi Siri (bez numerów i skanów).
struct SnippetRow: Identifiable {
    let id: UUID
    let title: String
    let category: DocumentCategory
    let expiryDate: Date
    let daysLeft: Int

    @MainActor
    init(_ document: Document) {
        id = document.id
        title = document.displayTitle
        category = document.category
        expiryDate = document.expiryDate
        daysLeft = document.daysLeft()
    }
}

/// Podgląd pod odpowiedzią Siri i w Skrótach: karta dokumentu albo krótka lista.
struct Snippet: View {
    var card: CardData?
    var rows: [SnippetRow] = []

    var body: some View {
        VStack(spacing: DT.Space.sm) {
            if let card {
                DocCard(data: card, tilt: false)
                    .padding(.vertical, DT.Space.xs)
            }
            ForEach(rows) { row in
                HStack(spacing: DT.Space.sm) {
                    MiniCard(category: row.category)
                    VStack(alignment: .leading, spacing: DT.Space.xxs) {
                        Text(row.title)
                            .font(DT.Typography.headline)
                            .foregroundStyle(DT.Palette.textPrimary)
                            .lineLimit(1)
                        Text(PL.date(row.expiryDate))
                            .font(DT.Typography.footnote)
                            .foregroundStyle(DT.Palette.textSecondary)
                    }
                    Spacer(minLength: DT.Space.xs)
                    Text(DaysText.compact(to: row.expiryDate))
                        .font(DT.Typography.subheadlineEmphasized)
                        .monospacedDigit()
                        .foregroundStyle(row.daysLeft < 0 ? DT.Palette.danger : row.daysLeft <= 7 ? DT.Palette.warning : DT.Palette.textPrimary)
                }
            }
        }
        .padding(rows.isEmpty && card == nil ? 0 : DT.Space.md)
    }
}
