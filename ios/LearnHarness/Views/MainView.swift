import SwiftUI

/// Hoofdscherm volgens Apple's richtlijnen voor de iPhone Duo:
/// - NavigationSplitView: dicht (compacte breedte) één kolom — eerst de lijst, dan de les —,
///   open (gewone breedte) lijst en les naast elkaar, zoals Mail. De split view houdt zelf
///   rekening met de vouw en de camera (reserved regions).
/// - Standaard systeem-toolbars met titel én symbool; op de Duo zet het systeem ze aan de zijkant.
///   "Nieuwe les" krijgt de hoogste prioriteit, de rest gaat naar het overloopmenu van het systeem.
/// - De les zelf is de LearnHarness-UI in één gedeelde WebView (WebStore), dus de toestand blijft
///   gelijk tussen beide schermen.
struct MainView: View {
    @Environment(AppModel.self) private var app
    @Bindable var store: WebStore

    enum Destination: Hashable { case home, chat(String) }
    enum Filter: String, CaseIterable, Identifiable {
        case all, teaching, practice
        var id: Self { self }
        var title: LocalizedStringKey {
            switch self {
            case .all: "All"
            case .teaching: "Lessons"
            case .practice: "Practice"
            }
        }
    }

    @State private var selection: Destination? = .home
    @State private var preferredColumn: NavigationSplitViewColumn = .sidebar
    @State private var filter: Filter = .all
    @State private var search = ""
    @State private var renaming: WebStore.Chat?
    @State private var renameText = ""
    @State private var deleting: WebStore.Chat?
    @State private var message: String?

    private var theme: LHTheme { store.theme }

    private var visibleChats: [WebStore.Chat] {
        store.chats.filter { chat in
            switch filter {
            case .all: true
            case .teaching: !chat.isPractice
            case .practice: chat.isPractice
            }
        }
        .filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $preferredColumn) {
            sidebar
        } detail: {
            detail
        }
        .tint(theme.primary)
        .preferredColorScheme(theme.isDark ? .dark : .light)
        .onChange(of: selection) { _, new in navigate(to: new) }
        .onChange(of: store.path) { _, _ in syncSelectionFromPage() }
        .alert("Rename session", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Title", text: $renameText)
            Button("Save") {
                if let chat = renaming { Task { await store.rename(chat.id, to: renameText) } }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .confirmationDialog("Delete session?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible, presenting: deleting) { chat in
            Button("Delete, keep knowledge graph", role: .destructive) { Task { message = await store.delete(chat.id, keepGraph: true) } }
            Button("Delete with this session’s nodes", role: .destructive) { Task { message = await store.delete(chat.id, keepGraph: false) } }
        } message: { chat in
            Text("“\(chat.title)” will be permanently deleted. This can’t be undone.")
        }
        .alert("Something went wrong", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: { Text(message ?? "") }
    }

    // MARK: Lijst

    private var sidebar: some View {
        List(selection: $selection) {
            Section {
                NavigationLink(value: Destination.home) {
                    Label("Knowledge graph", systemImage: "point.3.connected.trianglepath.dotted")
                        .font(.lhUI(.body))
                }
            }
            .listRowBackground(rowBackground(.home))

            Section {
                ForEach(visibleChats) { chat in
                    NavigationLink(value: Destination.chat(chat.id)) {
                        SessionRow(chat: chat, theme: theme)
                    }
                    .listRowBackground(rowBackground(.chat(chat.id)))
                    .swipeActions(edge: .trailing) {
                        Button("Delete", systemImage: "trash", role: .destructive) { deleting = chat }
                        Button("Rename", systemImage: "pencil") { renameText = chat.title; renaming = chat }
                    }
                    .contextMenu { sessionActions(chat) }
                }
            } header: {
                Picker("Show", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .textCase(nil)
                .padding(.bottom, 4)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(theme.background)
        .searchable(text: $search, prompt: "Search sessions")
        .refreshable { await store.refreshChats() }
        .navigationTitle("LearnHarness")
        .overlay {
            if store.loadedOnce && store.chats.isEmpty {
                ContentUnavailableView("No sessions yet", systemImage: "graduationcap",
                                       description: Text("Start a lesson with New lesson."))
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("New lesson", systemImage: "book") { startNew(practice: false) }
                    Button("New practice session", systemImage: "dumbbell") { startNew(practice: true) }
                } label: {
                    Label("New lesson", systemImage: "square.and.pencil")
                } primaryAction: {
                    startNew(practice: false)
                }
            }
            .visibilityPriority(.high)

            ToolbarItemGroup(placement: .bottomBar) {
                Button("Background agents", systemImage: "waveform.path.ecg") { showDetail(); store.openBackgroundAgents() }
                Button("Settings", systemImage: "gearshape") { showDetail(); store.openSettings() }
            }

            ToolbarOverflowMenu {
                Button("Reload", systemImage: "arrow.clockwise") { store.reload() }
                // Zoom zoals ⌘+ / ⌘− / ⌘0 op de Mac; met een toetsenbord werken die toetsen hier ook.
                Section("Zoom") {
                    Button("Zoom In", systemImage: "plus.magnifyingglass") { store.zoomIn() }
                        .keyboardShortcut("+", modifiers: .command)
                        .disabled(!store.canZoomIn)
                    Button("Zoom Out", systemImage: "minus.magnifyingglass") { store.zoomOut() }
                        .keyboardShortcut("-", modifiers: .command)
                        .disabled(!store.canZoomOut)
                    Button("Actual Size (\(Int((store.zoom * 100).rounded()))%)", systemImage: "1.magnifyingglass") { store.resetZoom() }
                        .keyboardShortcut("0", modifiers: .command)
                }
                Button("Sign out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                    Task { await app.logout() }
                }
            }
        }
    }

    private func rowBackground(_ d: Destination) -> some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(selection == d ? theme.accent : Color.clear)
            .padding(.horizontal, 6)
    }

    // MARK: Les

    private var detail: some View {
        ZStack {
            theme.background.ignoresSafeArea()
            // Het toetsenbord regelt WKWebView zelf (visualViewport); als SwiftUI de view óók
            // kleiner maakt, bleef de invoerbalk na het sluiten van het toetsenbord te hoog staan.
            WebContainer(store: store)
                .ignoresSafeArea(.keyboard)
            if let err = store.loadError {
                ContentUnavailableView {
                    Label("Server unreachable", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(err)
                } actions: {
                    Button("Try again") { store.reload() }.buttonStyle(.glass)
                }
                .background(theme.background)
            }
        }
        .navigationTitle(detailTitle)
        .navigationSubtitle(detailSubtitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if store.currentChatId != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button("Plan", systemImage: "point.topleft.down.to.point.bottomright.curvepath") { store.openPlan() }
                        .disabled(!store.planAvailable)
                }
                ToolbarOverflowMenu {
                    if let chat = currentChat { sessionActions(chat) }
                }
            }
        }
    }

    /// Het sessiemenu van de Mac (sidebar.tsx): Rename, Export as Markdown…, Delete…, en de
    /// handmatige extractie naar de kennisgraaf. Oefensessies extraheren nooit (upstream).
    @ViewBuilder
    private func sessionActions(_ chat: WebStore.Chat) -> some View {
        Button("Rename", systemImage: "pencil") { renameText = chat.title; renaming = chat }
        Button("Export as Markdown…", systemImage: "square.and.arrow.up") { store.exportMarkdown(chat.id) }
        if !chat.isPractice {
            Button("Extract into knowledge graph", systemImage: "point.3.connected.trianglepath.dotted") {
                Task { message = await store.extract(chat.id) }
            }
        }
        Divider()
        Button("Delete…", systemImage: "trash", role: .destructive) { deleting = chat }
    }

    private var currentChat: WebStore.Chat? {
        guard let id = store.currentChatId else { return nil }
        return store.chats.first { $0.id == id }
    }

    private var detailTitle: String {
        if store.path.hasPrefix("/chat/new") { return store.path.contains("practice") ? String(localized: "New practice session") : String(localized: "New lesson") }
        if let chat = currentChat { return chat.title }
        return store.currentChatId == nil ? String(localized: "Knowledge graph") : ""
    }

    private var detailSubtitle: String {
        guard let chat = currentChat else { return "" }
        if chat.isPractice { return String(localized: "Practice") }
        return SessionRow.phaseLabel(chat.phase) ?? ""
    }

    // MARK: Navigatie

    private func navigate(to destination: Destination?) {
        switch destination {
        case .home: store.openHome()
        case .chat(let id): store.openChat(id)
        case nil: break
        }
    }

    /// De pagina navigeert ook zelf (nieuwe sessie na de eerste vraag): lijst laten volgen.
    private func syncSelectionFromPage() {
        let fromPage: Destination? = store.currentChatId.map { .chat($0) } ?? (store.path == "/" ? .home : nil)
        if fromPage != selection { selection = fromPage }
        Task { await store.refreshChats() }
    }

    private func startNew(practice: Bool) {
        selection = nil
        store.newSession(practice: practice)
        showDetail()
    }

    /// Op het buitenscherm (één kolom) de les tonen; op het binnenscherm staat die er al.
    private func showDetail() { preferredColumn = .detail }
}

struct SessionRow: View {
    let chat: WebStore.Chat
    let theme: LHTheme

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(chat.title)
                    .font(.system(.body))
                    .foregroundStyle(theme.foreground)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if chat.isPractice { Image(systemName: "dumbbell").imageScale(.small) }
                    Text(meta)
                }
                .font(.lhUI(.caption))
                .foregroundStyle(theme.muted)
            }
            Spacer(minLength: 0)
            if chat.busy == true { ProgressView().controlSize(.small) }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var meta: String {
        var parts: [String] = []
        if chat.pendingQuestion == true || chat.pendingProblem == true { parts.append(String(localized: "Waiting for you")) }
        else if let p = Self.phaseLabel(chat.phase) { parts.append(p) }
        if let d = chat.updated { parts.append(d.formatted(.relative(presentation: .named))) }
        return parts.joined(separator: " · ")
    }

    static func phaseLabel(_ phase: String?) -> String? {
        switch phase {
        case "probe": String(localized: "Probing")
        case "plan": String(localized: "Planning")
        case "teach": String(localized: "Teaching")
        default: nil
        }
    }
}
