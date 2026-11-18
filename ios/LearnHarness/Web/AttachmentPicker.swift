import PhotosUI
import UIKit
import UniformTypeIdentifiers
import WebKit

/// Native bestandskiezer voor elk `<input type=file>` in de LearnHarness-UI.
///
/// Waarom: upstream opent zijn verborgen bestandsvelden met `input.click()` vanuit een menu
/// (paperclip, "Extract files…"). WKWebView op iOS toont daarop geen kiezer. bridge.js vangt die
/// `click()` af; de app toont Foto's / Camera / Bestanden (gefilterd op `accept`) en geeft de
/// bestanden terug aan precies dat veld (`__lhDeliverFiles`), waarna de pagina een gewone
/// `change` krijgt. De paperclip uploadt daarna zelf via `window.lh.getPathForFile`.
@MainActor
final class AttachmentPicker: NSObject, PHPickerViewControllerDelegate, UIDocumentPickerDelegate,
                              UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    /// Uploads gaan tot 50 MB (upload.py, Cloudflare tot 100 MB); groter heeft geen zin.
    static let maxBytes = 50 * 1024 * 1024

    private weak var web: WKWebView?
    private var requestId = ""
    private var multiple = true
    private var accept: [UTType] = [.item]
    private var pickingFolder = false
    private let presenter: () -> UIViewController?

    init(web: WKWebView, presenter: @escaping () -> UIViewController?) {
        self.web = web
        self.presenter = presenter
    }

    func start(requestId: String, multiple: Bool, directory: Bool = false, accept acceptAttribute: String, sourceRect: CGRect) {
        self.requestId = requestId
        self.multiple = multiple
        // `<input webkitdirectory>` (Extract files → Folder): een map kiezen, alle bestanden erin.
        if directory { folder(); return }
        let (types, acceptsImages) = Self.types(for: acceptAttribute)
        accept = types
        // Alleen documenten (bijv. graaf-import): geen menu met één keuze, meteen Bestanden.
        guard acceptsImages else { files(); return }
        guard let top = presenter() else { finish([]); return }
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        if acceptsImages {
            sheet.addAction(UIAlertAction(title: String(localized: "Photos"), style: .default) { _ in self.photos() })
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                sheet.addAction(UIAlertAction(title: String(localized: "Camera"), style: .default) { _ in self.camera() })
            }
        }
        sheet.addAction(UIAlertAction(title: String(localized: "Files"), style: .default) { _ in self.files() })
        sheet.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel) { _ in self.finish([]) })
        if let pop = sheet.popoverPresentationController, let web {
            pop.sourceView = web
            pop.sourceRect = sourceRect
        }
        top.present(sheet, animated: true)
    }

    /// `accept` ("image/*,.pdf,.md") → documenttypen, en of foto's/camera zin hebben.
    nonisolated static func types(for accept: String) -> ([UTType], Bool) {
        let parts = accept.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
        if parts.isEmpty { return ([.item], true) }
        var types: [UTType] = []
        var images = false
        for p in parts {
            if p.hasPrefix(".") {
                if let t = UTType(filenameExtension: String(p.dropFirst())) {
                    types.append(t)
                    if t.conforms(to: .image) { images = true }
                }
            } else if p.hasSuffix("/*") {
                let t: UTType = switch p {
                case "image/*": .image
                case "video/*": .movie
                case "audio/*": .audio
                case "text/*": .text
                default: .item
                }
                types.append(t)
                if t == .image { images = true }
            } else if let t = UTType(mimeType: p) {
                types.append(t)
                if t.conforms(to: .image) { images = true }
            }
        }
        return (types.isEmpty ? [.item] : types, images)
    }

    // MARK: Bronnen

    private func photos() {
        var cfg = PHPickerConfiguration(photoLibrary: .shared())
        cfg.selectionLimit = multiple ? 10 : 1
        cfg.filter = .images
        cfg.preferredAssetRepresentationMode = .compatible // HEIC → JPEG: leesbaar voor de agent
        let picker = PHPickerViewController(configuration: cfg)
        picker.delegate = self
        presenter()?.present(picker, animated: true)
    }

    private func camera() {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = self
        presenter()?.present(picker, animated: true)
    }

    private func files() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: accept, asCopy: true)
        picker.allowsMultipleSelection = multiple
        picker.delegate = self
        presenter()?.present(picker, animated: true)
    }

    nonisolated func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        // NSItemProvider is niet Sendable; we geven ze één keer door en gebruiken ze daarna alleen
        // op de main actor.
        nonisolated(unsafe) let providers = results.map(\.itemProvider)
        Task { @MainActor in
            picker.dismiss(animated: true)
            var files: [PickedFile] = []
            for provider in providers {
                let type = provider.registeredContentTypes.first { $0.conforms(to: .jpeg) || $0.conforms(to: .png) }
                    ?? provider.registeredContentTypes.first { $0.conforms(to: .image) } ?? .image
                if let data = await Self.load(provider: provider, type: type) {
                    let ext = type.preferredFilenameExtension ?? "jpg"
                    files.append(PickedFile(name: (provider.suggestedName ?? "photo") + "." + ext,
                                            mime: type.preferredMIMEType ?? "image/jpeg", data: data))
                }
            }
            self.finish(files)
        }
    }

    private static func load(provider: NSItemProvider, type: UTType) async -> Data? {
        await withCheckedContinuation { cont in
            _ = provider.loadDataRepresentation(for: type) { data, _ in cont.resume(returning: data) }
        }
    }

    nonisolated func imagePickerController(_ picker: UIImagePickerController,
                                           didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        let data = (info[.originalImage] as? UIImage)?.jpegData(compressionQuality: 0.85)
        Task { @MainActor in
            picker.dismiss(animated: true)
            self.finish(data.map { [PickedFile(name: "camera.jpg", mime: "image/jpeg", data: $0)] } ?? [])
        }
    }

    nonisolated func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        Task { @MainActor in picker.dismiss(animated: true); self.finish([]) }
    }

    private func folder() {
        pickingFolder = true
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.delegate = self
        presenter()?.present(picker, animated: true)
    }

    /// Alle bestanden van een map naar de pagina, zoals Chrome dat doet bij `webkitdirectory`.
    /// Via base64 naar de pagina, dus met een grens aan het totaal.
    private func deliverFolder(_ root: URL) {
        let scoped = root.startAccessingSecurityScopedResource()
        defer { if scoped { root.stopAccessingSecurityScopedResource() } }
        let scan = FolderScan.scan(root)
        guard scan.total <= 100 * 1024 * 1024, scan.items.count <= FolderScan.maxFiles else {
            finish([])
            alertTooBig(String(localized: "At most \(FolderScan.maxFiles) files and 100 MB per folder."))
            return
        }
        let files = scan.items.compactMap { item -> PickedFile? in
            guard let data = try? Data(contentsOf: item.url) else { return nil }
            let mime = UTType(filenameExtension: item.url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            return PickedFile(name: item.url.lastPathComponent, mime: mime, data: data)
        }
        finish(files)
    }

    private func alertTooBig(_ message: String) {
        guard let top = presenter() else { return }
        let a = UIAlertController(title: String(localized: "Folder too large"), message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
        top.present(a, animated: true)
    }

    nonisolated func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        Task { @MainActor in
            if self.pickingFolder {
                self.pickingFolder = false
                if let root = urls.first { self.deliverFolder(root) } else { self.finish([]) }
                return
            }
            var files: [PickedFile] = []
            for url in urls {
                guard let data = try? Data(contentsOf: url) else { continue }
                let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                files.append(PickedFile(name: url.lastPathComponent, mime: mime, data: data))
                try? FileManager.default.removeItem(at: url)
            }
            self.finish(files)
        }
    }

    nonisolated func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        Task { @MainActor in self.pickingFolder = false; self.finish([]) }
    }

    // MARK: Terug naar de pagina

    struct PickedFile { let name: String; let mime: String; let data: Data }

    private func finish(_ files: [PickedFile]) {
        let tooBig = files.filter { $0.data.count > Self.maxBytes }
        let ok = files.filter { $0.data.count <= Self.maxBytes }
        let payload: [[String: String]] = ok.map { ["name": $0.name, "type": $0.mime, "b64": $0.data.base64EncodedString()] }
        guard let data = try? JSONSerialization.data(withJSONObject: payload), let json = String(data: data, encoding: .utf8) else { return }
        let id = requestId.filter { $0.isLetter || $0.isNumber }
        web?.evaluateJavaScript("window.__lhDeliverFiles && window.__lhDeliverFiles(\"\(id)\", \(json));") { _, _ in }
        if !tooBig.isEmpty, let top = presenter() {
            let a = UIAlertController(title: String(localized: "File too large"),
                                      message: tooBig.map(\.name).joined(separator: "\n"), preferredStyle: .alert)
            a.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
            top.present(a, animated: true)
        }
    }
}
