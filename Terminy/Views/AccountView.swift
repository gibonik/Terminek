import SwiftUI
import SwiftData
import UserNotifications

/// Konto: przypomnienia (kiedy i o czym), oś najbliższych powiadomień, wygląd i bezpieczeństwo.
struct AccountView: View {
    @Environment(AppLock.self) private var lock
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Document.expiryDate) private var documents: [Document]

    @AppStorage(NotificationScheduler.reminderHourKey) private var reminderHour = 9
    @AppStorage(NotificationScheduler.offsetKey(30)) private var remind30 = true
    @AppStorage(NotificationScheduler.offsetKey(7)) private var remind7 = true
    @AppStorage(NotificationScheduler.offsetKey(0)) private var remind0 = true
    @AppStorage(Haptics.enabledKey) private var haptics = true
    @AppStorage(AppAppearance.key) private var appearance = AppAppearance.system.rawValue
    @State private var status: UNAuthorizationStatus = .notDetermined
    @State private var testSent = 0
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

                Text("Terminek · wersja \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                    .font(DT.Typography.footnote)
                    .foregroundStyle(DT.Palette.textTertiary)
                    .frame(maxWidth: .infinity)
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
                Text(documents.count == 1 ? "1 dokument" : "\(documents.count) dokumentów")
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
        .background { LiveGradient(colors: [DT.Palette.accent, DT.Palette.accentAlt]) }
        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.panel, style: .continuous))
        .shadow(color: DT.Palette.accent.opacity(0.35), radius: DT.Space.lg, y: DT.Space.sm)
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
