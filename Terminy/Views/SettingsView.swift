import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(AppLock.self) private var lock
    @Query private var documents: [Document]

    var body: some View {
        @Bindable var lock = lock
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Ustawienia")
                    .font(.brico(44, .heavy, relativeTo: .largeTitle))
                    .tracking(-1.5)
                    .padding(.horizontal, 4)

                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: $lock.isEnabled) {
                        row("faceid", "Zamek \(lock.biometryName)")
                    }
                    .tint(W.gold)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 60)
                    .walletPanel()
                    Text("Portfel zamknie się, gdy wyjdziesz z aplikacji.")
                        .font(.footnote)
                        .foregroundStyle(W.muted)
                        .padding(.horizontal, 6)
                }
                .riseIn(0)

                VStack(alignment: .leading, spacing: 8) {
                    VStack(spacing: 0) {
                        HStack {
                            row("wallet.pass", "W portfelu")
                            Spacer()
                            Text(documents.count == 1 ? "1 dokument" : "\(documents.count) dokumentów")
                                .font(.brico(16, .bold))
                                .foregroundStyle(W.muted)
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 60)
                        Rectangle().fill(W.stroke).frame(height: 1).padding(.leading, 56)
                        HStack {
                            row(TerminyApp.usesCloudKit ? "icloud" : "iphone", "Zapis")
                            Spacer()
                            Text(TerminyApp.usesCloudKit ? "iCloud" : "Tylko ten iPhone")
                                .font(.brico(16, .bold))
                                .foregroundStyle(W.muted)
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 60)
                    }
                    .walletPanel()
                    Text(TerminyApp.usesCloudKit
                         ? "Dokumenty są w Twoim prywatnym iCloud i synchronizują się między urządzeniami."
                         : "Dokumenty są zapisane tylko na tym iPhonie, bo aplikacja jest wgrana bez iCloud.")
                        .font(.footnote)
                        .foregroundStyle(W.muted)
                        .padding(.horizontal, 6)
                }
                .riseIn(1)

                VStack(spacing: 6) {
                    Image(systemName: "wallet.pass.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(W.gold)
                    Text("Terminy").font(.brico(17, .bold))
                    Text("Wersja \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                        .font(.footnote)
                        .foregroundStyle(W.muted)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
                .riseIn(2)
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
    }

    private func row(_ symbol: String, _ title: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(W.gold)
                .frame(width: 26)
            Text(title).font(.brico(16, .bold)).foregroundStyle(W.cream)
        }
    }
}
