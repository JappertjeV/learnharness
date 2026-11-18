import Foundation
import UIKit
import WebKit

/// Veilige naam voor upload.py (`NAME_RE`), precies als `safeName` in bridge.js: geen paden, geen
/// "..", alleen `A-Za-z0-9._ ()+-`, extensie hoogstens 12 tekens. Los van de UI zodat het te
/// testen is (LearnHarnessTests, met dezelfde gevallen als scripts/test-bridge.mjs).
enum UploadName {
    nonisolated static func safe(_ name: String) -> String {
        // Per Unicode-scalar, zoals JS: na NFKD is "é" een "e" plus een los accent, en dat accent
        // wordt "-". Een Swift-regex zou "é" als één teken in zijn geheel vervangen.
        func clean(_ s: String) -> String {
            let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._ ()+-")
            var out = String.UnicodeScalarView()
            var inRun = false
            for u in s.decomposedStringWithCompatibilityMapping.unicodeScalars {
                if allowed.contains(u) { out.append(u); inRun = false }
                else if !inRun { out.append("-"); inRun = true }
            }
            return String(out)
        }
        let plain = name.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? ""
        let dot = plain.lastIndex(of: ".")
        var ext = ""
        if let dot, dot > plain.startIndex {
            ext = "." + String(plain[plain.index(after: dot)...].filter { $0.isASCII && ($0.isLetter || $0.isNumber) }.prefix(12))
        }
        let stem = dot.map { $0 > plain.startIndex ? String(plain[..<$0]) : plain } ?? plain
        var base = clean(stem)
            .replacing(/\.{2,}/, with: ".")
            .replacing(/^[^A-Za-z0-9]+/, with: "")
        base = String(base.prefix(80))
        if base.isEmpty { base = "bijlage" }
        return (base + (ext.count > 1 ? ext : "")).replacing(/\.{2,}/, with: ".")
    }

    /// Zelfde voorvoegsel als bridge.js: tijdstempel + 4 willekeurige tekens, zodat niets botst.
    nonisolated static func unique(_ name: String, now: Date = .now) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        let rand = String((0..<4).map { _ in "abcdefghijklmnopqrstuvwxyz0123456789".randomElement()! })
        return "\(f.string(from: now))-\(rand)-\(safe(name))"
    }
}

/// Een gekozen map, platgeslagen tot bestanden met hun pad eronder.
struct FolderScan {
    struct Item { let url: URL; let parts: [String]; let size: Int }

    /// upload.py: hoogstens 8 delen diep, de map zelf is er één van.
    nonisolated static let maxDepth = 7
    nonisolated static let maxFiles = 500
    nonisolated static let maxFileBytes = 50 * 1024 * 1024   // = AttachmentPicker.maxBytes en upload.py
    nonisolated static let maxTotalBytes = 250 * 1024 * 1024

    var items: [Item] = []
    var skipped: [String] = []   // te diep of te groot
    var total: Int { items.reduce(0) { $0 + $1.size } }

    /// Verborgen bestanden (.DS_Store, .git) en de inhoud van pakketten slaat het over, zoals Finder.
    nonisolated static func scan(_ root: URL) -> FolderScan {
        var result = FolderScan()
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                                                          options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return result }
        let rootParts = root.standardizedFileURL.pathComponents
        for case let url as URL in walker {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            let rel = Array(url.standardizedFileURL.pathComponents.dropFirst(rootParts.count))
            let size = values.fileSize ?? 0
            if rel.isEmpty { continue }
            if rel.count > maxDepth || size > maxFileBytes {
                result.skipped.append(rel.joined(separator: "/"))
                continue
            }
            result.items.append(Item(url: url, parts: rel.map(UploadName.safe), size: size))
        }
        return result
    }
}

/// Paperclip → Folder: map kiezen, bestand voor bestand naar /app-upload/<map>/… sturen (met het
/// sessiecookie van de WebView), en de pagina het pad op de server geven. Dat is wat de Mac doet
/// met een map op de schijf: de agent leest de map daar.
@MainActor
final class FolderUploader: NSObject, UIDocumentPickerDelegate {
    private weak var web: WKWebView?
    private let presenter: () -> UIViewController?
    private var requestId = ""
    private var progress: UIAlertController?
    private var cancelled = false

    init(web: WKWebView, presenter: @escaping () -> UIViewController?) {
        self.web = web
        self.presenter = presenter
    }

    func start(requestId: String) {
        self.requestId = requestId.filter { $0.isLetter || $0.isNumber }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.delegate = self
        presenter()?.present(picker, animated: true)
    }

    nonisolated func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        Task { @MainActor in self.finish(nil) }
    }

    nonisolated func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        Task { @MainActor in
            guard let folder = urls.first else { self.finish(nil); return }
            await self.upload(folder)
        }
    }

    private func upload(_ folder: URL) async {
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        let scan = FolderScan.scan(folder)

        if scan.items.isEmpty {
            alert(String(localized: "Folder is empty"), String(localized: "There are no files in this folder to attach."))
            finish(nil); return
        }
        if scan.items.count > FolderScan.maxFiles || scan.total > FolderScan.maxTotalBytes {
            let msg = String(localized: "At most \(FolderScan.maxFiles) files and \(FolderScan.maxTotalBytes / 1024 / 1024) MB per folder. This folder has \(scan.items.count) files (\(scan.total / 1024 / 1024) MB).")
            alert(String(localized: "Folder too large"), msg)
            finish(nil); return
        }
        guard let base = uploadBase() else { finish(nil); return }

        let top = UploadName.unique(folder.lastPathComponent)
        let header = await cookieHeader(for: base)
        showProgress(0, of: scan.items.count)
        var failed: [String] = scan.skipped
        var done = 0
        for item in scan.items {
            if cancelled { break }
            let path = ([top] + item.parts).map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathSegmentAllowed) ?? $0 }.joined(separator: "/")
            guard let url = URL(string: "app-upload/" + path, relativeTo: base), let data = try? Data(contentsOf: item.url) else {
                failed.append(item.parts.joined(separator: "/")); continue
            }
            var req = URLRequest(url: url)
            req.httpMethod = "PUT"
            for (k, v) in header { req.setValue(v, forHTTPHeaderField: k) }
            let status = (try? await URLSession.shared.upload(for: req, from: data).1 as? HTTPURLResponse)?.statusCode ?? 0
            if status == 201 { done += 1 } else { failed.append(item.parts.joined(separator: "/") + " (HTTP \(status))") }
            showProgress(done, of: scan.items.count)
        }
        await dismissProgress()
        if cancelled { finish(nil); return }
        if !failed.isEmpty {
            alert(String(localized: "Some files weren’t attached"), failed.prefix(12).joined(separator: "\n") + (failed.count > 12 ? "\n…" : ""))
        }
        finish(done > 0 ? "/home/lh/Bijlagen/\(top)" : nil)
    }

    /// Oorsprong van de pagina (dus ook de lokale ontwikkelserver in de simulator).
    private func uploadBase() -> URL? {
        guard let page = web?.url, var c = URLComponents(url: page, resolvingAgainstBaseURL: false) else { return nil }
        c.path = "/"; c.query = nil; c.fragment = nil
        return c.url
    }

    private func cookieHeader(for url: URL) async -> [String: String] {
        let all = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
        let mine = all.filter { url.host()?.hasSuffix($0.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))) == true }
        return HTTPCookie.requestHeaderFields(with: mine)
    }

    private func showProgress(_ done: Int, of total: Int) {
        let text = String(localized: "Uploading \(done) of \(total)…")
        if let progress { progress.message = text; return }
        let a = UIAlertController(title: String(localized: "Attaching folder"), message: text, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel) { _ in self.cancelled = true; self.progress = nil })
        progress = a
        presenter()?.present(a, animated: true)
    }

    private func dismissProgress() async {
        guard let p = progress else { return }
        progress = nil
        await withCheckedContinuation { cont in p.dismiss(animated: true) { cont.resume() } }
    }

    private func alert(_ title: String, _ message: String) {
        let a = UIAlertController(title: title, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
        presenter()?.present(a, animated: true)
    }

    private func finish(_ path: String?) {
        let arg = path.flatMap { try? String(data: JSONSerialization.data(withJSONObject: [$0]), encoding: .utf8) }.map { String($0.dropFirst().dropLast()) } ?? "null"
        web?.evaluateJavaScript("window.__lhFolderChosen && window.__lhFolderChosen(\"\(requestId)\", \(arg));") { _, _ in }
    }
}

extension CharacterSet {
    /// Eén padsegment: alles wat in een pad mag, behalve "/".
    nonisolated static let urlPathSegmentAllowed: CharacterSet = {
        var s = CharacterSet.urlPathAllowed
        s.remove("/")
        return s
    }()
}
