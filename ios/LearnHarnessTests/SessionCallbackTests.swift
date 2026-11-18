import XCTest
@testable import LearnHarness

/// De terugroep-URL van de server (/app-login) mag alleen een echte sessie opleveren.
final class SessionCallbackTests: XCTestCase {
    func testAcceptsSessionFromServer() {
        let url = URL(string: "learnharness://login?session=AbCdEfGhIjKlMnOpQrStUvWxYz012345")!
        XCTAssertEqual(SessionCallback.sessionValue(from: url), "AbCdEfGhIjKlMnOpQrStUvWxYz012345")
    }

    func testAcceptsAutheliaSpecialCharacters() {
        // Authelia 4.39 gebruikt ook `-_!#$%^*`; upload.py percent-encodet ze (zelfde uitvoer als
        // de lokale test van upload.py). Dit faalde eerst: de app weigerde de echte sessie.
        let url = URL(string: "learnharness://login?session=aB3%23x%259%21%5E%2A%24-_Zq0aB3%23x%259%21%5E%2A%24-_Zq0")!
        XCTAssertEqual(SessionCallback.sessionValue(from: url), "aB3#x%9!^*$-_Zq0aB3#x%9!^*$-_Zq0")
    }

    func testRejectsEmptySession() {
        // Zo zag het eruit toen Caddy `redir` vóór `forward_auth` uitvoerde (zonder login).
        XCTAssertNil(SessionCallback.sessionValue(from: URL(string: "learnharness://login/?session=")!))
        XCTAssertNil(SessionCallback.sessionValue(from: URL(string: "learnharness://login")!))
    }

    func testRejectsOtherSchemesAndOddValues() {
        XCTAssertNil(SessionCallback.sessionValue(from: URL(string: "https://login?session=AbCdEfGhIjKlMnOpQrStUvWxYz012345")!))
        XCTAssertNil(SessionCallback.sessionValue(from: URL(string: "learnharness://other?session=AbCdEfGhIjKlMnOpQrStUvWxYz012345")!))
        XCTAssertNil(SessionCallback.sessionValue(from: URL(string: "learnharness://login?session=abc%3Bdomain%3Devil.example0000000")!))
    }
}

/// Het `accept`-attribuut bepaalt welke bronnen de kiezer toont.
final class AcceptTypesTests: XCTestCase {
    func testImagesOfferPhotosAndCamera() {
        let (types, images) = AttachmentPicker.types(for: "image/*")
        XCTAssertTrue(images)
        XCTAssertEqual(types, [.image])
    }

    func testDocumentsOnly() {
        let (types, images) = AttachmentPicker.types(for: ".md,.txt,.pdf")
        XCTAssertFalse(images)
        XCTAssertTrue(types.contains(.pdf))
    }

    func testNoAcceptMeansEverything() {
        let (types, images) = AttachmentPicker.types(for: "")
        XCTAssertTrue(images)
        XCTAssertEqual(types, [.item])
    }
}

/// UploadName.safe moet precies hetzelfde geven als safeName in bridge.js (de verwachte waarden
/// komen uit de JS-versie), en alles moet door NAME_RE van upload.py.
final class UploadNameTests: XCTestCase {
    let cases: [(String, String)] = [
        ("Foto 1.HEIC", "Foto 1.HEIC"), ("été/../../etc/passwd", "passwd"), ("..hidden", "bijlage.hidden"),
        ("rapport (v2).pdf", "rapport (v2).pdf"), ("😀.png", "bijlage.png"), ("", "bijlage"),
        (String(repeating: "a", count: 300) + ".txt", String(repeating: "a", count: 80) + ".txt"),
        ("x...y..z", "x.y.z"), ("C:\\temp\\a.pdf", "a.pdf"), ("noext.", "noext"), ("a/b/c.tar.gz", "c.tar.gz"),
        ("Notities 2026", "Notities 2026"), ("v1.2", "v1.2"), ("café menu.pdf", "cafe- menu.pdf"),
        ("a/", "bijlage"), ("Ünïcödé.md", "U-ni-co-de-.md"),
    ]

    func testMatchesBridgeJS() {
        for (input, expected) in cases {
            XCTAssertEqual(UploadName.safe(input), expected, "invoer: \(input)")
        }
    }

    func testPassesServerNameRule() throws {
        let nameRE = try NSRegularExpression(pattern: "^[A-Za-z0-9][A-Za-z0-9._ ()+-]{0,180}$")
        for (input, _) in cases {
            let out = UploadName.unique(input)
            XCTAssertNotNil(nameRE.firstMatch(in: out, range: NSRange(out.startIndex..., in: out)), out)
            XCTAssertFalse(out.contains("..") || out.contains("/"), out)
        }
    }

    func testFolderScanSkipsHiddenAndKeepsStructure() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "scan-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default
        try fm.createDirectory(at: root.appending(path: "sub/diep"), withIntermediateDirectories: true)
        try Data("a".utf8).write(to: root.appending(path: "a.md"))
        try Data("b".utf8).write(to: root.appending(path: "sub/diep/b é.txt"))
        try Data("x".utf8).write(to: root.appending(path: ".DS_Store"))
        let scan = FolderScan.scan(root)
        XCTAssertEqual(Set(scan.items.map { $0.parts.joined(separator: "/") }), ["a.md", "sub/diep/b e-.txt"])
        XCTAssertEqual(scan.total, 2)
    }
}

/// Het serveradres van het loginscherm: alleen https (behalve localhost), zonder pad.
final class ServerAddressTests: XCTestCase {
    func testAddsHttpsAndDropsPath() {
        XCTAssertEqual(ServerAddress.normalize("  Learn.Example.com/auth/?x=1 ")?.absoluteString, "https://learn.example.com")
        XCTAssertEqual(ServerAddress.normalize("https://learn.example.com:8443/")?.absoluteString, "https://learn.example.com:8443")
    }

    func testHttpOnlyForLocalhost() {
        XCTAssertEqual(ServerAddress.normalize("http://localhost:3917")?.absoluteString, "http://localhost:3917")
        XCTAssertNil(ServerAddress.normalize("http://learn.example.com"))
        XCTAssertNil(ServerAddress.normalize("ftp://learn.example.com"))
    }

    func testRejectsEmptyAndJunk() {
        XCTAssertNil(ServerAddress.normalize(""))
        XCTAssertNil(ServerAddress.normalize("   "))
        XCTAssertNil(ServerAddress.normalize("https://"))
    }
}
