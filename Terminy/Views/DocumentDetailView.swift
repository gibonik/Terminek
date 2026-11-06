import SwiftUI
import SwiftData

struct DocumentDetailView: View {
    @Bindable var document: Document
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var editing = false
    @State private var confirmRenew = false
    @State private var confirmDelete = false
    @State private var showScan = false

    var body: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    Image(systemName: document.category.symbol)
                        .font(.largeTitle)
                        .foregroundStyle(.tint)
                    Text(document.expiryDate.formatted(date: .long, time: .omitted))
                        .font(.title2.weight(.semibold))
                    DaysLeftBadge(daysLeft: document.daysLeft())
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Section("Szczegóły") {
                LabeledContent("Rodzaj", value: document.category.title)
                if !document.owner.isEmpty { LabeledContent("Czyje", value: document.owner) }
                if !document.number.isEmpty {
                    LabeledContent("Numer") {
                        Text(document.number).textSelection(.enabled)
                    }
                }
                if document.category == .subscription {
                    if let price = document.price {
                        LabeledContent("Cena", value: price.formatted(.currency(code: "PLN")))
                    }
                    if let cycle = document.billingCycle {
                        LabeledContent("Rozliczenie", value: cycle.title)
                    }
                }
                LabeledContent("Przypomnienia", value: document.remindersEnabled ? "30 i 7 dni przed" : "wyłączone")
            }

            if !document.notes.isEmpty {
                Section("Notatki") { Text(document.notes) }
            }

            if let data = document.scanImageData, let image = UIImage(data: data) {
                Section("Skan") {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .onTapGesture { showScan = true }
                }
            }

            Section {
                Button {
                    confirmRenew = true
                } label: {
                    Label("Odnowione – przesuń termin", systemImage: "arrow.clockwise")
                }
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("Usuń dokument", systemImage: "trash")
                }
            }
        }
        .navigationTitle(document.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Edytuj") { editing = true }
        }
        .sheet(isPresented: $editing) {
            DocumentEditView(document: document)
        }
        .fullScreenCover(isPresented: $showScan) {
            ScanPreview(data: document.scanImageData)
        }
        .confirmationDialog("Przesunąć termin na \(document.renewedExpiryDate().formatted(date: .long, time: .omitted))?",
                            isPresented: $confirmRenew, titleVisibility: .visible) {
            Button("Przesuń") { withAnimation { document.renew() } }
            Button("Ustawię datę ręcznie") { editing = true }
        }
        .confirmationDialog("Usunąć ten dokument?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Usuń", role: .destructive) {
                context.delete(document)
                dismiss()
            }
        }
    }
}

private struct ScanPreview: View {
    let data: Data?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let data, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFit()
                }
            }
            .toolbar { Button("Zamknij") { dismiss() } }
        }
    }
}
