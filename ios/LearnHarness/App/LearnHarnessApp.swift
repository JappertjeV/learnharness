import SwiftUI

@main
struct LearnHarnessApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var store: WebStore?

    var body: some View {
        ZStack {
            (store?.theme ?? .default).background.ignoresSafeArea()
            switch model.state {
            case .checking:
                ProgressView()
            case .loggedOut:
                LoginView()
                    .preferredColorScheme(.dark)
            case .loggedIn:
                if let store {
                    MainView(store: store)
                } else if let server = model.serverURL {
                    ProgressView()
                        .onAppear {
                            store = WebStore(serverURL: server) { Task { await model.sessionExpired() } }
                        }
                }
            }
        }
        .task { await model.checkSession() }
        .onChange(of: model.state) { _, state in
            // Na opnieuw inloggen een verse WebView, zodat de nieuwe sessie-cookie geldt.
            if state == .loggedOut { store = nil }
        }
    }
}

extension Color {
    // Loginscherm (vóór er een pagina is om het thema uit te lezen): standaard donker thema.
    static let lhBackground = LHTheme.default.background
    static let lhForeground = LHTheme.default.foreground
    static let lhMuted = LHTheme.default.muted
}
