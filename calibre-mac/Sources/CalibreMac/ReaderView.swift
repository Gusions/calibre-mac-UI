import SwiftUI
import WebKit
import PDFKit

struct Heading: Identifiable, Hashable { var id: String; var title: String; var level: Int }

@Observable @MainActor
final class WebController: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    let view: WKWebView
    let bookID: Int
    var headings: [Heading] = []
    var progress: Double = 0
    var size = 19.0
    var font = "serif"
    var theme = "white"

    init(bookID: Int) {
        self.bookID = bookID
        let cfg = WKWebViewConfiguration()
        let js = "window.addEventListener('scroll',function(){var h=document.documentElement.scrollHeight-window.innerHeight;window.webkit.messageHandlers.progress.postMessage(h>0?window.scrollY/h:0)},{passive:true});"
        cfg.userContentController.addUserScript(WKUserScript(source: js, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        view = WKWebView(frame: .zero, configuration: cfg)
        super.init()
        cfg.userContentController.add(self, name: "progress")
        view.navigationDelegate = self
        view.setValue(false, forKey: "drawsBackground")
    }

    func load(_ index: URL) { view.loadFileURL(index, allowingReadAccessTo: index.deletingLastPathComponent().deletingLastPathComponent()) }

    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
        if let v = m.body as? Double { progress = v; UserDefaults.standard.set(v, forKey: "pos.\(bookID)") }
    }

    func webView(_ w: WKWebView, didFinish navigation: WKNavigation!) {
        applyStyle()
        let js = "(function(){var h=[...document.querySelectorAll('h1,h2,h3')];var l=h.map(function(e){return +e.tagName[1]});if(!h.length){h=[...document.querySelectorAll('p,div')].filter(function(e){var t=e.textContent.trim();return t.length<60&&e.children.length<2&&/^(capitolo|chapter|parte|part|libro|book)\\b/i.test(t)});l=h.map(function(){return 2})}return h.slice(0,300).map(function(e,i){e.id=e.id||'cm'+i;return {id:e.id,t:e.textContent.trim().slice(0,80),l:l[i]}})})()"
        w.evaluateJavaScript(js) { [weak self] r, _ in
            guard let self, let a = r as? [[String: Any]] else { return }
            self.headings = a.compactMap { d in
                guard let id = d["id"] as? String, let t = d["t"] as? String, !t.isEmpty else { return nil }
                return Heading(id: id, title: t, level: (d["l"] as? Int) ?? 1)
            }
        }
        let pos = UserDefaults.standard.double(forKey: "pos.\(bookID)")
        if pos > 0 { go(to: pos, delay: 0.25) }
    }

    func go(to r: Double, delay: Double = 0) {
        let js = "window.scrollTo(0, \(r) * (document.documentElement.scrollHeight - window.innerHeight));"
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { self.view.evaluateJavaScript(js) }
    }
    func scroll(to id: String) { view.evaluateJavaScript("document.getElementById('\(id)').scrollIntoView({behavior:'smooth'})") }

    func applyStyle() {
        let colors: [String: (String, String, String)] = ["white": ("#ffffff", "#1d1d1f", "#0a84ff"), "sepia": ("#f4ecd8", "#5b4636", "#9a5b13"), "dark": ("#1c1c1e", "#d8d8dc", "#64b5ff")]
        let (bg, fg, acc) = colors[theme] ?? colors["white"]!
        let fam = font == "serif" ? "'New York', Georgia, serif" : "-apple-system, 'SF Pro Text', sans-serif"
        let css = "html{background:\(bg)!important}body{max-width:720px!important;margin:0 auto!important;padding:48px 36px 140px!important;font-family:\(fam)!important;font-size:\(Int(size))px!important;line-height:1.7!important;background:\(bg)!important;color:\(fg)!important}body *{font-family:inherit!important;color:inherit!important;background:transparent!important}img,svg{max-width:100%!important;height:auto!important}a{color:\(acc)!important}"
        let js = "(function(){var s=document.getElementById('cm-style');if(!s){s=document.createElement('style');s.id='cm-style';document.head.appendChild(s)}s.textContent=`\(css)`})()"
        view.evaluateJavaScript(js)
    }

    func find(_ q: String, forward: Bool = true) {
        guard !q.isEmpty else { return }
        let c = WKFindConfiguration(); c.backwards = !forward; c.wraps = true; c.caseSensitive = false
        view.find(q, configuration: c) { _ in }
    }
}

struct WebHost: NSViewRepresentable {
    let controller: WebController
    func makeNSView(context: Context) -> WKWebView { controller.view }
    func updateNSView(_ v: WKWebView, context: Context) {}
}

struct PDFHost: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> PDFView {
        let v = PDFView(); v.autoScales = true; v.displayMode = .singlePageContinuous
        v.document = PDFDocument(url: url); return v
    }
    func updateNSView(_ v: PDFView, context: Context) {}
}

struct ReaderView: View {
    private var store: LibraryStore { LibraryStore.shared }
    let bookID: Int

    enum Phase { case loading, web, pdf(URL), failed(String) }
    @State private var phase: Phase = .loading
    @State private var controller: WebController
    @State private var showTOC = true
    @State private var tab = 0
    @State private var query = ""
    @AppStorage("rdSize") private var size = 19.0
    @AppStorage("rdFont") private var font = "serif"
    @AppStorage("rdTheme") private var theme = "auto"
    @Environment(\.colorScheme) private var scheme
    @State private var bookmarks: [Double] = []

    init(bookID: Int) {
        self.bookID = bookID
        _controller = State(initialValue: WebController(bookID: bookID))
        _bookmarks = State(initialValue: (UserDefaults.standard.array(forKey: "bm.\(bookID)") as? [Double]) ?? [])
    }

    private var book: Book? { store.books.first { $0.id == bookID } }
    private var effTheme: String { theme == "auto" ? (scheme == .dark ? "dark" : "white") : theme }
    private var bg: Color { switch effTheme { case "sepia": Color(red: 0.957, green: 0.925, blue: 0.847); case "dark": Color(red: 0.11, green: 0.11, blue: 0.118); default: .white } }

    var body: some View {
        HStack(spacing: 0) {
            if showTOC, case .web = phase { sidebar.frame(width: 240).transition(.move(edge: .leading)) }
            VStack(spacing: 0) {
                content
                if case .web = phase { footer }
            }
        }
        .background(bg)
        .preferredColorScheme(theme == "auto" ? nil : (effTheme == "dark" ? .dark : .light))
        .navigationTitle(book?.title ?? "Lettura")
        .navigationSubtitle(book?.authorText ?? "")
        .searchable(text: $query, placement: .toolbar, prompt: "Cerca nel libro")
        .onSubmit(of: .search) { controller.find(query) }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { withAnimation { showTOC.toggle() } } label: { Label("Indice", systemImage: "sidebar.leading") }
            }
            ToolbarItemGroup {
                Button { size = max(14, size - 1); sync() } label: { Label("Testo più piccolo", systemImage: "textformat.size.smaller") }
                Button { size = min(32, size + 1); sync() } label: { Label("Testo più grande", systemImage: "textformat.size.larger") }
                Menu {
                    Picker("Carattere", selection: $font) { Text("Serif").tag("serif"); Text("Sans").tag("sans") }
                    Picker("Tema", selection: $theme) { Text("Automatico").tag("auto"); Text("Bianco").tag("white"); Text("Seppia").tag("sepia"); Text("Scuro").tag("dark") }
                } label: { Label("Aspetto", systemImage: "textformat") }
                Button { toggleBookmark() } label: { Label("Segnalibro", systemImage: isBookmarked ? "bookmark.fill" : "bookmark") }
            }
        }
        .onChange(of: font) { sync() }
        .onChange(of: theme) { sync() }
        .onChange(of: scheme) { sync() }
        .task { await prepare() }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .loading: VStack(spacing: 12) { ProgressView(); Text("Preparo il libro…").foregroundStyle(.secondary) }.frame(maxWidth: .infinity, maxHeight: .infinity)
        case .web: WebHost(controller: controller)
        case .pdf(let u): PDFHost(url: u)
        case .failed(let m): ContentUnavailableView("Impossibile aprire il libro", systemImage: "exclamationmark.triangle", description: Text(m))
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) { Text("Indice").tag(0); Text("Segnalibri \(bookmarks.isEmpty ? "" : "(\(bookmarks.count))")").tag(1) }
                .pickerStyle(.segmented).labelsHidden().padding(10)
            List {
                if tab == 0 {
                    if controller.headings.isEmpty { Text("Questo libro non ha un indice.").foregroundStyle(.secondary) }
                    ForEach(controller.headings) { h in
                        Button { controller.scroll(to: h.id) } label: { Text(h.title).lineLimit(2).padding(.leading, CGFloat(max(0, h.level - 1)) * 10) }.buttonStyle(.plain)
                    }
                } else {
                    if bookmarks.isEmpty { Text("Nessun segnalibro.").foregroundStyle(.secondary) }
                    ForEach(bookmarks, id: \.self) { r in
                        Button { controller.go(to: r) } label: { Label("\(Int(r * 100))%", systemImage: "bookmark.fill") }.buttonStyle(.plain)
                            .contextMenu { Button("Elimina", role: .destructive) { bookmarks.removeAll { $0 == r }; saveBM() } }
                    }
                }
            }.listStyle(.sidebar)
        }
        .background(.regularMaterial)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Slider(value: Binding(get: { controller.progress }, set: { controller.progress = $0; controller.go(to: $0) }), in: 0...1)
            Text("\(Int(controller.progress * 100))%").monospacedDigit().foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
        }
        .padding(.horizontal, 18).padding(.vertical, 7).background(.bar)
    }

    private var isBookmarked: Bool { bookmarks.contains { abs($0 - controller.progress) < 0.01 } }
    private func toggleBookmark() {
        if let i = bookmarks.firstIndex(where: { abs($0 - controller.progress) < 0.01 }) { bookmarks.remove(at: i) }
        else { bookmarks.append(controller.progress); bookmarks.sort() }
        saveBM()
    }
    private func saveBM() { UserDefaults.standard.set(bookmarks, forKey: "bm.\(bookID)") }
    private func sync() { controller.size = size; controller.font = font; controller.theme = effTheme; controller.applyStyle() }

    private func prepare() async {
        controller.size = size; controller.font = font; controller.theme = effTheme
        guard let b = book else { phase = .failed("Libro non trovato."); return }
        if let p = b.formatPaths["pdf"] { phase = .pdf(URL(fileURLWithPath: p)); return }
        let order = ["epub", "azw3", "mobi", "kepub", "docx", "fb2", "txt", "html", "htmlz"]
        guard let (fmt, path) = order.compactMap({ f in b.formatPaths[f].map { (f, $0) } }).first else { phase = .failed("Nessun formato leggibile."); return }
        let mtime = ((try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate]) as? Date)?.timeIntervalSince1970 ?? 0
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("CalibreMac/reader/\(bookID)-\(fmt)-\(Int(mtime))")
        let dir = root.appendingPathComponent("html")
        let index = dir.appendingPathComponent("index.html")
        if !FileManager.default.fileExists(atPath: index.path) {
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let z = root.appendingPathComponent("book.htmlz").path
                _ = try await store.engine.run(store.engine.tool("ebook-convert"), [path, z])
                _ = try await store.engine.run("/usr/bin/unzip", ["-o", "-q", z, "-d", dir.path])
            } catch { phase = .failed(error.localizedDescription); try? FileManager.default.removeItem(at: root); return }
        }
        controller.load(index)
        phase = .web
    }
}
