import Foundation
import Observation
import AppKit

enum ViewMode: String, CaseIterable { case list, grid }

@Observable @MainActor
final class LibraryStore {
    static let shared = LibraryStore()
    let engine = Engine.shared

    // Dati
    var books: [Book] = [] { didSet { rebuildCategories(); recompute() } }
    private(set) var visible: [Book] = []
    private(set) var categories: [Kind: [CategoryItem]] = [:]

    // Stato UI
    var selection: Set<Int> = [] { didSet { if selection != oldValue { /* inspector segue la selezione */ } } }
    var search = "" { didSet { if search != oldValue { recompute() } } }
    var fullText = false { didSet { ftsHits = nil; recompute() } }
    var sidebar: Set<SideItem> = [.smart(.all)] { didSet { recompute() } }
    var excluded: Set<TagKey> = [] { didSet { recompute() } }
    var matchAll = true { didSet { recompute() } }
    var sortOrder: [KeyPathComparator<Book>] = [KeyPathComparator(\.titleSort)] { didSet { recompute() } }
    var viewMode: ViewMode = ViewMode(rawValue: UserDefaults.standard.string(forKey: "viewMode") ?? "") ?? .list {
        didSet { UserDefaults.standard.set(viewMode.rawValue, forKey: "viewMode") }
    }
    var coverSize: Double = 150
    var sidebarByCount = false
    var showInspector = true
    var showImporter = false
    var showEdit = false
    var showConvert = false
    var showDelete = false
    var showNews = false
    var quickLook: URL?
    var toast: String?
    var loading = false
    var jobs: [Job] = []
    var ftsHits: [Int: String]? = nil
    var openReader: ((Int) -> Void)?
    var hasLibrary = UserDefaults.standard.string(forKey: "libraryPath") != nil || ProcessInfo.processInfo.environment["CALIBREMAC_LIBRARY"] != nil
    var ftsStatus: String?
    var devices: [Device] = []
    var showSend = false
    var monitoring = false

    var marked: Set<Int> = Set((UserDefaults.standard.array(forKey: "marked") as? [Int]) ?? []) {
        didSet { UserDefaults.standard.set(Array(marked), forKey: "marked"); recompute() }
    }
    var savedSearches: [SavedSearch] = {
        guard let d = UserDefaults.standard.data(forKey: "saved"), let v = try? JSONDecoder().decode([SavedSearch].self, from: d) else { return [] }
        return v
    }() { didSet { UserDefaults.standard.set(try? JSONEncoder().encode(savedSearches), forKey: "saved") } }
    var recentLibraries: [String] = (UserDefaults.standard.array(forKey: "recentLibs") as? [String]) ?? []

    var libraryPath: String? { UserDefaults.standard.string(forKey: "libraryPath") }
    var selectedBooks: [Book] { books.filter { selection.contains($0.id) } }
    var activeTags: [TagKey] { sidebar.compactMap { if case .tag(let k, let v) = $0 { TagKey(kind: k, value: v) } else { nil } } }
    var hasFilters: Bool { !activeTags.isEmpty || !excluded.isEmpty }

    // MARK: Libreria

    func openLibrary(_ path: String) async {
        loading = true; hasLibrary = true
        UserDefaults.standard.set(path, forKey: "libraryPath")
        recentLibraries = ([path] + recentLibraries.filter { $0 != path }).prefix(6).map { $0 }
        UserDefaults.standard.set(recentLibraries, forKey: "recentLibs")
        selection = []; books = []
        await engine.start(libraryPath: path)
        if engine.ready { await reload() }
        loading = false
    }

    func reload(ids: [Int]? = nil) async {
        guard engine.ready else { return }
        do {
            let fresh = try await engine.fetchBooks(base: engine.baseURL, lib: engine.libraryID, ids: ids)
            if let ids {
                var dict = Dictionary(uniqueKeysWithValues: books.map { ($0.id, $0) })
                for b in fresh { dict[b.id] = b }
                for id in ids where !fresh.contains(where: { $0.id == id }) { dict[id] = nil }
                books = Array(dict.values)
            } else { books = fresh }
        } catch { say("Errore nel caricamento: \(error.localizedDescription)") }
    }

    func say(_ m: String) {
        toast = m
        Task { try? await Task.sleep(nanoseconds: 3_500_000_000); if toast == m { toast = nil } }
    }

    // MARK: Filtri

    private func recompute() {
        var r = books
        var scope: Smart = .all
        var savedQueries: [Query] = []
        for item in sidebar {
            if case .smart(let s) = item { scope = s }
            if case .saved(let id) = item, let s = savedSearches.first(where: { $0.id == id }) { savedQueries.append(Query(s.query)) }
        }
        switch scope {
        case .all: break
        case .recent: let c = Date().addingTimeInterval(-30 * 86400); r = r.filter { $0.added > c }
        case .marked: r = r.filter { marked.contains($0.id) }
        case .top: r = r.filter { $0.rating >= 5 }
        }
        let tags = activeTags
        if !tags.isEmpty {
            r = r.filter { b in
                let f: (TagKey) -> Bool = { $0.kind.values(of: b).contains($0.value) }
                return matchAll ? tags.allSatisfy(f) : tags.contains(where: f)
            }
        }
        if !excluded.isEmpty { r = r.filter { b in !excluded.contains { $0.kind.values(of: b).contains($0.value) } } }
        for q in savedQueries { r = r.filter(q.matches) }
        let s = search.trimmingCharacters(in: .whitespaces)
        if !s.isEmpty {
            if fullText {
                if let hits = ftsHits { r = r.filter { hits[$0.id] != nil } }
            } else { let q = Query(s); r = r.filter(q.matches) }
        }
        r.sort(using: sortOrder)
        visible = r
    }

    private func rebuildCategories() {
        var out: [Kind: [String: Int]] = [:]
        for b in books { for k in Kind.allCases { for v in k.values(of: b) { out[k, default: [:]][v, default: 0] += 1 } } }
        categories = out.mapValues { $0.map { CategoryItem(kind: .tag, name: $0.key, count: $0.value) } }
        for k in Kind.allCases {
            categories[k] = (out[k] ?? [:]).map { CategoryItem(kind: k, name: $0.key, count: $0.value) }
        }
    }

    func items(_ kind: Kind) -> [CategoryItem] {
        let l = categories[kind] ?? []
        if sidebarByCount { return l.sorted { $0.count != $1.count ? $0.count > $1.count : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending } }
        if kind == .rating { return l.sorted { $0.name > $1.name } }
        return l.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func clearFilters() { sidebar = [.smart(.all)]; excluded = []; search = "" }

    func saveCurrentSearch(name: String) {
        guard !search.isEmpty else { return }
        savedSearches.append(SavedSearch(name: name, query: search))
    }

    // MARK: Lavori

    func runJob(_ title: String, _ work: @escaping @Sendable (@escaping @Sendable (Double?) -> Void) async throws -> Void) {
        let job = Job(title: title)
        jobs.insert(job, at: 0)
        let jid = job.id
        Task {
            let progress: @Sendable (Double?) -> Void = { p in
                Task { @MainActor in if let i = self.jobs.firstIndex(where: { $0.id == jid }) { self.jobs[i].progress = p } }
            }
            do {
                try await work(progress)
                if let i = jobs.firstIndex(where: { $0.id == jid }) { jobs[i].state = .done; jobs[i].progress = 1 }
            } catch {
                if let i = jobs.firstIndex(where: { $0.id == jid }) { jobs[i].state = .failed; jobs[i].message = error.localizedDescription }
                say("Errore: \(error.localizedDescription)")
            }
        }
    }
    var runningJobs: Int { jobs.filter { $0.state == .running }.count }

    // MARK: Azioni sui libri

    func add(urls: [URL]) {
        guard engine.ready, !urls.isEmpty else { return }
        let before = Set(books.map(\.id))
        runJob("Aggiungo \(urls.count) file") { [engine] _ in
            _ = try await engine.calibredb(["add"] + urls.map(\.path))
            await self.reload()
            await MainActor.run {
                let new = Set(self.books.map(\.id)).subtracting(before)
                if !new.isEmpty { self.selection = new }
                self.say(new.isEmpty ? "Nessun nuovo libro (duplicati?)" : "\(new.count) libri aggiunti")
            }
        }
    }

    func addEmpty() {
        runJob("Libro vuoto") { [engine] _ in
            _ = try await engine.calibredb(["add", "--empty", "--title", "Nuovo libro", "--authors", "Autore sconosciuto"])
            await self.reload()
        }
    }

    func setMetadata(ids: [Int], fields: [String: String]) async {
        guard !fields.isEmpty else { return }
        do {
            for id in ids {
                _ = try await engine.calibredb(["set_metadata", String(id)] + fields.flatMap { ["-f", "\($0.key):\($0.value)"] })
            }
            await reload(ids: ids)
        } catch { say("Errore: \(error.localizedDescription)") }
    }

    func setCover(id: Int, url: URL) {
        guard ["jpg", "jpeg", "png", "gif", "webp", "heic", "tiff", "bmp"].contains(url.pathExtension.lowercased()) else { say("Trascina un file immagine"); return }
        Task { await setMetadata(ids: [id], fields: ["cover": url.path]); say("Copertina aggiornata") }
    }

    func setRating(_ ids: [Int], stars: Int) {
        // aggiornamento ottimistico, poi sincronizzazione
        books = books.map { var b = $0; if ids.contains(b.id) { b.rating = stars }; return b }
        Task { await setMetadata(ids: ids, fields: ["rating": String(stars * 2)]) }
    }

    func remove(ids: [Int]) {
        runJob("Rimuovo \(ids.count) libri") { [engine] _ in
            _ = try await engine.calibredb(["remove", ids.map(String.init).joined(separator: ",")])
            await self.reload(ids: ids)
            await MainActor.run { self.selection.subtract(ids) }
        }
    }

    func removeFormat(id: Int, fmt: String) {
        runJob("Rimuovo \(fmt.uppercased())") { [engine] _ in
            _ = try await engine.calibredb(["remove_format", String(id), fmt.uppercased()])
            await self.reload(ids: [id])
        }
    }

    func export(ids: [Int], to dir: URL) {
        runJob("Salvo \(ids.count) libri su disco") { [engine] _ in
            _ = try await engine.calibredb(["export", "--to-dir", dir.path] + ids.map(String.init))
            await MainActor.run { NSWorkspace.shared.activateFileViewerSelecting([dir]) }
        }
    }

    func convert(_ list: [Book], to fmt: String, profile: String, polish: Bool) {
        for b in list {
            guard let src = b.formatPaths.first(where: { $0.key != fmt.lowercased() })?.value ?? b.formatPaths.values.first else { say("“\(b.title)” non ha file"); continue }
            runJob("\(b.title) → \(fmt.uppercased())") { [engine] progress in
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: tmp) }
                let out = tmp.appendingPathComponent("book.\(fmt.lowercased())").path
                var args = [src, out]
                if profile != "default" { args += ["--output-profile", profile] }
                _ = try await engine.run(await engine.tool("ebook-convert"), args) { line in
                    if let r = line.range(of: #"^\d+(?=%)"#, options: .regularExpression), let v = Double(line[r]) { progress(v / 100) }
                }
                var final = out
                if polish, ["epub", "azw3"].contains(fmt.lowercased()) {
                    let pol = tmp.appendingPathComponent("polished.\(fmt.lowercased())").path
                    _ = try await engine.run(await engine.tool("ebook-polish"), ["--smarten-punctuation", "--remove-unused-css", out, pol])
                    final = pol
                }
                _ = try await engine.calibredb(["add_format", String(b.id), final])
                await self.reload(ids: [b.id])
            }
        }
    }

    func polish(_ list: [Book]) {
        for b in list {
            guard let src = b.formatPaths["epub"] ?? b.formatPaths["azw3"] else { say("Servono EPUB o AZW3"); continue }
            let ext = (src as NSString).pathExtension
            runJob("Rifinisco \(b.title)") { [engine] _ in
                let out = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).\(ext)").path
                defer { try? FileManager.default.removeItem(atPath: out) }
                _ = try await engine.run(await engine.tool("ebook-polish"), ["--smarten-punctuation", "--remove-unused-css", "--compress-images", src, out])
                _ = try await engine.calibredb(["add_format", String(b.id), out])
                await self.reload(ids: [b.id])
            }
        }
    }

    func embedMetadata(_ list: [Book]) {
        runJob("Incorpora metadati") { [engine] _ in
            _ = try await engine.calibredb(["embed_metadata"] + list.map { String($0.id) })
        }
    }

    func toggleMark(_ ids: [Int]) {
        let all = ids.allSatisfy { marked.contains($0) }
        if all { marked.subtract(ids) } else { marked.formUnion(ids) }
    }

    func revealInFinder(_ list: [Book]) {
        let urls = list.compactMap { $0.bestPath }.map { URL(fileURLWithPath: $0) }
        if !urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(urls) }
    }

    func openExternally(_ b: Book, fmt: String? = nil) {
        guard let p = fmt.flatMap({ b.formatPaths[$0.lowercased()] }) ?? b.bestPath else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: p))
    }

    func preview(_ b: Book) {
        if let p = b.bestPath { quickLook = URL(fileURLWithPath: p) }
    }

    func randomBook() {
        if let b = visible.randomElement() { selection = [b.id] }
    }

    // MARK: Tag browser: rinomina / unisci / rimuovi

    func edit(kind: Kind, value: String, to new: String?) {
        let affected = books.filter { kind.values(of: $0).contains(value) }
        guard !affected.isEmpty else { return }
        runJob(new == nil ? "Rimuovo “\(value)”" : "Rinomino “\(value)”") { [engine] progress in
            for (i, b) in affected.enumerated() {
                var f: [String: String] = [:]
                switch kind {
                case .tag:
                    var t = b.tags.map { $0 == value ? (new ?? "") : $0 }.filter { !$0.isEmpty }
                    t = t.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
                    f["tags"] = t.joined(separator: ",")
                case .author: f["authors"] = b.authors.map { $0 == value ? (new ?? "") : $0 }.filter { !$0.isEmpty }.joined(separator: " & ")
                case .series: f["series"] = new ?? ""
                case .publisher: f["publisher"] = new ?? ""
                default: return
                }
                _ = try await engine.calibredb(["set_metadata", String(b.id)] + f.flatMap { ["-f", "\($0.key):\($0.value)"] })
                progress(Double(i + 1) / Double(affected.count))
            }
            await self.reload(ids: affected.map(\.id))
            await MainActor.run { self.sidebar = self.sidebar.filter { if case .tag(let k, let v) = $0 { return !(k == kind && v == value) }; return true }; if self.sidebar.isEmpty { self.sidebar = [.smart(.all)] } }
        }
    }

    // MARK: Scarica metadati

    struct FetchedMeta { var title = "", authors = "", publisher = "", date = "", isbn = "", comments = "", opfPath = "" }

    func fetchMetadata(for b: Book) async throws -> FetchedMeta {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let opf = tmp.appendingPathComponent("meta.opf").path
        var args = ["-t", b.title, "-o", "-d", "20", "--opf"]
        if let a = b.authors.first, a != "Sconosciuto" { args += ["-a", a] }
        if let isbn = b.identifiers["isbn"] { args += ["-i", isbn] }
        let out = try await engine.run(engine.tool("fetch-ebook-metadata"), args)
        try out.write(toFile: opf, atomically: true, encoding: .utf8)
        var m = FetchedMeta(opfPath: opf)
        func tag(_ t: String) -> String? {
            guard let r = out.range(of: "<\(t)[^>]*>([^<]*)</\(t)>", options: .regularExpression) else { return nil }
            return String(out[r]).replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        }
        m.title = tag("dc:title") ?? ""
        m.authors = tag("dc:creator") ?? ""
        m.publisher = tag("dc:publisher") ?? ""
        m.date = String((tag("dc:date") ?? "").prefix(10))
        m.comments = tag("dc:description") ?? ""
        if let r = out.range(of: #"<dc:identifier[^>]*opf:scheme="ISBN"[^>]*>([^<]*)<"#, options: .regularExpression) {
            m.isbn = String(out[r]).replacingOccurrences(of: "<[^>]+>?", with: "", options: .regularExpression)
        }
        guard !m.title.isEmpty else { throw ToolError(message: "Nessun risultato dalle fonti online.") }
        return m
    }

    func applyOPF(_ path: String, to id: Int) async {
        do {
            _ = try await engine.calibredb(["set_metadata", String(id), path])
            await reload(ids: [id])
            say("Metadati applicati")
        } catch { say("Errore: \(error.localizedDescription)") }
    }

    // MARK: Ricerca nel testo

    func runFTS() async {
        guard fullText else { ftsStatus = nil; return }
        let q = search.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { ftsHits = nil; ftsStatus = nil; recompute(); return }
        try? await Task.sleep(nanoseconds: 350_000_000)
        if Task.isCancelled { return }
        do {
            _ = try? await engine.calibredb(["fts_index", "enable"])
            let out = try await engine.calibredb(["fts_search", "--output-format", "json", q])
            guard let d = out.data(using: .utf8), let arr = try JSONSerialization.jsonObject(with: d) as? [[String: Any]] else { throw ToolError(message: out) }
            var hits: [Int: String] = [:]
            for r in arr { if let id = r["book_id"] as? Int { hits[id] = (r["text"] as? String) ?? "" } }
            ftsHits = hits; ftsStatus = "\(hits.count) libri con corrispondenze"
            recompute()
        } catch {
            ftsHits = [:]; ftsStatus = error.localizedDescription.contains("indicizzat") ? "Indicizzazione in corso…" : "Ricerca non disponibile"
            recompute()
        }
    }

    func addFormat(id: Int, url: URL) {
        runJob("Aggiungo formato") { [engine] _ in
            _ = try await engine.calibredb(["add_format", String(id), url.path])
            await self.reload(ids: [id])
        }
    }

    func fetchNews(_ name: String) {
        runJob("Notizie: \(name)") { [engine] progress in
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tmp) }
            let out = tmp.appendingPathComponent("\(name).epub").path
            _ = try await engine.run(await engine.tool("ebook-convert"), ["\(name).recipe", out]) { line in
                if let r = line.range(of: #"^\d+(?=%)"#, options: .regularExpression), let v = Double(line[r]) { progress(v / 100) }
            }
            _ = try await engine.calibredb(["add", "--tags", "News", out])
            await self.reload()
        }
    }
}
