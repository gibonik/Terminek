import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Zapis i wczytanie kopii zapasowej. Hasło szyfruje plik; bez niego kopii nie da się otworzyć.
struct BackupSheet: View {
    enum Mode: Identifiable {
        case export
        case restore(Data)
        var id: String {
            switch self {
            case .export: "export"
            case .restore: "restore"
            }
        }
    }

    static let lastBackupKey = "lastBackupDate"

    let mode: Mode
    var onRestored: (Backup.ImportResult) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var documents: [Document]
    @State private var password = ""
    @State private var repeated = ""
    @State private var working = false
    @State private var error: String?
    @State private var shareItems: ShareItems?
    @FocusState private var focus: Int?

    private var isExport: Bool { if case .export = mode { true } else { false } }

    private var canContinue: Bool {
        guard !working else { return false }
        if isExport { return password.count >= Backup.minPasswordLength && password == repeated }
        return !password.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DT.Space.lg) {
            HStack {
                Text(isExport ? "Zapisz kopię" : "Wczytaj kopię").font(DT.Typography.title2)
                Spacer()
                RoundIconButton(symbol: "xmark", label: "Zamknij") { dismiss() }
            }

            Text(isExport
                 ? "Kopia zawiera wszystkie dokumenty (\(documents.count)) razem ze skanami. Ustaw hasło: bez niego nikt jej nie otworzy, także Ty. Zapisz plik w Plikach, na dysku Google albo wyślij sobie mailem."
                 : "Dokumenty z kopii zostaną dodane. Te, które już są w aplikacji, zostaną zastąpione wersją z kopii.")
                .font(DT.Typography.subheadline)
                .foregroundStyle(DT.Palette.textSecondary)

            VStack(spacing: 0) {
                secureField(isExport ? "Hasło (min. \(Backup.minPasswordLength) znaków)" : "Hasło do kopii", text: $password, tag: 0)
                if isExport {
                    Rectangle().fill(DT.Palette.separator).frame(height: DT.Size.hairline).padding(.leading, DT.Space.md)
                    secureField("Powtórz hasło", text: $repeated, tag: 1)
                }
            }
            .panel()

            if isExport && !repeated.isEmpty && password != repeated {
                Label("Hasła się różnią.", systemImage: "exclamationmark.triangle")
                    .font(DT.Typography.footnote)
                    .foregroundStyle(DT.Palette.warning)
            }
            if let error {
                Label(error, systemImage: "xmark.octagon")
                    .font(DT.Typography.footnote)
                    .foregroundStyle(DT.Palette.danger)
            }

            Spacer(minLength: 0)

            PrimaryButton(title: working ? "Chwila…" : isExport ? "Zapisz kopię" : "Wczytaj",
                          symbol: working ? nil : isExport ? "lock.doc" : "arrow.down.doc") { run() }
                .disabled(!canContinue)
                .opacity(canContinue ? 1 : 0.5)
        }
        .padding(DT.Space.gutter)
        .background(AppBackground())
        .foregroundStyle(DT.Palette.textPrimary)
        .presentationDetents([.medium, .large])
        .onAppear { focus = 0 }
        .sheet(item: $shareItems, onDismiss: { BackupSheet.removeTemporaryFiles() }) { items in
            ActivitySheet(items: items.items) { saved in
                if saved {
                    UserDefaults.standard.set(Date.now, forKey: Self.lastBackupKey)
                    Breadcrumbs.add("Kopia zapisana")
                    dismiss()
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func secureField(_ title: String, text: Binding<String>, tag: Int) -> some View {
        SecureField("", text: text, prompt: Text(title).foregroundStyle(DT.Palette.textTertiary))
            .font(DT.Typography.body)
            .textContentType(isExport ? .newPassword : .password)
            .focused($focus, equals: tag)
            .submitLabel(tag == 0 && isExport ? .next : .done)
            .onSubmit { if tag == 0 && isExport { focus = 1 } else if canContinue { run() } }
            .padding(.horizontal, DT.Space.md)
            .frame(minHeight: DT.Size.toggleRow)
    }

    private func run() {
        guard canContinue else { return }
        focus = nil
        error = nil
        working = true
        let password = password
        switch mode {
        case .export:
            let docs = documents
            // Szyfrowanie kilkudziesięciu skanów to chwila, więc poza głównym wątkiem
            // (najpierw kopiujemy dane z modeli na głównym).
            let items = docs.map(Backup.Item.init)
            Task {
                defer { working = false }
                do {
                    let data = try await Task.detached(priority: .userInitiated) {
                        try Backup.export(items: items, password: password)
                    }.value
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent(Backup.fileName())
                    try data.write(to: url, options: [.atomic, .completeFileProtection])
                    shareItems = ShareItems(items: [url])
                } catch {
                    self.error = error.localizedDescription
                }
            }
        case .restore(let data):
            Task {
                defer { working = false }
                do {
                    let payload = try await Task.detached(priority: .userInitiated) {
                        try Backup.read(data, password: password)
                    }.value
                    let result = try Backup.restore(payload, into: context)
                    Breadcrumbs.add("Kopia wczytana: +\(result.added), zmienione \(result.updated)")
                    Haptics.shared.fire(.renew)
                    onRestored(result)
                    dismiss()
                } catch {
                    Haptics.shared.fire(.pull)
                    self.error = error.localizedDescription
                }
            }
        }
    }

    static func removeTemporaryFiles() {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: fm.temporaryDirectory, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == Backup.fileExtension { try? fm.removeItem(at: file) }
    }
}
