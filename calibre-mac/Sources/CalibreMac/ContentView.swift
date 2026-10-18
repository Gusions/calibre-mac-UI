import SwiftUI
import UniformTypeIdentifiers
import QuickLook

struct ContentView: View {
    private var store: LibraryStore { LibraryStore.shared }
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if !store.hasLibrary { WelcomeView() }
            else if let e = store.engine.error { ErrorView(message: e) }
            else if store.engine.starting || (store.loading && store.books.isEmpty) {
                VStack(spacing: 14) { ProgressView(); Text("Apro la libreria…").foregroundStyle(.secondary) }
            } else { LibraryWindow() }
        }
        .onAppear { store.openReader = { openWindow(id: "reader", value: $0) }; store.startDeviceMonitor() }
        .task {
            guard store.hasLibrary, !store.engine.ready, !store.engine.starting else { return }
            let env = ProcessInfo.processInfo.environment["CALIBREMAC_LIBRARY"]
            if let p = env ?? store.libraryPath { await store.openLibrary(p) }
        }
    }
}

struct LibraryWindow: View {
    private var store: LibraryStore { LibraryStore.shared }

    var body: some View {
        @Bindable var store = store
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 210, ideal: 250, max: 340)
        } detail: {
            MainArea()
                .inspector(isPresented: $store.showInspector) {
                    InspectorView().inspectorColumnWidth(min: 290, ideal: 330, max: 440)
                }
        }
        .navigationTitle(title)
        .navigationSubtitle("\(store.visible.count) di \(store.books.count) libri")
        .overlay(alignment: .bottom) { ToastView() }
    }

    private var title: String {
        if let s = store.sidebar.compactMap({ if case .smart(let s) = $0 { s } else { nil } }).first { return s.title }
        return "Calibre"
    }
}

struct MainArea: View {
    private var store: LibraryStore { LibraryStore.shared }
    @State private var showJobs = false
    @State private var saveName = ""
    @State private var showSave = false

    var body: some View {
        @Bindable var store = store
        Group {
            if store.books.isEmpty {
                ContentUnavailableView {
                    Label("La libreria è vuota", systemImage: "books.vertical")
                } description: { Text("Trascina qui dei libri o usa Aggiungi.") } actions: {
                    Button("Aggiungi libri…") { store.showImporter = true }.buttonStyle(.borderedProminent)
                }
            } else if store.visible.isEmpty {
                ContentUnavailableView.search(text: store.search)
            } else if store.viewMode == .list { BookTable() } else { BookGrid() }
        }
        .safeAreaInset(edge: .top, spacing: 0) { FilterBar() }
        .safeAreaInset(edge: .bottom, spacing: 0) { StatusBar() }
        .searchable(text: $store.search, placement: .toolbar, prompt: store.fullText ? "Cerca nel testo dei libri" : "Cerca titolo, autore, tag…")
        .searchScopes($store.fullText) {
            Text("Metadati").tag(false)
            Text("Testo completo").tag(true)
        }
        .task(id: store.search + (store.fullText ? "1" : "0")) { await store.runFTS() }
        .toolbar { toolbar }
        .fileImporter(isPresented: $store.showImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { r in
            if case .success(let urls) = r {
                let granted = urls.filter { $0.startAccessingSecurityScopedResource() }
                store.add(urls: granted)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in store.add(urls: urls.filter { $0.isFileURL }); return true }
        .confirmationDialog("Rimuovere \(store.selection.count) libri?", isPresented: $store.showDelete, titleVisibility: .visible) {
            Button("Rimuovi", role: .destructive) { store.remove(ids: Array(store.selection)) }
            Button("Annulla", role: .cancel) {}
        } message: { Text("I libri vengono spostati nel cestino di Calibre.") }
        .sheet(isPresented: $store.showEdit) { EditMetadataView() }
        .sheet(isPresented: $store.showConvert) { ConvertView() }
        .sheet(isPresented: $store.showNews) { NewsView() }
        .sheet(isPresented: $store.showSend) { SendToDeviceView() }
        .quickLookPreview($store.quickLook)
        .alert("Salva ricerca", isPresented: $showSave) {
            TextField("Nome", text: $saveName)
            Button("Salva") { store.saveCurrentSearch(name: saveName.isEmpty ? store.search : saveName); saveName = "" }
            Button("Annulla", role: .cancel) {}
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        @Bindable var store = store
        ToolbarItemGroup(placement: .navigation) {
            Button { store.showImporter = true } label: { Label("Aggiungi", systemImage: "plus") }
                .help("Aggiungi libri (⌘O)")
        }
        ToolbarItemGroup {
            Button { store.showEdit = true } label: { Label("Metadati", systemImage: "square.and.pencil") }
                .help("Modifica metadati (⌘E)").disabled(store.selection.isEmpty)
            Button { store.showConvert = true } label: { Label("Converti", systemImage: "arrow.triangle.2.circlepath") }
                .help("Converti formato").disabled(store.selection.isEmpty)
            Button { if let id = store.selection.first { store.openReader?(id) } } label: { Label("Leggi", systemImage: "book") }
                .help("Leggi (⌘↩)").disabled(store.selection.isEmpty)
        }
        ToolbarSpacer(.fixed)
        ToolbarItemGroup {
            Button { saveToDisk() } label: { Label("Salva su disco", systemImage: "square.and.arrow.down") }
                .help("Salva i file su disco").disabled(store.selection.isEmpty)
            Button { store.devices = DeviceScanner.scan(); store.showSend = true } label: { Label("Invia a e-reader", systemImage: "externaldrive") }
                .help("Invia a un Kindle, Kobo o altro lettore (⇧⌘D)").disabled(store.selection.isEmpty)
            if let b = store.selectedBooks.first, let p = b.bestPath {
                ShareLink(item: URL(fileURLWithPath: p)) { Label("Condividi", systemImage: "square.and.arrow.up") }
            }
            Button { store.showDelete = true } label: { Label("Rimuovi", systemImage: "trash") }
                .help("Rimuovi (⌘⌫)").disabled(store.selection.isEmpty)
        }
        ToolbarSpacer(.fixed)
        ToolbarItem {
            Picker("Vista", selection: $store.viewMode) {
                Label("Elenco", systemImage: "list.bullet").tag(ViewMode.list)
                Label("Griglia", systemImage: "square.grid.2x2").tag(ViewMode.grid)
            }.pickerStyle(.segmented)
        }
        ToolbarItem {
            Menu {
                Picker("Ordina per", selection: sortBinding) {
                    Text("Titolo").tag("title"); Text("Autore").tag("author"); Text("Data aggiunta").tag("added")
                    Text("Valutazione").tag("rating"); Text("Anno").tag("year")
                }
                Button(store.sortOrder.first?.order == .forward ? "Decrescente" : "Crescente") {
                    if var f = store.sortOrder.first { f.order = f.order == .forward ? .reverse : .forward; store.sortOrder = [f] }
                }
            } label: { Label("Ordina", systemImage: "arrow.up.arrow.down") }
        }
        ToolbarItem {
            Menu {
                Button("Scarica notizie…", systemImage: "newspaper") { store.showNews = true }
                Divider()
                Button("Rifinisci libri", systemImage: "sparkles") { store.polish(store.selectedBooks) }.disabled(store.selection.isEmpty)
                Button("Incorpora metadati", systemImage: "doc.badge.gearshape") { store.embedMetadata(store.selectedBooks) }.disabled(store.selection.isEmpty)
                Button("Segna / deseleziona", systemImage: "bookmark") { store.toggleMark(Array(store.selection)) }.disabled(store.selection.isEmpty)
                Button("Mostra nel Finder", systemImage: "folder") { store.revealInFinder(store.selectedBooks) }.disabled(store.selection.isEmpty)
                Divider()
                Button("Salva ricerca corrente…", systemImage: "magnifyingglass") { showSave = true }.disabled(store.search.isEmpty)
                Button("Libro a caso", systemImage: "dice") { store.randomBook() }
            } label: { Label("Altro", systemImage: "ellipsis.circle") }
        }
        ToolbarItem {
            Button { showJobs.toggle() } label: {
                Label("Lavori", systemImage: store.runningJobs > 0 ? "arrow.trianglehead.2.clockwise.rotate.90" : "list.bullet.rectangle")
            }
            .help("Lavori in corso")
            .popover(isPresented: $showJobs) { JobsView() }
            .badge(store.runningJobs)
        }
        ToolbarItem {
            Button { store.showInspector.toggle() } label: { Label("Dettagli", systemImage: "sidebar.trailing") }
                .help("Mostra o nascondi i dettagli")
        }
    }

    private var sortBinding: Binding<String> {
        Binding(get: { sortKey }, set: { k in
            let rev = store.sortOrder.first?.order == .reverse
            let o: SortOrder = rev ? .reverse : .forward
            switch k {
            case "author": store.sortOrder = [KeyPathComparator(\.authorSort, order: o)]
            case "added": store.sortOrder = [KeyPathComparator(\.added, order: o)]
            case "rating": store.sortOrder = [KeyPathComparator(\.rating, order: o)]
            case "year": store.sortOrder = [KeyPathComparator(\.year, order: o)]
            default: store.sortOrder = [KeyPathComparator(\.titleSort, order: o)]
            }
        })
    }
    private var sortKey: String {
        guard let kp = store.sortOrder.first?.keyPath else { return "title" }
        if kp == \Book.authorSort { return "author" }
        if kp == \Book.added { return "added" }
        if kp == \Book.rating { return "rating" }
        if kp == \Book.year { return "year" }
        return "title"
    }

    private func saveToDisk() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true
        p.prompt = "Salva qui"; p.message = "Dove salvare i libri selezionati?"
        if p.runModal() == .OK, let u = p.url { store.export(ids: Array(store.selection), to: u) }
    }
}

struct FilterBar: View {
    private var store: LibraryStore { LibraryStore.shared }

    var body: some View {
        @Bindable var store = store
        if store.hasFilters {
            HStack(spacing: 6) {
                ForEach(store.activeTags, id: \.self) { t in chip(label(t), color: .accentColor) { store.sidebar.remove(.tag(t.kind, t.value)); if store.sidebar.isEmpty { store.sidebar = [.smart(.all)] } } }
                ForEach(Array(store.excluded), id: \.self) { t in chip("NON " + label(t), color: .red) { store.excluded.remove(t) } }
                if store.activeTags.count > 1 {
                    Picker("", selection: $store.matchAll) { Text("Tutti").tag(true); Text("Almeno uno").tag(false) }
                        .pickerStyle(.segmented).labelsHidden().fixedSize()
                }
                Spacer()
                Button("Azzera") { store.clearFilters() }.buttonStyle(.plain).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(.bar)
            .overlay(alignment: .bottom) { Divider() }
        }
    }
    private func label(_ t: TagKey) -> String { t.kind == .rating ? String(repeating: "★", count: Int(t.value) ?? 0) : t.value }
    private func chip(_ text: String, color: Color, remove: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Text(text).font(.callout)
            Button(action: remove) { Image(systemName: "xmark.circle.fill").imageScale(.small) }.buttonStyle(.plain)
        }
        .padding(.horizontal, 9).padding(.vertical, 3)
        .background(color.opacity(0.15), in: Capsule())
        .foregroundStyle(color)
    }
}

struct StatusBar: View {
    private var store: LibraryStore { LibraryStore.shared }

    var body: some View {
        @Bindable var store = store
        HStack(spacing: 12) {
            Circle().fill(.green).frame(width: 7, height: 7)
            Text("\(store.visible.count) libri").foregroundStyle(.secondary)
            if !store.selection.isEmpty { Text("· \(store.selection.count) selezionati").foregroundStyle(.secondary) }
            Spacer()
            if let r = store.fullText ? store.ftsStatus : nil { Text(r).foregroundStyle(.secondary) }
            if store.viewMode == .grid {
                Image(systemName: "square.grid.3x3").foregroundStyle(.secondary)
                Slider(value: $store.coverSize, in: 110...260).frame(width: 120).controlSize(.small)
            }
        }
        .font(.callout)
        .padding(.horizontal, 12).padding(.vertical, 5)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

struct ToastView: View {
    private var store: LibraryStore { LibraryStore.shared }
    var body: some View {
        if let t = store.toast {
            Text(t).font(.callout).padding(.horizontal, 16).padding(.vertical, 9)
                .glassEffect(.regular, in: Capsule())
                .padding(.bottom, 44)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

struct JobsView: View {
    private var store: LibraryStore { LibraryStore.shared }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Lavori").font(.headline)
            if store.jobs.isEmpty { Text("Nessun lavoro in corso").foregroundStyle(.secondary) }
            ForEach(store.jobs.prefix(8)) { j in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(j.title).lineLimit(1)
                        Spacer()
                        switch j.state {
                        case .running: ProgressView().controlSize(.small)
                        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        }
                    }
                    if j.state == .running { if let p = j.progress { ProgressView(value: p) } else { ProgressView().progressViewStyle(.linear) } }
                    if j.state == .failed { Text(j.message).font(.caption).foregroundStyle(.secondary).lineLimit(3) }
                }
            }
        }
        .padding(16).frame(width: 320)
    }
}

struct WelcomeView: View {
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "books.vertical.fill").font(.system(size: 64)).foregroundStyle(.tint)
            Text("Benvenuto in Calibre").font(.largeTitle.bold())
            Text("Una nuova interfaccia nativa per la tua libreria. Scegli una libreria esistente o creane una nuova.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 380)
            HStack {
                Button("Apri libreria…") { LibraryPicker.open() }.buttonStyle(.borderedProminent).controlSize(.large)
                Button("Nuova libreria…") { LibraryPicker.create() }.controlSize(.large)
            }
        }
        .padding(60)
    }
}

struct ErrorView: View {
    var message: String
    var body: some View {
        ContentUnavailableView {
            Label("Impossibile aprire la libreria", systemImage: "exclamationmark.triangle")
        } description: { Text(message) } actions: {
            Button("Scegli un’altra libreria…") { LibraryPicker.open() }
            Link("Scarica Calibre", destination: URL(string: "https://calibre-ebook.com/download_osx")!)
            SettingsLink { Text("Impostazioni…") }
        }
    }
}
