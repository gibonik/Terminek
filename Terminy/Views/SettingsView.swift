import SwiftUI
import SwiftData
import UserNotifications

/// Motyw wybrany w ustawieniach (0 = jak w systemie).
enum AppAppearance: Int, CaseIterable, Identifiable {
    case system, light, dark
    static let key = "appearance"
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .system: "Auto"
        case .light: "Jasny"
        case .dark: "Ciemny"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

struct SettingsView: View {
    @Environment(AppLock.self) private var lock
    @Environment(\.openURL) private var openURL
    @Query private var documents: [Document]

    @AppStorage(NotificationScheduler.reminderHourKey) private var reminderHour = 9
    @AppStorage(NotificationScheduler.offsetKey(30)) private var remind30 = true
    @AppStorage(NotificationScheduler.offsetKey(7)) private var remind7 = true
    @AppStorage(NotificationScheduler.offsetKey(0)) private var remind0 = true
    @AppStorage(AppAppearance.key) private var appearance = AppAppearance.system.rawValue
    @State private var notificationsStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        @Bindable var lock = lock
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeader(title: "Ustawienia").riseIn(0)

                if notificationsStatus == .denied {
                    Button {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "bell.slash.fill").font(.system(size: 16, weight: .bold))
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Powiadomienia są wyłączone").font(.system(size: 14, weight: .heavy))
                                Text("Stuknij, żeby włączyć je w Ustawieniach iPhone'a")
                                    .font(.system(size: 12, weight: .semibold)).opacity(0.9)
                            }
                            Spacer()
                        }
                        .foregroundStyle(.white)
                        .padding(14)
                        .background(Palette.alert, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    .buttonStyle(PressScaleStyle())
                    .riseIn(1)
                }

                group(index: 1) {
                    toggleRow("Blokada \(lock.biometryName)", symbol: "faceid", color: Palette.urgentChip, isOn: $lock.isEnabled)
                }

                sectionTitle("Przypomnienia").riseIn(2)
                group(index: 2) {
                    toggleRow("30 dni przed terminem", symbol: "calendar", color: CategoryGroup.home.color, isOn: $remind30)
                    divider
                    toggleRow("7 dni przed terminem", symbol: "clock.fill", color: CategoryGroup.auto.color, isOn: $remind7)
                    divider
                    toggleRow("W dniu terminu", symbol: "exclamationmark", color: Palette.alert, isOn: $remind0)
                    divider
                    row("Godzina", symbol: "bell.fill", color: CategoryGroup.subscriptions.color) {
                        Picker("Godzina", selection: $reminderHour) {
                            ForEach(6..<23) { Text(String(format: "%d:00", $0)).tag($0) }
                        }
                        .labelsHidden()
                        .tint(Palette.ink)
                    }
                }

                sectionTitle("Wygląd").riseIn(3)
                group(index: 3) {
                    row("Motyw", symbol: "circle.lefthalf.filled", color: Color(hex: 0x6B7080)) {
                        Picker("Motyw", selection: $appearance) {
                            ForEach(AppAppearance.allCases) { Text($0.title).tag($0.rawValue) }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                    }
                }

                sectionTitle("Dane").riseIn(4)
                group(index: 4) {
                    row("Dokumentów", symbol: "doc.text.fill", color: CategoryGroup.personal.color) {
                        Text("\(documents.count)").font(.system(size: 15, weight: .heavy)).foregroundStyle(Palette.ink)
                    }
                    divider
                    row(TerminyApp.usesCloudKit ? "iCloud" : "Zapis", symbol: "icloud.fill", color: CategoryGroup.home.color) {
                        Text(TerminyApp.usesCloudKit ? "synchronizacja" : "tylko ten iPhone")
                            .font(.system(size: 14, weight: .bold)).foregroundStyle(Palette.muted)
                    }
                }

                Text(footer)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.muted)
                    .padding(.horizontal, 6)
                    .riseIn(5)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .scrollIndicators(.hidden)
        .tabBarClearance()
        .background(Palette.bg.ignoresSafeArea())
        .onChange(of: reminderSignature) {
            Task { await NotificationScheduler.shared.reschedule(documents) }
        }
        .task {
            notificationsStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        }
    }

    private var reminderSignature: String { "\(reminderHour)-\(remind30)-\(remind7)-\(remind0)" }

    private var footer: String {
        let storage = TerminyApp.usesCloudKit
            ? "Dane są w Twoim prywatnym iCloud i synchronizują się między urządzeniami."
            : "Dane są zapisane na tym iPhonie (aplikacja wgrana bez iCloud)."
        return "Przypomnienia przychodzą o \(reminderHour):00. " + storage
    }

    private var divider: some View {
        Rectangle().fill(Palette.line).frame(height: 1).padding(.leading, 44)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .heavy)).tracking(0.6)
            .foregroundStyle(Palette.muted)
            .padding(.horizontal, 6)
            .padding(.top, 4)
    }

    private func group<Content: View>(index: Int, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .background(Palette.panel, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .riseIn(index)
    }

    private func icon(_ symbol: String, _ color: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(color, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func toggleRow(_ title: String, symbol: String, color: Color, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            icon(symbol, color)
            Toggle(title, isOn: isOn)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Palette.ink)
                .tint(Palette.switchOn)
        }
        .frame(minHeight: 58)
    }

    private func row<Trailing: View>(_ title: String, symbol: String, color: Color,
                                     @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 12) {
            icon(symbol, color)
            Text(title).font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.ink)
            Spacer(minLength: 8)
            trailing()
        }
        .frame(minHeight: 58)
    }
}
