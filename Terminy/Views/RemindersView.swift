import SwiftUI
import SwiftData
import UserNotifications

/// Co i kiedy przypomnę: ustawienia przypomnień i oś najbliższych powiadomień.
struct RemindersView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Document.expiryDate) private var documents: [Document]

    @AppStorage(NotificationScheduler.reminderHourKey) private var reminderHour = 9
    @AppStorage(NotificationScheduler.offsetKey(30)) private var remind30 = true
    @AppStorage(NotificationScheduler.offsetKey(7)) private var remind7 = true
    @AppStorage(NotificationScheduler.offsetKey(0)) private var remind0 = true
    @State private var status: UNAuthorizationStatus = .notDetermined
    @State private var testSent = 0

    private var upcoming: [NotificationScheduler.PlannedReminder] {
        Array(NotificationScheduler.plannedReminders(
            for: documents, hour: reminderHour, now: .now,
            offsets: NotificationScheduler.enabledOffsets()
        ).prefix(20))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DT.Space.gutter) {
                VStack(alignment: .leading, spacing: DT.Space.xxs) {
                    Text("Kiedy i o czym")
                        .font(DT.Typography.subheadline)
                        .foregroundStyle(DT.Palette.textSecondary)
                    Text("Przypomnienia")
                        .font(DT.Typography.largeTitle)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .padding(.horizontal, DT.Space.xxs)

                if status == .denied {
                    Button {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                    } label: {
                        HStack(spacing: DT.Space.sm) {
                            Image(systemName: "bell.slash.fill").font(DT.Typography.icon)
                            VStack(alignment: .leading, spacing: DT.Space.xxs) {
                                Text("Powiadomienia są wyłączone").font(DT.Typography.headline)
                                Text("Stuknij, żeby włączyć je w Ustawieniach iPhone'a.").font(DT.Typography.footnote).opacity(0.9)
                            }
                            Spacer()
                        }
                        .foregroundStyle(DT.Palette.onDanger)
                        .padding(DT.Space.md)
                        .background(DT.Palette.dangerFill, in: RoundedRectangle(cornerRadius: DT.Radius.panel, style: .continuous))
                    }
                    .buttonStyle(CardPressStyle())
                    .riseIn(0)
                }

                VStack(spacing: 0) {
                    toggle("Miesiąc przed terminem", isOn: $remind30)
                    divider
                    toggle("Tydzień przed terminem", isOn: $remind7)
                    divider
                    toggle("W dniu terminu", isOn: $remind0)
                    divider
                    HStack {
                        Text("Godzina").font(DT.Typography.headline)
                        Spacer()
                        Picker("Godzina", selection: $reminderHour) {
                            ForEach(6..<23, id: \.self) { Text(verbatim: "\($0):00").tag($0) }
                        }
                        .labelsHidden()
                        .tint(DT.Palette.accent)
                    }
                    .padding(.horizontal, DT.Space.md)
                    .frame(minHeight: DT.Size.row)
                }
                .walletPanel()
                .riseIn(1)

                Button {
                    testSent += 1
                    let doc = documents.first { $0.daysLeft() >= 0 } ?? documents.first
                    Task { await NotificationScheduler.shared.sendTest(for: doc) }
                } label: {
                    HStack(spacing: DT.Space.sm) {
                        Image(systemName: "bell.badge.fill")
                            .symbolEffect(.bounce, value: testSent)
                        Text(testSent == 0 ? "Wyślij próbne powiadomienie" : "Wysłane, przyjdzie za 5 sekund")
                            .font(DT.Typography.headline)
                            .contentTransition(.opacity)
                    }
                    .foregroundStyle(DT.Palette.accentText)
                    .frame(maxWidth: .infinity, minHeight: DT.Size.row)
                    .walletPanel()
                }
                .buttonStyle(CardPressStyle())
                .riseIn(2)

                WalletSectionTitle(text: "Najbliższe").riseIn(3)

                if upcoming.isEmpty {
                    Text(documents.isEmpty ? "Dodaj dokument, a tu pojawią się jego przypomnienia." : "Nie ma zaplanowanych przypomnień.")
                        .font(DT.Typography.body)
                        .foregroundStyle(DT.Palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, minHeight: DT.Size.tile)
                        .walletPanel()
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(upcoming.enumerated()), id: \.element.identifier) { index, reminder in
                            TimelineRow(reminder: reminder,
                                        document: documents.first { $0.id == reminder.documentID },
                                        isFirst: index == 0,
                                        isLast: index == upcoming.count - 1)
                                .riseIn(4 + min(index, 8))
                        }
                    }
                }
            }
            .padding(.horizontal, DT.Space.gutter)
            .padding(.top, DT.Space.xs)
            .padding(.bottom, DT.Space.dockClearance)
        }
        .scrollIndicators(.hidden)
        .onChange(of: "\(reminderHour)-\(remind30)-\(remind7)-\(remind0)") {
            Task { await NotificationScheduler.shared.reschedule(documents) }
        }
        .task(id: scenePhase) {
            status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        }
    }

    private var divider: some View {
        Rectangle().fill(DT.Palette.separator).frame(height: DT.Size.hairline).padding(.leading, DT.Space.md)
    }

    private func toggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) { Text(title).font(DT.Typography.headline) }
            .tint(DT.Palette.accent)
            .padding(.horizontal, DT.Space.md)
            .frame(minHeight: DT.Size.row)
    }
}

/// Punkt na osi: dzień i godzina po lewej, treść powiadomienia po prawej.
struct TimelineRow: View {
    let reminder: NotificationScheduler.PlannedReminder
    let document: Document?
    let isFirst: Bool
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: DT.Space.md) {
            VStack(spacing: 0) {
                Rectangle().fill(isFirst ? .clear : DT.Palette.separator).frame(width: DT.Size.hairline * 2, height: DT.Space.gutter)
                Circle()
                    .fill(isFirst ? DT.Palette.accent : (document?.group.color ?? DT.Palette.textPrimary))
                    .frame(width: DT.Size.timelineDot, height: DT.Size.timelineDot)
                    .overlay(Circle().strokeBorder(DT.Palette.background, lineWidth: DT.Size.hairline * 2))
                Rectangle().fill(isLast ? .clear : DT.Palette.separator).frame(width: DT.Size.hairline * 2).frame(maxHeight: .infinity)
            }
            .frame(width: DT.Size.timelineDot + DT.Space.xxs)

            VStack(alignment: .leading, spacing: DT.Space.xs) {
                Text(PL.dayAndMonth(reminder.fireDate) + ", " + reminder.fireDate.formatted(.dateTime.hour().minute().locale(PL.locale)))
                    .font(DT.Typography.footnoteEmphasized)
                    .foregroundStyle(isFirst ? DT.Palette.accent : DT.Palette.textSecondary)
                HStack(spacing: DT.Space.sm) {
                    if let document { MiniCard(category: document.category) }
                    VStack(alignment: .leading, spacing: DT.Space.xxs) {
                        Text(reminder.title).font(DT.Typography.headline).foregroundStyle(DT.Palette.textPrimary)
                        Text(reminder.body).font(DT.Typography.subheadline).foregroundStyle(DT.Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(DT.Space.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .walletPanel()
            }
            .padding(.top, DT.Space.sm)
            .padding(.bottom, DT.Space.xxs)
        }
        .accessibilityElement(children: .combine)
    }
}
