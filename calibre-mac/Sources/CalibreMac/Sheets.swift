import SwiftUI

struct IdRow: Identifiable, Hashable { var id = UUID(); var key: String; var value: String }

struct EditMetadataView: View {
    private var store: LibraryStore { LibraryStore.shared }
    @Environment(\.dismiss) private var dismiss

    @State private var currentID = 0
    @State private var title = ""
    @State private var authors = ""
    @State private var series = ""
    @State private var seriesIndex = ""
    @State private var publisher = ""
    @State private var tags = ""
    @State private var languages = ""
    @State private var comments = ""
    @State private var rating = 0
    @State private var ids: [IdRow] = []
    @State private var original: Book?
    @State private var fetching = false
    @State private var coverFile: URL?
    @State private var pickCover = false
    @State private var fetched: LibraryStore.FetchedMeta?
    @State private var fetchError: String?

    private var multi: Bool { store.selection.count > 1 }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if !multi {
                    Button { step(-1) } label: { Image(systemName: "chevron.left") }.disabled(index == nil || index == 0)
                    Button { step(1) } label: { Image(systemName: "chevron.right") }.disabled(index == nil || index == store.visible.count - 1)
                }
                Text(multi ? "Modifica \(store.selection.count) libri" : "Metadati").font(.headline)
                Spacer()
                if !multi, let i = index { Text("\(i + 1) di \(store.visible.count)").foregroundStyle(.secondary) }
            }.padding([.horizontal, .top], 18).padding(.bottom, 10)
            Form {
                if multi {
                    Text("Solo i campi compilati vengono applicati. I tag si aggiungono a quelli esistenti.").font(.callout).foregroundStyle(.secondary)
                } else {
                    Section {
                        HStack(alignment: .top, spacing: 16) {
                            Group {
                                if let u = coverFile, let img = NSImage(contentsOf: u) {
                                    Image(nsImage: img).resizable().scaledToFill().aspectRatio(2 / 3, contentMode: .fit)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                } else if let b = original { CoverView(book: b) }
                            }
                            .frame(width: 92).shadow(color: .black.opacity(0.25), radius: 5, y: 3)
                            VStack(alignment: .leading, spacing: 8) {
                                Button("Scegli immagine…", systemImage: "photo") { pickCover = true }
                                if coverFile != nil { Button("Annulla modifica copertina") { coverFile = nil }.buttonStyle(.link) }
                                Text("Puoi anche trascinare un file immagine su questa finestra.").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    TextField("Titolo", text: $title)
                }
                TextField("Autori", text: $authors, prompt: Text(multi ? "" : "separati da &"))
                HStack { TextField("Serie", text: $series); if !multi { TextField("N°", text: $seriesIndex).frame(width: 60) } }
                TextField("Editore", text: $publisher)
                TextField(multi ? "Aggiungi tag" : "Tag", text: $tags, prompt: Text("separati da virgola"))
                TextField("Lingue", text: $languages, prompt: Text("it, en"))
                Picker("Valutazione", selection: $rating) {
                    if multi { Text("—").tag(-1) }
                    Text("Nessuna").tag(0)
                    ForEach(1...5, id: \.self) { Text(String(repeating: "★", count: $0)).tag($0) }
                }
                if !multi {
                    Section("Identificatori") {
                        ForEach($ids) { $r in
                            HStack { TextField("", text: $r.key).frame(width: 90); TextField("", text: $r.value)
                                Button { ids.removeAll { $0.id == r.id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain) }
                        }
                        Button("Aggiungi identificatore", systemImage: "plus") { ids.append(IdRow(key: "isbn", value: "")) }.buttonStyle(.link)
                    }
                    Section("Commenti") {
                        TextEditor(text: $comments).font(.body).frame(minHeight: 90)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
                    }
                    if fetching { HStack { ProgressView().controlSize(.small); Text("Interrogo le fonti online…").foregroundStyle(.secondary) } }
                    if let e = fetchError { Text(e).foregroundStyle(.red).font(.callout) }
                    if let f = fetched {
                        GroupBox("Risultato trovato") {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(f.title).fontWeight(.semibold)
                                Text([f.authors, f.publisher, f.date].filter { !$0.isEmpty }.joined(separator: " · ")).foregroundStyle(.secondary)
                                if !f.isbn.isEmpty { Text("ISBN \(f.isbn)").font(.caption).foregroundStyle(.secondary) }
                                HStack { Spacer(); Button("Applica questi metadati") { Task { await store.applyOPF(f.opfPath, to: currentID); fetched = nil; load() } } }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                if !multi { Button("Scarica metadati") { fetch() }.disabled(fetching) }
                Spacer()
                Button("Annulla", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Salva") { save(); dismiss() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }.padding(18)
        }
        .frame(width: 560, height: multi ? 460 : 800)
        .fileImporter(isPresented: $pickCover, allowedContentTypes: [.image]) { r in if case .success(let u) = r { coverFile = u } }
        .dropDestination(for: URL.self) { urls, _ in
            if !multi, let u = urls.first, ["jpg", "jpeg", "png", "gif", "webp", "heic", "tiff"].contains(u.pathExtension.lowercased()) { coverFile = u; return true }
            return false
        }
        .onAppear { currentID = store.selection.first ?? 0; load() }
    }

    private var index: Int? { store.visible.firstIndex { $0.id == currentID } }
    private func step(_ d: Int) {
        guard let i = index, store.visible.indices.contains(i + d) else { return }
        save(); currentID = store.visible[i + d].id; store.selection = [currentID]; load()
    }

    private func load() {
        fetched = nil; fetchError = nil; coverFile = nil
        guard !multi, let b = store.books.first(where: { $0.id == currentID }) else { rating = -1; return }
        original = b
        title = b.title; authors = b.authors.joined(separator: " & "); series = b.series
        seriesIndex = b.seriesIndex > 0 ? (b.seriesIndex == b.seriesIndex.rounded() ? String(Int(b.seriesIndex)) : String(b.seriesIndex)) : ""
        publisher = b.publisher; tags = b.tags.joined(separator: ", "); languages = b.languages.joined(separator: ", ")
        rating = b.rating; comments = b.plainComments
        ids = b.identifiers.sorted { $0.key < $1.key }.map { IdRow(key: $0.key, value: $0.value) }
    }

    private func fetch() {
        guard let b = original else { return }
        fetching = true; fetched = nil; fetchError = nil
        var probe = b; probe.title = title; if let a = authors.split(separator: "&").first { probe.authors = [a.trimmingCharacters(in: .whitespaces)] }
        Task {
            do { fetched = try await store.fetchMetadata(for: probe) } catch { fetchError = error.localizedDescription }
            fetching = false
        }
    }

    private func save() {
        var f: [String: String] = [:]
        func list(_ s: String, _ sep: Character) -> [String] { s.split(separator: sep).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
        if multi {
            if !authors.isEmpty { f["authors"] = list(authors, "&").joined(separator: " & ") }
            if !series.isEmpty { f["series"] = series }
            if !publisher.isEmpty { f["publisher"] = publisher }
            if !languages.isEmpty { f["languages"] = list(languages, ",").joined(separator: ",") }
            if rating >= 0 { f["rating"] = String(rating * 2) }
            let add = list(tags, ",")
            let targets = store.selectedBooks
            Task {
                if !add.isEmpty { for b in targets { await store.setMetadata(ids: [b.id], fields: ["tags": Array(Set(b.tags + add)).sorted().joined(separator: ",")]) } }
                await store.setMetadata(ids: targets.map(\.id), fields: f)
            }
            return
        }
        guard let o = original else { return }
        if title != o.title { f["title"] = title }
        if list(authors, "&") != o.authors { f["authors"] = list(authors, "&").joined(separator: " & ") }
        if series != o.series { f["series"] = series }
        let idx = Double(seriesIndex.replacingOccurrences(of: ",", with: ".")) ?? 0
        if idx != o.seriesIndex { f["series_index"] = String(idx) }
        if publisher != o.publisher { f["publisher"] = publisher }
        if list(tags, ",") != o.tags { f["tags"] = list(tags, ",").joined(separator: ",") }
        if list(languages, ",") != o.languages { f["languages"] = list(languages, ",").joined(separator: ",") }
        if rating != o.rating { f["rating"] = String(rating * 2) }
        if comments != o.plainComments { f["comments"] = comments }
        let newIDs = Dictionary(ids.filter { !$0.key.isEmpty && !$0.value.isEmpty }.map { ($0.key, $0.value) }, uniquingKeysWith: { $1 })
        if newIDs != o.identifiers { f["identifiers"] = newIDs.map { "\($0.key):\($0.value)" }.sorted().joined(separator: ",") }
        if let c = coverFile { f["cover"] = c.path }
        let id = o.id
        Task { await store.setMetadata(ids: [id], fields: f) }
    }
}

struct ConvertView: View {
    private var store: LibraryStore { LibraryStore.shared }
    @Environment(\.dismiss) private var dismiss
    @AppStorage("defFmt") private var fmt = "EPUB"
    @AppStorage("profile") private var profile = "default"
    @AppStorage("polish") private var polish = false

    static let formats = ["EPUB", "MOBI", "AZW3", "KEPUB", "PDF", "DOCX", "FB2", "TXT", "HTMLZ"]
    static let profiles = [("default", "Predefinito"), ("kindle", "Kindle"), ("kobo", "Kobo"), ("tablet", "Tablet"), ("generic_eink", "E-ink generico"), ("ipad", "iPad")]

    var body: some View {
        let list = store.selectedBooks
        VStack(alignment: .leading, spacing: 14) {
            Text("Converti \(list.count == 1 ? "libro" : "\(list.count) libri")").font(.headline)
            Text(list.count == 1 ? (list.first?.title ?? "") : "Conversione in blocco").foregroundStyle(.secondary).lineLimit(1)
            Form {
                Picker("Formato di uscita", selection: $fmt) { ForEach(Self.formats, id: \.self) { Text($0) } }
                Picker("Profilo dispositivo", selection: $profile) { ForEach(Self.profiles, id: \.0) { Text($0.1).tag($0.0) } }
                Toggle("Rifinisci dopo la conversione", isOn: $polish).disabled(!["EPUB", "AZW3"].contains(fmt))
            }.formStyle(.grouped)
            HStack {
                Spacer()
                Button("Annulla", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Converti") { store.convert(list, to: fmt, profile: profile, polish: polish); dismiss() }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }
        .padding(20).frame(width: 440)
    }
}

struct NewsView: View {
    private var store: LibraryStore { LibraryStore.shared }
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    private let suggestions = ["The Guardian", "BBC News", "Il Post", "La Repubblica", "Internazionale", "Corriere della Sera", "The Economist", "Wired"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Scarica notizie").font(.headline)
            Text("Scarica un quotidiano o una rivista come e-book usando le ricette integrate di Calibre.").foregroundStyle(.secondary)
            TextField("Nome della ricetta", text: $name).textFieldStyle(.roundedBorder)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack { ForEach(suggestions, id: \.self) { s in Button(s) { name = s }.buttonStyle(.bordered).controlSize(.small) } }
            }
            HStack {
                Spacer()
                Button("Annulla", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Scarica") { store.fetchNews(name); dismiss() }.disabled(name.isEmpty).keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }
        .padding(20).frame(width: 460)
    }
}

struct SettingsView: View {
    private var store: LibraryStore { LibraryStore.shared }
    @AppStorage("defFmt") private var fmt = "EPUB"
    @AppStorage("profile") private var profile = "default"
    @AppStorage("polish") private var polish = false
    @State private var dir = Engine.shared.calibreDir

    var body: some View {
        TabView {
            Form {
                Section("Motore Calibre") {
                    TextField("Percorso eseguibili", text: $dir).onSubmit { Engine.shared.calibreDir = dir }
                    LabeledContent("Stato") {
                        if store.engine.ready { Label("Server attivo sulla porta \(store.engine.port)", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                        else if Engine.shared.calibreInstalled { Label("Pronto", systemImage: "circle") }
                        else { Label("Calibre non trovato", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                    }
                    Text("Calibre.app serve solo come motore (database, conversione, metadati). La sua interfaccia Qt non viene mai avviata.").font(.callout).foregroundStyle(.secondary)
                }
                Section("Libreria") {
                    LabeledContent("Cartella") { Text(store.engine.libraryPath).textSelection(.enabled).lineLimit(1).truncationMode(.middle) }
                    HStack { Button("Apri libreria…") { LibraryPicker.open() }; Button("Nuova libreria…") { LibraryPicker.create() } }
                }
            }.formStyle(.grouped).tabItem { Label("Generali", systemImage: "gearshape") }
            Form {
                Picker("Formato predefinito", selection: $fmt) { ForEach(ConvertView.formats, id: \.self) { Text($0) } }
                Picker("Profilo dispositivo", selection: $profile) { ForEach(ConvertView.profiles, id: \.0) { Text($0.1).tag($0.0) } }
                Toggle("Rifinisci dopo la conversione", isOn: $polish)
            }.formStyle(.grouped).tabItem { Label("Conversione", systemImage: "arrow.triangle.2.circlepath") }
        }
        .frame(width: 520, height: 380)
    }
}
