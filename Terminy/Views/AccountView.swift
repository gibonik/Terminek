import SwiftUI
import SwiftData
import UserNotifications
import StoreKit
import AppIntents

/// Konto: przypomnienia (kiedy i o czym), oś najbliższych powiadomień, wygląd i bezpieczeństwo.
struct AccountView: View {
    @Environment(AppLock.self) private var lock
    @Environment(AppRouter.self) private var router
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Document.expiryDate) private var documents: [Document]

    @AppStorage(NotificationScheduler.reminderHourKey) private var reminderHour = 9
    @AppStorage(NotificationScheduler.offsetKey(30)) private var remind30 = true
    @AppStorage(NotificationScheduler.offsetKey(7)) private var remind7 = true
    @AppStorage(NotificationScheduler.offsetKey(0)) private var remind0 = true
    @AppStorage(Haptics.enabledKey) private var haptics = true
    @AppStorage(AppAppearance.key) private var appearance = AppAppearance.system.rawValue
    @AppStorage(AppRouter.shakeKey) private var shakeToReport = true
    @State private var backup: BackupSheet.Mode?
    @State private var importing = false
    @State private var status: UNAuthorizationStatus = .notDetermined
    @State private var testSent = 0
    @State private var paywall: PaywallReason?
    @State private var manageSubscriptions = false
    @State private var versionTaps = 0
    @AppStorage(Store.developerMenuKey) private var developerMenu = false
    @State private var legal: LegalDocument?
    @State private var reportCount = Diagnostics.shared.reports.count
    @Namespace private var themePill

    private var upcoming: [NotificationScheduler.PlannedReminder] {
        Array(NotificationScheduler.plannedReminders(
            for: documents, hour: reminderHour, now: .now,
            offsets: NotificationScheduler.enabledOffsets()
        ).prefix(8))
    }

    var body: some View {
        @Bindable var lock = lock
        ScrollView {
            VStack(alignment: .leading, spacing: DT.Space.lg) {
                Text("Konto").font(DT.Typography.largeTitle).riseIn(0)

                profileCard.riseIn(1)

                plusCard.riseIn(1)

                if status == .denied { deniedBanner.riseIn(2) }

                group("Przypomnienia", index: 2) {
                    toggle("calendar.badge.clock", "Miesiąc przed", isOn: $remind30)
                    divider
                    toggle("calendar", "Tydzień przed", isOn: $remind7)
                    divider
                    toggle("exclamationmark.circle", "W dniu terminu", isOn: $remind0)
                    divider
                    HStack(spacing: DT.Space.sm) {
                        icon("clock")
                        Text("Godzina").font(DT.Typography.body)
                        Spacer()
                        Picker("Godzina", selection: $reminderHour) {
                            ForEach(6..<23, id: \.self) { Text(verbatim: "\($0):00").tag($0) }
                        }
                        .labelsHidden()
                        .tint(DT.Palette.accentText)
                    }
                    .padding(.horizontal, DT.Space.md)
                    .frame(minHeight: DT.Size.toggleRow)
                    divider
                    Button {
                        testSent += 1
                        let doc = documents.first { $0.daysLeft() >= 0 } ?? documents.first
                        Task { await NotificationScheduler.shared.sendTest(for: doc) }
                    } label: {
                        HStack(spacing: DT.Space.sm) {
                            Image(systemName: "bell.badge.fill")
                                .font(DT.Typography.subheadlineEmphasized)
                                .foregroundStyle(DT.Palette.onAccent)
                                .frame(width: DT.Size.iconBadge, height: DT.Size.iconBadge)
                                .background(DT.Palette.accent, in: Circle())
                                .symbolEffect(.bounce, value: testSent)
                            Text(testSent == 0 ? "Wyślij próbne powiadomienie" : "Wysłane, przyjdzie za 5 sekund")
                                .font(DT.Typography.body)
                                .foregroundStyle(DT.Palette.accentText)
                                .contentTransition(.opacity)
                            Spacer()
                        }
                        .padding(.horizontal, DT.Space.md)
                        .frame(minHeight: DT.Size.toggleRow)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(CardPressStyle())
                }

                timeline.riseIn(3)

                VStack(alignment: .leading, spacing: DT.Space.sm) {
                    overline("Wygląd")
                    themePicker
                }
                .riseIn(4)

                group("Bezpieczeństwo i urządzenie", index: 5) {
                    toggle("faceid", "Blokada \(lock.biometryName)", isOn: $lock.isEnabled)
                    divider
                    toggle("iphone.radiowaves.left.and.right", "Wibracje", isOn: $haptics)
                    divider
                    HStack(spacing: DT.Space.sm) {
                        icon(TerminyApp.usesCloudKit ? "icloud" : "iphone")
                        Text("Zapis").font(DT.Typography.body)
                        Spacer()
                        Text(TerminyApp.usesCloudKit ? "iCloud" : "Tylko ten iPhone")
                            .font(DT.Typography.subheadline)
                            .foregroundStyle(DT.Palette.textSecondary)
                    }
                    .padding(.horizontal, DT.Space.md)
                    .frame(minHeight: DT.Size.toggleRow)
                }

                group("Kopia zapasowa", index: 5) {
                    Button { backup = .export } label: {
                        HStack(spacing: DT.Space.sm) {
                            icon("lock.doc")
                            VStack(alignment: .leading, spacing: 0) {
                                Text("Zapisz kopię").font(DT.Typography.body).foregroundStyle(DT.Palette.textPrimary)
                                Text(lastBackupText)
                                    .font(DT.Typography.footnote)
                                    .foregroundStyle(backupIsStale ? DT.Palette.warning : DT.Palette.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(DT.Typography.footnoteEmphasized).foregroundStyle(DT.Palette.textTertiary)
                        }
                        .padding(.horizontal, DT.Space.md)
                        .padding(.vertical, DT.Space.xs)
                        .frame(minHeight: DT.Size.toggleRow)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(documents.isEmpty)
                    divider
                    Button { importing = true } label: {
                        row("arrow.down.doc", "Wczytaj kopię", chevron: true)
                    }
                    .buttonStyle(.plain)
                }
                .sheet(item: $backup) { mode in
                    BackupSheet(mode: mode) { result in
                        router.show("Wczytano: nowe \(result.added), zastąpione \(result.updated)", symbol: "arrow.down.doc.fill")
                    }
                }
                .fileImporter(isPresented: $importing, allowedContentTypes: [.data, .item]) { result in
                    switch result {
                    case .success(let url):
                        let access = url.startAccessingSecurityScopedResource()
                        defer { if access { url.stopAccessingSecurityScopedResource() } }
                        if let data = try? Data(contentsOf: url) {
                            backup = .restore(data)
                        } else {
                            router.show("Nie udało się otworzyć pliku.", symbol: "xmark.octagon.fill")
                        }
                    case .failure:
                        break
                    }
                }

                group("Siri i skróty", index: 5) {
                    Button { router.showShortcutsHelp = true } label: {
                        row("mic", "Co powiedzieć Siri", chevron: true)
                    }
                    .buttonStyle(.plain)
                    divider
                    HStack(spacing: DT.Space.sm) {
                        icon("square.2.layers.3d")
                        Text("Aplikacja Skróty").font(DT.Typography.body)
                        Spacer()
                        ShortcutsLink()
                            .shortcutsLinkStyle(.automaticOutline)
                    }
                    .padding(.horizontal, DT.Space.md)
                    .frame(minHeight: DT.Size.toggleRow)
                }
                .sheet(isPresented: Binding(get: { router.showShortcutsHelp }, set: { router.showShortcutsHelp = $0 })) {
                    ShortcutsHelpSheet()
                }

                group("Pomoc", index: 6) {
                    Button { BugReportPresenter.present(BugReportRequest(kind: .bug)) } label: {
                        row("ladybug", "Zgłoś błąd", chevron: true)
                    }
                    .buttonStyle(.plain)
                    divider
                    Button { BugReportPresenter.present(BugReportRequest(kind: .idea)) } label: {
                        row("lightbulb", "Zaproponuj funkcję", chevron: true)
                    }
                    .buttonStyle(.plain)
                    divider
                    toggle("iphone.gen3.radiowaves.left.and.right", "Potrząśnij, by zgłosić błąd", isOn: $shakeToReport)
                }

                group("Informacje", index: 6) {
                    ForEach(Array(LegalDocument.allCases.enumerated()), id: \.element) { index, doc in
                        if index > 0 { divider }
                        Button { legal = doc } label: {
                            HStack(spacing: DT.Space.sm) {
                                icon(doc.symbol)
                                Text(doc.title).font(DT.Typography.body).foregroundStyle(DT.Palette.textPrimary)
                                Spacer()
                                Image(systemName: "chevron.right").font(DT.Typography.footnoteEmphasized).foregroundStyle(DT.Palette.textTertiary)
                            }
                            .padding(.horizontal, DT.Space.md)
                            .frame(minHeight: DT.Size.toggleRow)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .sheet(item: $legal) { LegalView(document: $0) }

                if developerMenu {
                    group("Menu deweloperskie", index: 6) {
                        HStack(spacing: DT.Space.sm) {
                            icon("ladybug")
                            Text("Raporty awarii").font(DT.Typography.body)
                            Spacer()
                            if let latest = Diagnostics.shared.reports.first {
                                ShareLink(item: latest) {
                                    Text("Wyślij (\(reportCount))").font(DT.Typography.subheadlineEmphasized)
                                }
                                .tint(DT.Palette.accentText)
                            } else {
                                Text("Brak").font(DT.Typography.subheadline).foregroundStyle(DT.Palette.textSecondary)
                            }
                        }
                        .padding(.horizontal, DT.Space.md)
                        .frame(minHeight: DT.Size.toggleRow)
                        .onAppear { reportCount = Diagnostics.shared.reports.count }
                        divider
                        toggle("hammer", "Plus testowy (bez płatności)", isOn: Binding(
                            get: { Store.shared.debugPlus }, set: { Store.shared.setDebugPlus($0) }))
                        divider
                        Button {
                            UserDefaults.standard.removeObject(forKey: "assistantDay")
                            Haptics.shared.fire(.stamp)
                        } label: {
                            HStack(spacing: DT.Space.sm) {
                                icon("sparkles")
                                Text("Wyzeruj pytania do asystenta").font(DT.Typography.body).foregroundStyle(DT.Palette.textPrimary)
                                Spacer()
                            }
                            .padding(.horizontal, DT.Space.md)
                            .frame(minHeight: DT.Size.toggleRow)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        divider
                        Button {
                            developerMenu = false
                            versionTaps = 0
                        } label: {
                            HStack(spacing: DT.Space.sm) {
                                icon("eye.slash")
                                Text("Ukryj menu").font(DT.Typography.body).foregroundStyle(DT.Palette.textPrimary)
                                Spacer()
                            }
                            .padding(.horizontal, DT.Space.md)
                            .frame(minHeight: DT.Size.toggleRow)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text("Terminek · wersja \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                    .font(DT.Typography.footnote)
                    .foregroundStyle(DT.Palette.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: DT.Size.touch)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        versionTaps += 1
                        if versionTaps >= 7 && !developerMenu {
                            developerMenu = true
                            Haptics.shared.fire(.renew)
                        }
                    }
                    .riseIn(6)
            }
            .padding(.horizontal, DT.Space.gutter)
            .padding(.top, DT.Space.xs)
            .padding(.bottom, DT.Space.tabBarClearance)
        }
        .scrollIndicators(.hidden)
        .onChange(of: "\(reminderHour)-\(remind30)-\(remind7)-\(remind0)") {
            Task { await NotificationScheduler.shared.reschedule(documents) }
        }
        .onChange(of: haptics) { _, on in if on { Haptics.shared.fire(.stow) } }
        .task(id: scenePhase) {
            status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        }
    }

    // MARK: Elementy

    private var profileCard: some View {
        let monthly = documents.filter { $0.category == .subscription }.reduce(0.0) { $0 + $1.monthlyCost }
        return HStack(spacing: DT.Space.md) {
            ZStack {
                Circle().fill(DT.Palette.Card.highlight.opacity(0.2))
                Image(systemName: "rectangle.stack.fill").font(DT.Typography.title3)
            }
            .frame(width: DT.Size.ring, height: DT.Size.ring)
            VStack(alignment: .leading, spacing: DT.Space.xxs) {
                Text("Twój portfel").font(DT.Typography.headline)
                Text(Assistant.documentsCount(documents.count))
                    .font(DT.Typography.subheadline).opacity(0.85)
                if monthly > 0 {
                    Text("Abonamenty: \(PL.money(monthly)) miesięcznie")
                        .font(DT.Typography.footnote).opacity(0.85)
                }
            }
            Spacer()
        }
        .foregroundStyle(DT.Palette.Card.ink)
        .padding(DT.Space.gutter)
        .background { LiveGradient(colors: DT.Palette.Card.brand) }
        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.panel, style: .continuous))
        .shadow(color: DT.Palette.accent.opacity(0.35), radius: DT.Space.lg, y: DT.Space.sm)
    }

    private var plusCard: some View {
        let store = Store.shared
        return VStack(alignment: .leading, spacing: DT.Space.sm) {
            HStack(spacing: DT.Space.sm) {
                Image(systemName: "sparkles")
                    .font(DT.Typography.subheadlineEmphasized)
                    .foregroundStyle(DT.Palette.onAccent)
                    .frame(width: DT.Size.iconBadge, height: DT.Size.iconBadge)
                    .background(DT.Palette.accent, in: Circle())
                VStack(alignment: .leading, spacing: 0) {
                    Text(store.isPlus ? "Terminek Plus" : "Darmowy plan").font(DT.Typography.headline)
                    Text(store.isPlus
                         ? (store.debugPlus && store.purchased.isEmpty ? "Włączony testowo" : store.hasLifetime ? "Na zawsze" : "Aktywny")
                         : "Dokumenty: \(min(documents.count, Store.freeDocuments)) z \(Store.freeDocuments)")
                        .font(DT.Typography.footnote)
                        .foregroundStyle(DT.Palette.textSecondary)
                }
                Spacer()
                if !store.isPlus {
                    Button("Odblokuj") { paywall = .manual }
                        .font(DT.Typography.subheadlineEmphasized)
                        .foregroundStyle(DT.Palette.onAccent)
                        .padding(.horizontal, DT.Space.md)
                        .frame(minHeight: DT.Size.pill)
                        .background(DT.Palette.accent, in: Capsule())
                }
            }
            if !store.isPlus {
                ProgressView(value: Double(min(documents.count, Store.freeDocuments)), total: Double(Store.freeDocuments))
                    .tint(documents.count >= Store.freeDocuments ? DT.Palette.warning : DT.Palette.accent)
            }
            HStack(spacing: DT.Space.md) {
                Button("Przywróć zakupy") { Task { await store.restore() } }
                if !store.purchased.isEmpty && !store.hasLifetime {
                    Button("Zarządzaj subskrypcją") { manageSubscriptions = true }
                }
            }
            .font(DT.Typography.footnoteEmphasized)
            .foregroundStyle(DT.Palette.accentText)
            if let message = store.message {
                Text(message).font(DT.Typography.footnote).foregroundStyle(DT.Palette.textSecondary)
            }
        }
        .padding(DT.Space.md)
        .panel()
        .sheet(item: $paywall) { reason in PaywallView(reason: reason) }
        .manageSubscriptionsSheet(isPresented: $manageSubscriptions)
    }

    private var deniedBanner: some View {
        Button {
            if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
        } label: {
            HStack(spacing: DT.Space.sm) {
                Image(systemName: "bell.slash.fill").font(DT.Typography.title3)
                VStack(alignment: .leading, spacing: DT.Space.xxs) {
                    Text("Powiadomienia są wyłączone").font(DT.Typography.headline)
                    Text("Stuknij, żeby włączyć je w Ustawieniach iPhone'a.").font(DT.Typography.footnote).opacity(0.9)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
            }
            .foregroundStyle(DT.Palette.onDanger)
            .padding(DT.Space.md)
            .background(DT.Palette.dangerFill, in: RoundedRectangle(cornerRadius: DT.Radius.panel, style: .continuous))
        }
        .buttonStyle(CardPressStyle())
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: DT.Space.sm) {
            overline("Najbliższe powiadomienia")
            if upcoming.isEmpty {
                Text(documents.isEmpty ? "Dodaj dokument, a tu pojawią się jego przypomnienia." : "Nie ma zaplanowanych przypomnień.")
                    .font(DT.Typography.subheadline)
                    .foregroundStyle(DT.Palette.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: DT.Size.tile)
                    .panel()
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(upcoming.enumerated()), id: \.element.identifier) { index, reminder in
                        TimelineRow(reminder: reminder,
                                    document: documents.first { $0.id == reminder.documentID },
                                    isFirst: index == 0,
                                    isLast: index == upcoming.count - 1)
                    }
                }
                .padding(.vertical, DT.Space.xs)
                .panel()
            }
        }
    }

    private var themePicker: some View {
        HStack(spacing: DT.Space.xxs) {
            ForEach(AppAppearance.allCases) { option in
                let isOn = appearance == option.rawValue
                Button {
                    withAnimation(DT.Motion.bouncy) { appearance = option.rawValue }
                } label: {
                    Text(option.title)
                        .font(DT.Typography.subheadlineEmphasized)
                        .foregroundStyle(isOn ? DT.Palette.onAccent : DT.Palette.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: DT.Size.touch)
                        .background {
                            if isOn {
                                Capsule().fill(DT.Palette.accent).matchedGeometryEffect(id: "theme", in: themePill)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(DT.Space.xxs)
        .panelCapsule()
    }

    private func group<Content: View>(_ title: String, index: Int, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DT.Space.sm) {
            overline(title)
            VStack(spacing: 0) { content() }.panel()
        }
        .riseIn(index)
    }

    private func overline(_ text: String) -> some View {
        Text(text.uppercased())
            .font(DT.Typography.overline)
            .kerning(DT.Size.hairline)
            .foregroundStyle(DT.Palette.textSecondary)
            .accessibilityAddTraits(.isHeader)
    }

    private var divider: some View {
        Rectangle().fill(DT.Palette.separator).frame(height: DT.Size.hairline)
            .padding(.leading, DT.Space.md + DT.Size.iconBadge + DT.Space.sm)
    }

    private func icon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(DT.Typography.subheadlineEmphasized)
            .foregroundStyle(DT.Palette.accentText)
            .frame(width: DT.Size.iconBadge, height: DT.Size.iconBadge)
            .background(DT.Palette.accent.opacity(0.14), in: Circle())
    }

    private var lastBackup: Date? { UserDefaults.standard.object(forKey: BackupSheet.lastBackupKey) as? Date }

    /// Bez iCloud kopia to jedyne zabezpieczenie danych, więc przypominamy o niej po miesiącu.
    private var backupIsStale: Bool {
        guard !TerminyApp.usesCloudKit, !documents.isEmpty else { return false }
        guard let lastBackup else { return true }
        return Date.now.timeIntervalSince(lastBackup) > 30 * 24 * 3600
    }

    private var lastBackupText: String {
        guard let lastBackup else { return TerminyApp.usesCloudKit ? "Dane są też w iCloud" : "Jeszcze nie zapisano kopii" }
        return "Ostatnia: \(PL.date(lastBackup))"
    }

    private func row(_ symbol: String, _ title: String, chevron: Bool = false) -> some View {
        HStack(spacing: DT.Space.sm) {
            icon(symbol)
            Text(title).font(DT.Typography.body).foregroundStyle(DT.Palette.textPrimary)
            Spacer()
            if chevron {
                Image(systemName: "chevron.right").font(DT.Typography.footnoteEmphasized).foregroundStyle(DT.Palette.textTertiary)
            }
        }
        .padding(.horizontal, DT.Space.md)
        .frame(minHeight: DT.Size.toggleRow)
        .contentShape(Rectangle())
    }

    private func toggle(_ symbol: String, _ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: DT.Space.sm) {
                icon(symbol)
                Text(title).font(DT.Typography.body)
            }
        }
        .tint(DT.Palette.accent)
        .padding(.horizontal, DT.Space.md)
        .frame(minHeight: DT.Size.toggleRow)
    }
}

/// Punkt na osi przypomnień.
struct TimelineRow: View {
    let reminder: NotificationScheduler.PlannedReminder
    let document: Document?
    let isFirst: Bool
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: DT.Space.sm) {
            VStack(spacing: 0) {
                Rectangle().fill(isFirst ? .clear : DT.Palette.separator).frame(width: DT.Size.hairline * 2, height: DT.Space.md)
                Circle()
                    .fill(isFirst ? DT.Palette.accent : (document?.group.color ?? DT.Palette.textSecondary))
                    .frame(width: DT.Size.timelineDot, height: DT.Size.timelineDot)
                    .shadow(color: isFirst ? DT.Palette.accent.opacity(0.6) : .clear, radius: DT.Space.xs)
                Rectangle().fill(isLast ? .clear : DT.Palette.separator).frame(width: DT.Size.hairline * 2).frame(maxHeight: .infinity)
            }
            .frame(width: DT.Size.timelineDot + DT.Space.xxs)

            VStack(alignment: .leading, spacing: DT.Space.xxs) {
                Text(PL.dayAndMonth(reminder.fireDate) + ", " + reminder.fireDate.formatted(.dateTime.hour().minute().locale(PL.locale)))
                    .font(DT.Typography.captionEmphasized)
                    .foregroundStyle(isFirst ? DT.Palette.accentText : DT.Palette.textSecondary)
                Text(reminder.title).font(DT.Typography.subheadlineEmphasized).foregroundStyle(DT.Palette.textPrimary)
                Text(reminder.body)
                    .font(DT.Typography.footnote)
                    .foregroundStyle(DT.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, DT.Space.sm)
            .padding(.bottom, DT.Space.xs)
            Spacer(minLength: 0)
            if let document { MiniCard(category: document.category).padding(.top, DT.Space.sm) }
        }
        .padding(.horizontal, DT.Space.md)
        .accessibilityElement(children: .combine)
    }
}

/// Jak używać skrótów: przykładowe frazy i przyciski do dodania.
struct ShortcutsHelpSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let examples: [(symbol: String, polish: String, english: String)] = [
        ("hourglass", "Najbliższy termin w Terminku", "What's my next deadline in Terminek"),
        ("calendar.badge.clock", "Kiedy kończy się OC w Terminku", "When does OC expire in Terminek"),
        ("exclamationmark.triangle", "Co wygasa w Terminku", "What expires soon in Terminek"),
        ("arrow.clockwise", "Odnów OC w Terminku", "Renew OC in Terminek"),
        ("doc.viewfinder", "Zeskanuj dokument w Terminku", "Scan a document in Terminek"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DT.Space.lg) {
                HStack {
                    Text("Siri i skróty").font(DT.Typography.title2)
                    Spacer()
                    RoundIconButton(symbol: "xmark", label: "Zamknij") { dismiss() }
                }
                Text("Siri nie mówi jeszcze po polsku. Jeśli masz Siri po angielsku, użyj angielskiej frazy. Po polsku skróty działają w aplikacji Skróty, w Spotlight, pod przyciskiem czynności i po stuknięciu w tył iPhone'a (Ustawienia › Dostępność › Dotyk).")
                    .font(DT.Typography.subheadline)
                    .foregroundStyle(DT.Palette.textSecondary)

                VStack(spacing: 0) {
                    ForEach(Array(examples.enumerated()), id: \.offset) { index, item in
                        if index > 0 {
                            Rectangle().fill(DT.Palette.separator).frame(height: DT.Size.hairline)
                                .padding(.leading, DT.Space.md + DT.Size.iconBadge + DT.Space.sm)
                        }
                        HStack(alignment: .top, spacing: DT.Space.sm) {
                            Image(systemName: item.symbol)
                                .font(DT.Typography.subheadlineEmphasized)
                                .foregroundStyle(DT.Palette.accentText)
                                .frame(width: DT.Size.iconBadge, height: DT.Size.iconBadge)
                                .background(DT.Palette.accent.opacity(0.14), in: Circle())
                            VStack(alignment: .leading, spacing: DT.Space.xxs) {
                                Text("„\(item.polish)”").font(DT.Typography.headline)
                                Text("„\(item.english)”").font(DT.Typography.footnote).foregroundStyle(DT.Palette.textSecondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(DT.Space.md)
                    }
                }
                .panel()

                SiriTipView(intent: NextDeadlineIntent())
                    .siriTipViewStyle(.automatic)

                VStack(alignment: .leading, spacing: DT.Space.sm) {
                    Text("PRZYCISK CZYNNOŚCI I CENTRUM STEROWANIA")
                        .font(DT.Typography.overline)
                        .kerning(DT.Size.hairline)
                        .foregroundStyle(DT.Palette.textSecondary)
                    tip("1.circle.fill", "Ustawienia › Przycisk czynności › Skrót › Terminek › Najbliższy termin. Jedno naciśnięcie i słyszysz, co się kończy.")
                    tip("2.circle.fill", "Na iOS 18 możesz też wybrać sterowanie „Skanuj dokument” albo „Dodaj dokument” (Przycisk czynności › Sterowanie).")
                    tip("3.circle.fill", "Te same przyciski dodasz w Centrum sterowania: przytrzymaj puste miejsce › Dodaj sterowanie › Terminek.")
                    tip("4.circle.fill", "Widżet „Najbliższy termin” dodasz na ekran główny i ekran blokady.")
                }
                .padding(DT.Space.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .panel()

                Text("Skróty, które czytają dokumenty, działają tylko na odblokowanym iPhonie. Numery dokumentów i skany nie trafiają do Siri.")
                    .font(DT.Typography.footnote)
                    .foregroundStyle(DT.Palette.textTertiary)
            }
            .padding(DT.Space.gutter)
        }
        .background(AppBackground())
        .foregroundStyle(DT.Palette.textPrimary)
        .presentationDetents([.large])
    }

    private func tip(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: DT.Space.sm) {
            Image(systemName: symbol)
                .font(DT.Typography.headline)
                .foregroundStyle(DT.Palette.accentText)
            Text(text)
                .font(DT.Typography.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
