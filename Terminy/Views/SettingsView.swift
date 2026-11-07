import SwiftUI
import SwiftData
import UserNotifications

struct SettingsView: View {
    @Environment(AppLock.self) private var lock
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Query private var documents: [Document]

    @AppStorage(NotificationScheduler.reminderHourKey) private var reminderHour = 9
    @AppStorage(NotificationScheduler.offsetKey(30)) private var remind30 = true
    @AppStorage(NotificationScheduler.offsetKey(7)) private var remind7 = true
    @AppStorage(NotificationScheduler.offsetKey(0)) private var remind0 = true
    @AppStorage(AppAppearance.key) private var appearance = AppAppearance.system.rawValue
    @State private var notificationsStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        @Bindable var lock = lock
        NavigationStack {
            Form {
                if notificationsStatus == .denied {
                    Section {
                        Button {
                            if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                        } label: {
                            Label("Włącz powiadomienia", systemImage: "bell.slash")
                        }
                    } footer: {
                        Text("Powiadomienia są wyłączone w Ustawieniach iPhone'a, więc przypomnienia nie przyjdą.")
                    }
                }

                Section {
                    Toggle("30 dni przed terminem", isOn: $remind30)
                    Toggle("Tydzień przed terminem", isOn: $remind7)
                    Toggle("W dniu terminu", isOn: $remind0)
                    Picker("Godzina", selection: $reminderHour) {
                        ForEach(6..<23, id: \.self) { Text("\($0):00").tag($0) }
                    }
                } header: {
                    Text("Przypomnienia")
                } footer: {
                    Text("Dotyczy wszystkich dokumentów z włączonymi przypomnieniami.")
                }

                Section {
                    Toggle("Blokada \(lock.biometryName)", isOn: $lock.isEnabled)
                } footer: {
                    Text("Terminy zablokują się, gdy wyjdziesz z aplikacji.")
                }

                Section("Wygląd") {
                    Picker("Motyw", selection: $appearance) {
                        ForEach(AppAppearance.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                }

                Section {
                    LabeledContent("Dokumenty", value: "\(documents.count)")
                    LabeledContent("Zapis", value: TerminyApp.usesCloudKit ? "iCloud" : "Tylko ten iPhone")
                } header: {
                    Text("Dane")
                } footer: {
                    Text(TerminyApp.usesCloudKit
                         ? "Dane są w Twoim prywatnym iCloud i synchronizują się między urządzeniami."
                         : "Dane są zapisane tylko na tym iPhonie, bo aplikacja jest wgrana bez iCloud.")
                }
            }
            .navigationTitle("Ustawienia")
        }
        .onChange(of: reminderSignature) {
            Task { await NotificationScheduler.shared.reschedule(documents) }
        }
        .task(id: scenePhase) {
            notificationsStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        }
    }

    private var reminderSignature: String { "\(reminderHour)-\(remind30)-\(remind7)-\(remind0)" }
}
