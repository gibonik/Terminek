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
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Kiedy i o czym")
                        .font(.brico(15, .medium, relativeTo: .subheadline))
                        .foregroundStyle(W.muted)
                    Text("Przypomnienia")
                        .font(.brico(40, .heavy, relativeTo: .largeTitle))
                        .tracking(-1.3)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .padding(.horizontal, 4)

                if status == .denied {
                    Button {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "bell.slash.fill").font(.system(size: 18, weight: .semibold))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Powiadomienia są wyłączone").font(.brico(16, .bold))
                                Text("Stuknij, żeby włączyć je w Ustawieniach iPhone'a.").font(.footnote).opacity(0.9)
                            }
                            Spacer()
                        }
                        .foregroundStyle(.white)
                        .padding(16)
                        .background(W.alert, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
                        Text("Godzina").font(.brico(16, .bold))
                        Spacer()
                        Picker("Godzina", selection: $reminderHour) {
                            ForEach(6..<23, id: \.self) { Text(verbatim: "\($0):00").tag($0) }
                        }
                        .labelsHidden()
                        .tint(W.gold)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 56)
                }
                .walletPanel()
                .riseIn(1)

                Button {
                    testSent += 1
                    let doc = documents.first { $0.daysLeft() >= 0 } ?? documents.first
                    Task { await NotificationScheduler.shared.sendTest(for: doc) }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "bell.badge.fill")
                            .symbolEffect(.bounce, value: testSent)
                        Text(testSent == 0 ? "Wyślij próbne powiadomienie" : "Wysłane, przyjdzie za 5 sekund")
                            .font(.brico(16, .bold))
                            .contentTransition(.opacity)
                    }
                    .foregroundStyle(W.gold)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .walletPanel(radius: 18)
                }
                .buttonStyle(CardPressStyle())
                .riseIn(2)

                WalletSectionTitle(text: "Najbliższe").riseIn(3)

                if upcoming.isEmpty {
                    Text(documents.isEmpty ? "Dodaj dokument, a tu pojawią się jego przypomnienia." : "Nie ma zaplanowanych przypomnień.")
                        .font(.brico(16, .medium))
                        .foregroundStyle(W.muted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, minHeight: 90)
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
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 120)
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
        Rectangle().fill(W.stroke).frame(height: 1).padding(.leading, 16)
    }

    private func toggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) { Text(title).font(.brico(16, .bold)) }
            .tint(W.gold)
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
    }
}

/// Punkt na osi: dzień i godzina po lewej, treść powiadomienia po prawej.
struct TimelineRow: View {
    let reminder: NotificationScheduler.PlannedReminder
    let document: Document?
    let isFirst: Bool
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Rectangle().fill(isFirst ? .clear : W.stroke).frame(width: 2, height: 18)
                Circle()
                    .fill(isFirst ? W.gold : (document?.group.color ?? W.cream))
                    .frame(width: 12, height: 12)
                    .overlay(Circle().strokeBorder(W.leather, lineWidth: 2))
                Rectangle().fill(isLast ? .clear : W.stroke).frame(width: 2).frame(maxHeight: .infinity)
            }
            .frame(width: 14)

            VStack(alignment: .leading, spacing: 6) {
                Text(PL.dayAndMonth(reminder.fireDate) + ", " + reminder.fireDate.formatted(.dateTime.hour().minute().locale(PL.locale)))
                    .font(.brico(13, .bold, relativeTo: .caption))
                    .foregroundStyle(isFirst ? W.gold : W.muted)
                HStack(spacing: 12) {
                    if let document { MiniCard(category: document.category) }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(reminder.title).font(.brico(16, .bold)).foregroundStyle(W.cream)
                        Text(reminder.body).font(.subheadline).foregroundStyle(W.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .walletPanel(radius: 18)
            }
            .padding(.top, 12)
            .padding(.bottom, 4)
        }
        .accessibilityElement(children: .combine)
    }
}
