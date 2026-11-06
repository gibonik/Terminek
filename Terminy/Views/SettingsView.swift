import SwiftUI
import SwiftData
import UserNotifications

struct SettingsView: View {
    @Environment(AppLock.self) private var lock
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Query private var documents: [Document]

    @AppStorage(NotificationScheduler.reminderHourKey) private var reminderHour = 9
    @State private var notificationsStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        @Bindable var lock = lock
        NavigationStack {
            Form {
                Section {
                    Toggle("Blokada \(lock.biometryName)", isOn: $lock.isEnabled)
                } footer: {
                    Text("Po wyjściu z aplikacji dokumenty zostaną zasłonięte do czasu odblokowania.")
                }

                Section {
                    Picker("Godzina przypomnień", selection: $reminderHour) {
                        ForEach(6..<23) { Text(String(format: "%02d:00", $0)).tag($0) }
                    }
                    .onChange(of: reminderHour) {
                        Task { await NotificationScheduler.shared.reschedule(documents) }
                    }
                    if notificationsStatus == .denied {
                        Button("Włącz powiadomienia w Ustawieniach") {
                            if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                        }
                    }
                } header: {
                    Text("Przypomnienia")
                } footer: {
                    Text("Przypominamy 30 dni, 7 dni przed terminem i w dniu terminu.")
                }

                Section {
                    LabeledContent("Dokumentów", value: "\(documents.count)")
                } header: {
                    Text("iCloud")
                } footer: {
                    Text("Dane trzymane są w Twojej prywatnej bazie iCloud i synchronizują się między Twoimi urządzeniami.")
                }
            }
            .navigationTitle("Ustawienia")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Gotowe") { dismiss() } }
            .task {
                notificationsStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            }
        }
    }
}
