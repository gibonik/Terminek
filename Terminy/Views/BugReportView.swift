import SwiftUI
import MessageUI

/// Co otworzyć w zgłoszeniu: rodzaj, zrzut ekranu (po potrząśnięciu) i raport awarii.
struct BugReportRequest: Identifiable {
    let id = UUID()
    var kind: BugReport.Kind = .bug
    var screenshot: UIImage?
    var crashReport: URL?
}

/// Pokazuje zgłoszenie nad tym, co jest otwarte (także nad szczegółami i edytorem).
@MainActor
enum BugReportPresenter {
    private(set) static var isShowing = false

    static func present(_ request: BugReportRequest) {
        guard !isShowing, let top = topController() else { return }
        isShowing = true
        let style = AppAppearance(rawValue: UserDefaults.standard.integer(forKey: AppAppearance.key))?.colorScheme
        weak var hostRef: UIViewController?
        let view = BugReportView(request: request) {
            hostRef?.dismiss(animated: true)
            isShowing = false
        }
        .tint(DT.Palette.accent)
        let host = UIHostingController(rootView: view)
        host.overrideUserInterfaceStyle = style == .dark ? .dark : style == .light ? .light : .unspecified
        host.presentationController?.delegate = DismissWatcher.shared
        hostRef = host
        top.present(host, animated: true)
    }

    fileprivate static func didDismiss() { isShowing = false }

    private static func topController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed { top = presented }
        return top
    }

    /// Zamknięcie arkusza przeciągnięciem w dół.
    private final class DismissWatcher: NSObject, UIAdaptivePresentationControllerDelegate {
        static let shared = DismissWatcher()
        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            MainActor.assumeIsolated { BugReportPresenter.didDismiss() }
        }
    }
}

/// Zgłoszenie błędu, pomysłu albo pytania. Wysyłka Pocztą (z załącznikami) albo dowolną aplikacją.
struct BugReportView: View {
    let request: BugReportRequest
    var onClose: () -> Void
    @State private var kind: BugReport.Kind
    @State private var message = ""
    @State private var includeDevice = true
    @State private var includeSteps = true
    @State private var includeScreenshot: Bool
    @State private var includeCrash: Bool
    @State private var deviceInfo = ""
    @State private var showingDetails = false
    @State private var mail: MailDraft?
    @State private var shareItems: ShareItems?
    @State private var sent = false
    @FocusState private var focused: Bool

    init(request: BugReportRequest, onClose: @escaping () -> Void) {
        self.request = request
        self.onClose = onClose
        _kind = State(initialValue: request.kind)
        // Zrzut może pokazywać dane dokumentów, więc domyślnie go nie dołączamy.
        _includeScreenshot = State(initialValue: false)
        _includeCrash = State(initialValue: request.crashReport != nil)
    }

    private var report: BugReport {
        BugReport(kind: kind, message: message, includeDevice: includeDevice, includeSteps: includeSteps,
                  screenshot: includeScreenshot ? request.screenshot : nil,
                  crashReport: includeCrash ? request.crashReport : nil)
    }

    private var canSend: Bool { !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Anuluj") { onClose() }
                    .font(DT.Typography.headline)
                    .foregroundStyle(DT.Palette.textSecondary)
                    .frame(minHeight: DT.Size.touch)
                Spacer()
                Text("Zgłoszenie").font(DT.Typography.headline)
                Spacer()
                Color.clear.frame(width: DT.Size.touch + DT.Space.md, height: DT.Size.touch)
            }
            .padding(.horizontal, DT.Space.gutter)
            .padding(.top, DT.Space.md)

            ScrollView {
                VStack(alignment: .leading, spacing: DT.Space.md) {
                    if request.crashReport != nil {
                        Label("Ostatnio aplikacja zamknęła się niespodziewanie. Raport pomoże to naprawić.",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(DT.Typography.subheadline)
                            .foregroundStyle(DT.Palette.warning)
                            .padding(DT.Space.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .panel()
                    }

                    kindPicker

                    VStack(alignment: .leading, spacing: DT.Space.xs) {
                        Text(kind.prompt).font(DT.Typography.subheadline).foregroundStyle(DT.Palette.textSecondary)
                        TextField("", text: $message, prompt: Text("Opisz to własnymi słowami").foregroundStyle(DT.Palette.textTertiary),
                                  axis: .vertical)
                            .lineLimit(5...12)
                            .font(DT.Typography.body)
                            .focused($focused)
                    }
                    .padding(DT.Space.md)
                    .panel()

                    if let screenshot = request.screenshot {
                        HStack(alignment: .top, spacing: DT.Space.sm) {
                            Image(uiImage: screenshot)
                                .resizable()
                                .scaledToFill()
                                .frame(width: DT.Size.tile * 0.6, height: DT.Size.tile * 1.2)
                                .clipShape(RoundedRectangle(cornerRadius: DT.Radius.sm, style: .continuous))
                                .blur(radius: includeScreenshot ? 0 : DT.Space.xxs)
                                .opacity(includeScreenshot ? 1 : 0.5)
                                .accessibilityHidden(true)
                            Toggle(isOn: $includeScreenshot) {
                                VStack(alignment: .leading, spacing: DT.Space.xxs) {
                                    Text("Dołącz zrzut ekranu").font(DT.Typography.body)
                                    Text("Sprawdź, czy nie widać na nim numerów dokumentów.")
                                        .font(DT.Typography.footnote)
                                        .foregroundStyle(DT.Palette.textSecondary)
                                }
                            }
                            .tint(DT.Palette.accent)
                        }
                        .padding(DT.Space.md)
                        .panel()
                        .animation(DT.Motion.standard, value: includeScreenshot)
                    }

                    VStack(spacing: 0) {
                        toggle("iphone", "Informacje o telefonie", "Wersja, model, system. Bez Twoich dokumentów.", isOn: $includeDevice)
                        divider
                        toggle("list.bullet.rectangle", "Ostatnie kroki w aplikacji", "Np. „skan: 2 strony”. Bez nazw i numerów.", isOn: $includeSteps)
                        if request.crashReport != nil {
                            divider
                            toggle("ladybug", "Raport awarii", "Techniczny zapis z chwili zamknięcia.", isOn: $includeCrash)
                        }
                    }
                    .panel()

                    Button {
                        withAnimation(DT.Motion.standard) { showingDetails.toggle() }
                    } label: {
                        Label(showingDetails ? "Ukryj, co wysyłam" : "Zobacz, co wysyłam", systemImage: "eye")
                            .font(DT.Typography.footnoteEmphasized)
                            .foregroundStyle(DT.Palette.accentText)
                            .frame(maxWidth: .infinity, minHeight: DT.Size.touch)
                    }
                    if showingDetails {
                        Text([includeDevice ? deviceInfo : "", includeSteps ? Breadcrumbs.read() : ""]
                            .filter { !$0.isEmpty }.joined(separator: "\n\n").ifEmpty("Tylko Twój opis."))
                            .font(DT.Typography.caption.monospaced())
                            .foregroundStyle(DT.Palette.textSecondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(DT.Space.md)
                            .panel()
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    Text("Zgłoszenie wyślesz sam, Pocztą albo inną aplikacją. Nic nie idzie automatycznie.")
                        .font(DT.Typography.footnote)
                        .foregroundStyle(DT.Palette.textTertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, DT.Space.gutter)
                .padding(.top, DT.Space.sm)
                .padding(.bottom, DT.Space.xxl)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: "Wyślij", symbol: "paperplane.fill") { send() }
                .disabled(!canSend)
                .opacity(canSend ? 1 : 0.5)
                .padding(.horizontal, DT.Space.gutter)
                .padding(.bottom, DT.Space.xs)
        }
        .background(AppBackground())
        .foregroundStyle(DT.Palette.textPrimary)
        .interactiveDismissDisabled(canSend)
        .task {
            deviceInfo = await BugReport.deviceInfo()
            focused = request.screenshot == nil && request.crashReport == nil
        }
        .sheet(item: $mail, onDismiss: finish) { draft in
            MailComposer(draft: draft) { sent = $0 }.ignoresSafeArea()
        }
        .sheet(item: $shareItems, onDismiss: finish) { items in
            ActivitySheet(items: items.items) { sent = $0 }.presentationDetents([.medium, .large])
        }
    }

    private var kindPicker: some View {
        HStack(spacing: DT.Space.xs) {
            ForEach(BugReport.Kind.allCases) { option in
                let isOn = kind == option
                Button {
                    withAnimation(DT.Motion.press) { kind = option }
                } label: {
                    Label(option.title, systemImage: option.symbol)
                        .font(DT.Typography.subheadlineEmphasized)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(isOn ? DT.Palette.onAccent : DT.Palette.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: DT.Size.pill)
                        .background(isOn ? DT.Palette.accent : DT.Palette.surfaceRaised, in: Capsule())
                }
                .buttonStyle(CardPressStyle())
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }

    private var divider: some View {
        Rectangle().fill(DT.Palette.separator).frame(height: DT.Size.hairline)
            .padding(.leading, DT.Space.md + DT.Size.iconBadge + DT.Space.sm)
    }

    private func toggle(_ symbol: String, _ title: String, _ detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: DT.Space.sm) {
                Image(systemName: symbol)
                    .font(DT.Typography.subheadlineEmphasized)
                    .foregroundStyle(DT.Palette.accentText)
                    .frame(width: DT.Size.iconBadge, height: DT.Size.iconBadge)
                    .background(DT.Palette.accent.opacity(0.14), in: Circle())
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(DT.Typography.body)
                    Text(detail).font(DT.Typography.footnote).foregroundStyle(DT.Palette.textSecondary)
                }
            }
        }
        .tint(DT.Palette.accent)
        .padding(.horizontal, DT.Space.md)
        .padding(.vertical, DT.Space.xs)
        .frame(minHeight: DT.Size.toggleRow)
    }

    private func send() {
        focused = false
        let report = report
        Breadcrumbs.add("Zgłoszenie: \(report.kind.title.lowercased())")
        Task {
            if MFMailComposeViewController.canSendMail() {
                mail = MailDraft(subject: report.subject, body: await report.body(), attachments: report.attachments())
            } else {
                shareItems = ShareItems(items: await report.shareItems())
            }
        }
    }

    /// Po wysłaniu zamykamy zgłoszenie; po anulowaniu wracamy do opisu, żeby nic nie przepadło.
    private func finish() {
        BugReport.cleanUpSharedFiles()
        if sent {
            Haptics.shared.fire(.renew)
            onClose()
        }
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}

struct MailDraft: Identifiable {
    let id = UUID()
    let subject: String
    let body: String
    let attachments: [(data: Data, mime: String, name: String)]
}

struct ShareItems: Identifiable {
    let id = UUID()
    let items: [Any]
}

/// Systemowe okno nowej wiadomości w Poczcie.
struct MailComposer: UIViewControllerRepresentable {
    let draft: MailDraft
    let onFinish: (Bool) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        if !BugReport.supportEmail.isEmpty { controller.setToRecipients([BugReport.supportEmail]) }
        controller.setSubject(draft.subject)
        controller.setMessageBody(draft.body, isHTML: false)
        for item in draft.attachments {
            controller.addAttachmentData(item.data, mimeType: item.mime, fileName: item.name)
        }
        return controller
    }

    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(dismiss: dismiss, onFinish: onFinish) }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let dismiss: DismissAction
        let onFinish: (Bool) -> Void
        init(dismiss: DismissAction, onFinish: @escaping (Bool) -> Void) {
            self.dismiss = dismiss
            self.onFinish = onFinish
        }

        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            onFinish(result == .sent || result == .saved)
            dismiss()
        }
    }
}

/// Arkusz „Udostępnij” (gdy nie ma skonfigurowanej Poczty).
struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]
    var onFinish: (Bool) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        let dismiss = dismiss
        let onFinish = onFinish
        controller.completionWithItemsHandler = { _, completed, _, _ in
            onFinish(completed)
            if completed { dismiss() }
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
