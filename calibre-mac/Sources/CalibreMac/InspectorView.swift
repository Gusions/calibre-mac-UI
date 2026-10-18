import SwiftUI
import UniformTypeIdentifiers

struct InspectorView: View {
    private var store: LibraryStore { LibraryStore.shared }
    @State private var addingFormat = false

    var body: some View {
        Group {
            switch store.selection.count {
            case 0:
                ContentUnavailableView("Nessuna selezione", systemImage: "book.closed", description: Text("Seleziona un libro per vederne i dettagli."))
            case 1:
                if let b = store.selectedBooks.first { detail(b) }
            default:
                VStack(spacing: 10) {
                    Text("\(store.selection.count)").font(.system(size: 44, weight: .bold, design: .rounded))
                    Text("libri selezionati").foregroundStyle(.secondary)
                    Button("Modifica in blocco…") { store.showEdit = true }.buttonStyle(.borderedProminent)
                    Button("Converti…") { store.showConvert = true }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func detail(_ b: Book) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                CoverView(book: b, full: true)
                    .frame(maxWidth: 190)
                    .shadow(color: .black.opacity(0.3), radius: 12, y: 7)
                    .padding(.top, 10)
                    .onTapGesture(count: 2) { store.preview(b) }
                    .dropDestination(for: URL.self) { urls, _ in if let u = urls.first { store.setCover(id: b.id, url: u); return true }; return false }
                    .help("Trascina un’immagine per cambiare la copertina")
                VStack(spacing: 3) {
                    Text(b.title).font(.system(.title2, design: .serif).weight(.semibold)).multilineTextAlignment(.center)
                    HStack(spacing: 0) {
                        ForEach(Array(b.authors.enumerated()), id: \.offset) { i, a in
                            Button(a) { store.sidebar = [.tag(.author, a)] }.buttonStyle(.link)
                            if i < b.authors.count - 1 { Text(", ").foregroundStyle(.secondary) }
                        }
                    }
                }
                StarsView(rating: b.rating, size: 18) { store.setRating([b.id], stars: $0) }
                HStack {
                    Button { store.openReader?(b.id) } label: { Text("Leggi").frame(minWidth: 60) }.buttonStyle(.borderedProminent)
                    Button("Modifica") { store.showEdit = true }
                    Button { store.preview(b) } label: { Image(systemName: "eye") }.help("Anteprima (spazio)")
                }.controlSize(.large)

                GroupBox {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(alignment: .top) {
                            label("Formati")
                            VStack(alignment: .leading, spacing: 5) {
                                ForEach(b.formats, id: \.self) { f in formatRow(b, f) }
                                Button("Aggiungi formato…", systemImage: "plus") { addingFormat = true }.buttonStyle(.link).font(.callout)
                            }
                        }
                        if !b.series.isEmpty { line("Serie") { Button(b.seriesLabel) { store.sidebar = [.tag(.series, b.series)] }.buttonStyle(.link) } }
                        if !b.publisher.isEmpty { line("Editore") { Button(b.publisher) { store.sidebar = [.tag(.publisher, b.publisher)] }.buttonStyle(.link) } }
                        if let d = b.pubdate { line("Pubblicato") { Text(d, format: .dateTime.day().month(.wide).year()) } }
                        if !b.tags.isEmpty {
                            line("Tag") {
                                FlowTags(tags: b.tags) { t in store.sidebar = [.tag(.tag, t)] }
                            }
                        }
                        if !b.languages.isEmpty { line("Lingua") { Text(b.languageNames.joined(separator: ", ")) } }
                        ForEach(b.identifiers.sorted(by: { $0.key < $1.key }), id: \.key) { k, v in line(k.uppercased()) { Text(v).textSelection(.enabled) } }
                        line("Aggiunto") { Text(b.added, format: .dateTime.day().month().year()) }
                        line("Dimensione") { Text(ByteCountFormatter.string(fromByteCount: Int64(b.size), countStyle: .file)) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                if !b.plainComments.isEmpty {
                    Text(b.plainComments).font(.callout).foregroundStyle(.secondary).lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                }
            }
            .padding(16)
        }
        .fileImporter(isPresented: $addingFormat, allowedContentTypes: [.item]) { r in
            if case .success(let u) = r, u.startAccessingSecurityScopedResource() { store.addFormat(id: b.id, url: u) }
        }
    }

    private func label(_ t: String) -> some View { Text(t).foregroundStyle(.secondary).font(.callout).frame(width: 76, alignment: .trailing) }
    private func line<C: View>(_ t: String, @ViewBuilder _ c: () -> C) -> some View {
        HStack(alignment: .firstTextBaseline) { label(t); c().font(.callout); Spacer(minLength: 0) }
    }

    private func formatRow(_ b: Book, _ f: String) -> some View {
        Menu {
            Button("Apri", systemImage: "arrow.up.forward.app") { store.openExternally(b, fmt: f) }
            Button("Anteprima", systemImage: "eye") { if let p = b.formatPaths[f.lowercased()] { store.quickLook = URL(fileURLWithPath: p) } }
            Button("Mostra nel Finder", systemImage: "folder") { if let p = b.formatPaths[f.lowercased()] { store.revealInFinder([Book.pathOnly(p)]) } }
            Button("Leggi in Calibre", systemImage: "book") { store.openReader?(b.id) }
            Divider()
            Button("Rimuovi formato", systemImage: "trash", role: .destructive) { if b.formats.count > 1 { store.removeFormat(id: b.id, fmt: f) } else { store.say("Impossibile rimuovere l’unico formato") } }
        } label: { Text(f.uppercased()).font(.system(size: 11, weight: .semibold)) }
        .menuStyle(.button).controlSize(.small).fixedSize()
    }
}

struct FlowTags: View {
    let tags: [String]
    var tap: (String) -> Void
    var body: some View {
        Text(tags.joined(separator: ", ")).foregroundStyle(Color.accentColor)
            .onTapGesture { if let t = tags.first { tap(t) } }
            .overlay(alignment: .leading) { Color.clear }
            .contextMenu { ForEach(tags, id: \.self) { t in Button(t) { tap(t) } } }
            .help("Clic destro per filtrare per un tag")
    }
}

extension Book {
    static func pathOnly(_ p: String) -> Book {
        var b = Book(json: ["application_id": -1, "title": "", "format_metadata": ["x": ["path": p, "size": 0]]])!
        b.formatPaths = ["x": p]
        return b
    }
}
