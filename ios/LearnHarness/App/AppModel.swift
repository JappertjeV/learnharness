import Foundation
import Observation
import WebKit

/// Toestand van de app: welke server en of er een sessie is.
///
/// De app is een schil rond de echte LearnHarness-UI van de server: dezelfde code als de
/// Mac-app (Electron rond dezelfde web-UI). Zo zijn functies en uiterlijk gelijk. Native zijn
/// de login, de bijlagen (upload + pad, zoals de paperclip op de Mac) en de
/// aanpassingen voor het smalle buitenscherm van de iPhone Duo.
@MainActor @Observable
final class AppModel {
    static let sessionCookie = "lh_session"
    static let serverKey = "LHServerURL"

    /// De server die de gebruiker op het loginscherm koos. Standaard die uit de build
    /// (`LH_DEFAULT_SERVER` in Local.xcconfig), zodat een eigen build meteen naar de eigen server
    /// wijst; de openbare code bevat geen serveradres.
    private(set) var serverURL: URL?
    var state: State = .checking
    var loginError: String?

    enum State: Equatable { case checking, loggedOut, loggedIn }

    /// Lokale ontwikkelserver zonder login (alleen voor testen in de simulator):
    /// start met `-LHServerURL http://localhost:3917`.
    var isDevServer: Bool { serverURL.map(ServerAddress.isLocal) ?? false }

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.serverKey)
        let builtIn = Bundle.main.object(forInfoDictionaryKey: "LHDefaultServer") as? String
        serverURL = [saved, builtIn].compactMap { $0.flatMap(ServerAddress.normalize) }.first
    }

    /// Andere server kiezen: de sessie van de oude server gaat weg, want die geldt daar niet.
    func setServer(_ url: URL) async {
        for c in await store.allCookies() where c.name == Self.sessionCookie { await store.deleteCookie(c) }
        serverURL = url
        UserDefaults.standard.set(url.absoluteString, forKey: Self.serverKey)
        loginError = nil
        state = .loggedOut
    }

    var store: WKHTTPCookieStore { WKWebsiteDataStore.default().httpCookieStore }

    func checkSession() async {
        guard let host = serverURL?.host() else { state = .loggedOut; return }
        if isDevServer { state = .loggedIn; return }
        let cookies = await store.allCookies()
        let valid = cookies.contains { $0.name == Self.sessionCookie && $0.domain == host && ($0.expiresDate ?? .distantFuture) > .now }
        state = valid ? .loggedIn : .loggedOut
    }

    /// Zet het sessiecookie dat de server via `learnharness://login?session=…` teruggaf
    /// (/app-login op de server, zie server/README.md).
    func acceptLoginCallback(_ url: URL) async {
        guard let value = SessionCallback.sessionValue(from: url), let host = serverURL?.host() else {
            loginError = String(localized: "The server didn’t return a session. Please try again.")
            state = .loggedOut
            return
        }
        let props: [HTTPCookiePropertyKey: Any] = [
            .name: Self.sessionCookie,
            .value: value,
            .domain: host,
            .path: "/",
            .secure: "TRUE",
            // Authelia: inactiviteit 2 weken, maximaal 4 weken; de server blijft de waarheid.
            .expires: Date.now.addingTimeInterval(28 * 24 * 3600),
            HTTPCookiePropertyKey("HttpOnly"): "TRUE",
            .sameSitePolicy: HTTPCookieStringPolicy.sameSiteLax.rawValue,
        ]
        guard let cookie = HTTPCookie(properties: props) else {
            loginError = String(localized: "Couldn’t save the session.")
            state = .loggedOut
            return
        }
        await store.setCookie(cookie)
        loginError = nil
        state = .loggedIn
    }

    /// De server stuurde naar de loginpagina: sessie verlopen of ingetrokken.
    func sessionExpired() async {
        for c in await store.allCookies() where c.name == Self.sessionCookie { await store.deleteCookie(c) }
        state = .loggedOut
    }

    func logout() async { await sessionExpired() }
}

/// Uitlezen van de terugroep-URL; los van AppModel zodat het te testen is.
enum SessionCallback {
    static func sessionValue(from url: URL) -> String? {
        guard url.scheme == "learnharness", url.host() == "login" else { return nil }
        let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "session" }?.value
        // Authelia 4.39 maakt sessie-ID's van 32 tekens uit `randomSessionChars`: letters, cijfers
        // en `-_!#$%^*`. Eerst stonden alleen letters, cijfers, - en _ hier toe, waardoor een echte
        // sessie werd geweigerd (2026-11-18). De server percent-encodet; queryItems decodeert al.
        // Leeg = niet ingelogd (zie server/upload.py, /app-login).
        guard let value, value.count >= 20, value.allSatisfy({ ($0.isASCII && ($0.isLetter || $0.isNumber)) || "-_!#$%^*".contains($0) }) else { return nil }
        return value
    }
}

/// Serveradres zoals de gebruiker het intypt, teruggebracht tot `https://host[:poort]`.
/// Alleen https: de sessie gaat als cookie mee. Uitzondering: localhost voor de testserver.
enum ServerAddress {
    static func normalize(_ input: String) -> URL? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        guard let parts = URLComponents(string: text), let scheme = parts.scheme?.lowercased(),
              let host = parts.host?.lowercased(), !host.isEmpty, !host.contains(" ") else { return nil }
        var clean = URLComponents()
        clean.host = host
        clean.port = parts.port
        switch scheme {
        case "https": clean.scheme = "https"
        case "http" where isLocalHost(host): clean.scheme = "http"
        default: return nil
        }
        return clean.url
    }

    static func isLocal(_ url: URL) -> Bool { isLocalHost(url.host() ?? "") }
    private static func isLocalHost(_ host: String) -> Bool { host == "localhost" || host == "127.0.0.1" }
}
