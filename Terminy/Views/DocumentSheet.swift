import SwiftUI
import SwiftData

/// Wysuwany od dołu arkusz ze szczegółami dokumentu.
struct DocumentSheet: View {
    @Bindable var document: Document
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @AppStorage(NotificationScheduler.reminderHourKey) private var reminderHour = 9
    @State private var confirmDelete = false
    @State private var showScan = false
    @State private var renewTick = 0

    var body: some View {
        let days = document.daysLeft()
        let group = document.group

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(document.category.title.uppercased())
                            .font(.system(size: 12, weight: .heavy)).tracking(0.5).opacity(0.75)
                        Spacer()
                        Image(systemName: document.category.symbol)
                            .font(.system(size: 16, weight: .bold)).opacity(0.75)
                    }
                    Text(document.displayTitle)
                        .font(.system(size: 24, weight: .heavy)).tracking(-0.6)
                    Text(bigDays(days))
                        .font(.system(size: 44, weight: .heavy).monospacedDigit()).tracking(-2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                    if days > 1, let rest = DaysText.headline(to: document.expiryDate).rest {
                        Text("i jeszcze " + rest)
                            .font(.system(size: 18, weight: .heavy)).tracking(-0.3)
                            .contentTransition(.numericText())
                    }
                    if days > 31 {
                        Text("razem \(days) dni")
                            .font(.system(size: 12, weight: .bold)).opacity(0.7)
                    }
                    Text((days < 0 ? "Termin minął " : "Ważne do ") + PL.date(document.expiryDate))
                        .font(.system(size: 13, weight: .semibold)).opacity(0.8)
                        .contentTransition(.numericText())
                }
                .foregroundStyle(days < 0 ? Color.white : group.ink)
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(days < 0 ? Palette.alert : group.color,
                            in: RoundedRectangle(cornerRadius: 24, style: .continuous))

                HStack(spacing: 8) {
                    infoTile(value: "30 dni", caption: "przypomnienie", on: reminder(30))
                    infoTile(value: "7 dni", caption: "przypomnienie", on: reminder(7))
                    infoTile(value: "W dniu", caption: String(format: "o %d:00", reminderHour), on: reminder(0))
                }

                if hasDetails {
                    VStack(alignment: .leading, spacing: 0) {
                        if !document.owner.isEmpty { row("Czyje", document.owner) }
                        if !document.number.isEmpty { row("Numer", document.number) }
                        if document.category == .subscription, let price = document.price {
                            row("Cena", PL.money(price) + " / " + (document.billingCycle ?? .monthly).shortTitle)
                        }
                        if !document.notes.isEmpty { row("Notatki", document.notes) }
                    }
                    .padding(.horizontal, 14)
                    .background(Palette.tile, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }

                if let data = document.scanImageData, let image = UIImage(data: data) {
                    Button { showScan = true } label: {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 120)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(alignment: .bottomLeading) {
                                Label("Skan", systemImage: "doc.viewfinder")
                                    .font(.system(size: 12, weight: .heavy))
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(.ultraThinMaterial, in: Capsule())
                                    .padding(10)
                            }
                    }
                    .buttonStyle(PressScaleStyle(scale: 0.98))
                }

                if confirmDelete {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Usunąć „\(document.displayTitle)”?")
                            .font(.system(size: 16, weight: .heavy))
                        Text("Znikną też przypomnienia i skan. Tego nie da się cofnąć.")
                            .font(.system(size: 13, weight: .semibold)).opacity(0.85)
                        HStack(spacing: 8) {
                            Button {
                                withAnimation(.spring(duration: 0.35)) { confirmDelete = false }
                            } label: {
                                Text("Zostaw")
                                    .font(.system(size: 15, weight: .heavy))
                                    .foregroundStyle(Palette.ink)
                                    .frame(maxWidth: .infinity).frame(height: 48)
                                    .background(Palette.panel, in: Capsule())
                            }
                            Button {
                                dismiss()
                                context.delete(document)
                            } label: {
                                Label("Usuń", systemImage: "trash.fill")
                                    .font(.system(size: 15, weight: .heavy))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity).frame(height: 48)
                                    .background(Palette.alert, in: Capsule())
                            }
                        }
                        .buttonStyle(PressScaleStyle())
                    }
                    .foregroundStyle(Palette.ink)
                    .padding(14)
                    .background(Palette.alert.opacity(0.14), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
                } else {
                    HStack(spacing: 8) {
                        Button {
                            withAnimation(.spring(duration: 0.35)) { confirmDelete = true }
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 17, weight: .heavy))
                                .foregroundStyle(Palette.alert)
                                .frame(width: 52, height: 52)
                                .background(Palette.tile, in: Circle())
                        }
                        .accessibilityLabel("Usuń")

                        Button { router.edit(document) } label: {
                            Label("Edytuj", systemImage: "pencil")
                                .font(.system(size: 15, weight: .heavy))
                                .foregroundStyle(Palette.ink)
                                .padding(.horizontal, 18)
                                .frame(height: 52)
                                .background(Palette.tile, in: Capsule())
                        }

                        Button(action: renew) {
                            Label("Odnowione", systemImage: "checkmark")
                                .font(.system(size: 15, weight: .heavy))
                                .foregroundStyle(Palette.bg)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(Palette.ink, in: Capsule())
                        }
                    }
                    .buttonStyle(PressScaleStyle())
                }
                Text("„Odnowione” przesunie termin na \(PL.date(document.renewedExpiryDate())).")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.muted)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, 16)
            .padding(.top, 22)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(34)
        .presentationBackground(Palette.panel)
        .sensoryFeedback(.success, trigger: renewTick)
        .fullScreenCover(isPresented: $showScan) {
            ScanPreview(data: document.scanImageData)
        }
    }

    private var hasDetails: Bool {
        !document.owner.isEmpty || !document.number.isEmpty || !document.notes.isEmpty
            || (document.category == .subscription && document.price != nil)
    }

    private func reminder(_ offset: Int) -> Bool {
        document.remindersEnabled && NotificationScheduler.enabledOffsets().contains(offset)
    }

    private func bigDays(_ days: Int) -> String {
        switch days {
        case ..<0: "\(-days) \(DaysText.dni(-days)) po"
        case 0: "Dziś"
        case 1: "Jutro"
        default: DaysText.headline(to: document.expiryDate).big
        }
    }

    private func renew() {
        withAnimation(.spring(duration: 0.6, bounce: 0.3)) { document.renew() }
        renewTick += 1
    }

    private func infoTile(value: String, caption: String, on: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 15, weight: .heavy))
            Text(on ? caption : "wyłączone").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.muted)
        }
        .foregroundStyle(Palette.ink)
        .opacity(on ? 1 : 0.5)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.tile, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.muted)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .padding(.vertical, 12)
    }
}

/// Własne okienko potwierdzenia usunięcia (zamiast systemowego).
struct ConfirmDeleteSheet: View {
    let document: Document
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(Palette.alert, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Usunąć „\(document.displayTitle)”?")
                        .font(.system(size: 18, weight: .heavy))
                        .lineLimit(2)
                    Text("Znikną też przypomnienia i skan.")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.muted)
                }
            }
            .foregroundStyle(Palette.ink)

            HStack(spacing: 8) {
                Button { dismiss() } label: {
                    Text("Zostaw")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(Palette.ink)
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .background(Palette.tile, in: Capsule())
                }
                Button {
                    dismiss()
                    withAnimation { context.delete(document) }
                } label: {
                    Text("Usuń")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .background(Palette.alert, in: Capsule())
                }
            }
            .buttonStyle(PressScaleStyle())
        }
        .padding(.horizontal, 16)
        .padding(.top, 26)
        .frame(maxHeight: .infinity, alignment: .top)
        .presentationDetents([.height(210)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(34)
        .presentationBackground(Palette.panel)
    }
}

struct ScanPreview: View {
    let data: Data?
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .gesture(MagnifyGesture()
                        .onChanged { scale = max(1, $0.magnification) }
                        .onEnded { _ in withAnimation(.spring) { scale = 1 } })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(.black)
                    .frame(width: 44, height: 44)
                    .background(.white, in: Circle())
            }
            .buttonStyle(PressScaleStyle())
            .padding(16)
            .accessibilityLabel("Zamknij")
        }
    }
}
