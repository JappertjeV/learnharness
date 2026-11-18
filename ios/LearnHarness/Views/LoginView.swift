import AuthenticationServices
import SwiftUI

/// Inloggen via de Safari-inlog van iOS (`ASWebAuthenticationSession`), met de login van de
/// server (Authelia in het voorbeeld). Zo vult Wachtwoorden het in, en het werkt ook met
/// passkeys, die een gewone WebView zonder associated domains niet kan. De server stuurt na het
/// inloggen terug naar `learnharness://login?session=…` (/app-login, zie server/README.md).
/// Zonder gekozen server (of na "Change server") vraagt dit scherm eerst het serveradres.
struct LoginView: View {
    @Environment(AppModel.self) private var model
    @State private var busy = false
    @State private var session: ASWebAuthenticationSession?
    @State private var anchor = WindowAnchor()
    @State private var editingServer = false
    @State private var serverText = ""
    @FocusState private var serverFocused: Bool

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Image("Logo")
                .resizable()
                .interpolation(.high)
                .frame(width: 96, height: 96)
                .clipShape(.rect(cornerRadius: 22))
            VStack(spacing: 8) {
                Text("LearnHarness")
                    .font(.system(size: 34, weight: .regular, design: .serif))
                    .foregroundStyle(Color.lhForeground)
                Text("An agent harness for learning.")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(Color.lhMuted)
            }
            if editingServer || model.serverURL == nil {
                serverForm
            } else {
                Button(action: start) {
                    primaryLabel("Sign in", systemImage: "person.crop.circle")
                }
                .disabled(busy)
            }
            if let err = model.loginError {
                Text(err)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            if let host = model.serverURL?.host(), !editingServer {
                Button {
                    serverText = model.serverURL?.absoluteString ?? ""
                    editingServer = true
                } label: {
                    Text(host).underline()
                }
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Color.lhMuted)
                .accessibilityLabel(Text("Change server"))
                .accessibilityValue(Text(host))
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.lhBackground)
        .background(WindowReader(anchor: anchor))
    }

    private var serverForm: some View {
        VStack(spacing: 14) {
            TextField("Server address", text: $serverText, prompt: Text(verbatim: "learn.example.com"))
                .textContentType(.URL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($serverFocused)
                .submitLabel(.continue)
                .onSubmit(saveServer)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(Color.lhForeground)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.lhForeground.opacity(0.08), in: .rect(cornerRadius: 10))
                .frame(maxWidth: 360)
            Button(action: saveServer) {
                primaryLabel("Continue", systemImage: "arrow.right")
            }
            .disabled(serverText.trimmingCharacters(in: .whitespaces).isEmpty)
            if model.serverURL != nil {
                Button("Cancel") { editingServer = false; model.loginError = nil }
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(Color.lhMuted)
            }
        }
        .onAppear { serverFocused = model.serverURL == nil }
    }

    private func primaryLabel(_ title: LocalizedStringKey, systemImage: String) -> some View {
        HStack(spacing: 10) {
            if busy { ProgressView().tint(Color.lhBackground) } else { Image(systemName: systemImage) }
            Text(title)
        }
        .font(.system(.body, design: .monospaced).weight(.medium))
        .foregroundStyle(Color.lhBackground)
        .padding(.horizontal, 22)
        .padding(.vertical, 13)
        .background(Color.lhForeground, in: .rect(cornerRadius: 10))
    }

    private func saveServer() {
        guard let url = ServerAddress.normalize(serverText) else {
            model.loginError = String(localized: "Enter a secure (https) server address, such as learn.example.com.")
            return
        }
        Task {
            await model.setServer(url)
            editingServer = false
        }
    }

    private func start() {
        guard anchor.window != nil else { model.loginError = String(localized: "Couldn’t start signing in."); return }
        guard let server = model.serverURL else { editingServer = true; return }
        busy = true
        model.loginError = nil
        let url = server.appending(path: "app-login")
        let s = ASWebAuthenticationSession(url: url, callback: .customScheme("learnharness")) { callback, error in
            Task { @MainActor in
                busy = false
                if let callback { await model.acceptLoginCallback(callback) }
                else if let e = error as? ASWebAuthenticationSessionError, e.code == .canceledLogin { /* zelf geannuleerd */ }
                else if let error { model.loginError = error.localizedDescription }
            }
        }
        // Safari-sessie hergebruiken: wie al in Safari is ingelogd, hoeft niet opnieuw.
        s.prefersEphemeralWebBrowserSession = false
        s.presentationContextProvider = anchor
        session = s
        if !s.start() { busy = false; model.loginError = String(localized: "Couldn’t start signing in.") }
    }
}

/// Het venster waarin het inlogvenster verschijnt (ook goed op de Duo met twee schermen).
final class WindowAnchor: NSObject, ASWebAuthenticationPresentationContextProviding {
    weak var window: UIWindow?
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // Het venster van het loginscherm zelf (WindowReader); start() begint pas als dat er is.
        window!
    }
}

private struct WindowReader: UIViewRepresentable {
    let anchor: WindowAnchor
    func makeUIView(context: Context) -> UIView { Probe(anchor: anchor) }
    func updateUIView(_ uiView: UIView, context: Context) {}

    final class Probe: UIView {
        let anchor: WindowAnchor
        init(anchor: WindowAnchor) { self.anchor = anchor; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError() }
        override func didMoveToWindow() { super.didMoveToWindow(); anchor.window = window }
    }
}
