import SwiftUI
import AppKit

struct CoverView: View {
    private var store: LibraryStore { LibraryStore.shared }
    let book: Book
    var full = false

    var body: some View {
        AsyncImage(url: store.engine.coverURL(book, full: full)) { phase in
            switch phase {
            case .success(let img): img.resizable().scaledToFill()
            default: placeholder
            }
        }
        .aspectRatio(2 / 3, contentMode: .fit)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 2, bottomLeadingRadius: 2, bottomTrailingRadius: 5, topTrailingRadius: 5))
    }

    private var placeholder: some View {
        let h = Double(abs(book.title.hashValue % 360)) / 360
        return ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Color(hue: h, saturation: 0.55, brightness: 0.9), Color(hue: h, saturation: 0.7, brightness: 0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(book.title).font(.system(.headline, design: .serif)).foregroundStyle(.white).padding(10)
        }
    }
}

struct StarsView: View {
    var rating: Int
    var size: CGFloat = 12
    var onChange: ((Int) -> Void)? = nil
    var body: some View {
        HStack(spacing: 1) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: i <= rating ? "star.fill" : "star")
                    .font(.system(size: size))
                    .foregroundStyle(i <= rating ? Color.orange : Color.secondary.opacity(0.4))
                    .onTapGesture { onChange?(i == rating ? 0 : i) }
            }
        }
    }
}

struct FormatBadges: View {
    let formats: [String]
    var body: some View {
        HStack(spacing: 3) {
            ForEach(formats, id: \.self) { f in
                Text(f.uppercased()).font(.system(size: 9.5, weight: .semibold))
                    .padding(.horizontal, 5).padding(.vertical, 1.5)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            }
        }
    }
}

struct BookContextMenu: View {
    private var store: LibraryStore { LibraryStore.shared }
    let ids: Set<Int>
    var books: [Book] { store.books.filter { ids.contains($0.id) } }

    var body: some View {
        if !ids.isEmpty {
            Button("Leggi", systemImage: "book") { if let i = books.first?.id { store.openReader?(i) } }
            Button("Anteprima", systemImage: "eye") { if let b = books.first { store.preview(b) } }
            Button("Modifica metadati…", systemImage: "square.and.pencil") { store.selection = ids; store.showEdit = true }
            Button("Converti…", systemImage: "arrow.triangle.2.circlepath") { store.selection = ids; store.showConvert = true }
            Divider()
            Button("Invia a e-reader…", systemImage: "externaldrive") { store.selection = ids; store.devices = DeviceScanner.scan(); store.showSend = true }
            Button("Segna / deseleziona", systemImage: "bookmark") { store.toggleMark(Array(ids)) }
            Button("Mostra nel Finder", systemImage: "folder") { store.revealInFinder(books) }
            Menu("Valutazione", systemImage: "star") {
                ForEach(0...5, id: \.self) { n in Button(n == 0 ? "Nessuna" : String(repeating: "★", count: n)) { store.setRating(Array(ids), stars: n) } }
            }
            Divider()
            Button("Rimuovi…", systemImage: "trash", role: .destructive) { store.selection = ids; store.showDelete = true }
        }
    }
}

extension TableColumnCustomization<Book> {
    static func load() -> Self {
        guard let d = UserDefaults.standard.data(forKey: "tableColumns"), let v = try? JSONDecoder().decode(Self.self, from: d) else { return Self() }
        return v
    }
    func save() { UserDefaults.standard.set(try? JSONEncoder().encode(self), forKey: "tableColumns") }
}

struct BookTable: View {
    private var store: LibraryStore { LibraryStore.shared }
    @State private var custom = TableColumnCustomization<Book>.load()

    var body: some View {
        @Bindable var store = store
        Table(store.visible, selection: $store.selection, sortOrder: $store.sortOrder, columnCustomization: $custom) {
            firstColumns
            otherColumns
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .onChange(of: custom) { custom.save() }
        .contextMenu(forSelectionType: Int.self) { ids in BookContextMenu(ids: ids) } primaryAction: { ids in
            if let i = ids.first { store.openReader?(i) }
        }
        .onKeyPress(.space) {
            if let b = store.selectedBooks.first { store.preview(b); return .handled }
            return .ignored
        }
    }

    @TableColumnBuilder<Book, KeyPathComparator<Book>>
    private var firstColumns: some TableColumnContent<Book, KeyPathComparator<Book>> {
            TableColumn("") { b in
                CoverView(book: b).frame(width: 22, height: 33).shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
            }.width(32).customizationID("cover")
            TableColumn("Titolo", value: \.titleSort) { b in
                HStack(spacing: 5) {
                    if store.marked.contains(b.id) { Image(systemName: "bookmark.fill").foregroundStyle(.orange).imageScale(.small) }
                    Text(b.title).fontWeight(.medium)
                }
            }.width(min: 160, ideal: 260).customizationID("title")
            TableColumn("Autore", value: \.authorSort) { b in Text(b.authorText) }.width(min: 100, ideal: 170).customizationID("author")
            TableColumn("Serie", value: \.seriesSort) { b in Text(b.seriesLabel).foregroundStyle(.secondary) }.width(min: 80, ideal: 150).customizationID("series")
            TableColumn("Valutazione", value: \.rating) { b in StarsView(rating: b.rating) { store.setRating([b.id], stars: $0) } }.width(80).customizationID("rating")
            TableColumn("Formati") { b in FormatBadges(formats: b.formats) }.width(min: 70, ideal: 120).customizationID("formats")
    }

    @TableColumnBuilder<Book, KeyPathComparator<Book>>
    private var otherColumns: some TableColumnContent<Book, KeyPathComparator<Book>> {
            TableColumn("Editore", value: \.publisherSort) { b in Text(b.publisher).foregroundStyle(.secondary) }.width(min: 70, ideal: 110).customizationID("publisher")
            TableColumn("Anno", value: \.year) { b in Text(b.year > 0 ? String(b.year) : "").foregroundStyle(.secondary).monospacedDigit() }.width(50).customizationID("year")
            TableColumn("Aggiunto", value: \.added) { b in Text(b.added, format: .dateTime.day().month(.abbreviated).year()).foregroundStyle(.secondary) }.width(min: 80, ideal: 100).customizationID("added")
            TableColumn("Tag") { b in Text(b.tags.joined(separator: ", ")).foregroundStyle(.secondary) }.width(min: 80, ideal: 140).customizationID("tags").defaultVisibility(.hidden)
            TableColumn("Lingua") { b in Text(b.languageNames.joined(separator: ", ")).foregroundStyle(.secondary) }.width(70).customizationID("lang").defaultVisibility(.hidden)
            TableColumn("Dim.", value: \.size) { b in Text(ByteCountFormatter.string(fromByteCount: Int64(b.size), countStyle: .file)).foregroundStyle(.secondary).monospacedDigit() }.width(70).customizationID("size").defaultVisibility(.hidden)
    }
}

struct BookGrid: View {
    private var store: LibraryStore { LibraryStore.shared }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: store.coverSize, maximum: store.coverSize * 1.6), spacing: 22, alignment: .top)], spacing: 24) {
                ForEach(store.visible) { b in cell(b) }
            }
            .padding(22)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onTapGesture { store.selection = [] }
        .onKeyPress(.space) {
            if let b = store.selectedBooks.first { store.preview(b); return .handled }
            return .ignored
        }
    }

    private func cell(_ b: Book) -> some View {
        let sel = store.selection.contains(b.id)
        return VStack(spacing: 7) {
            CoverView(book: b)
                .shadow(color: .black.opacity(0.28), radius: 7, y: 4)
                .overlay(alignment: .topTrailing) {
                    if store.marked.contains(b.id) { Image(systemName: "bookmark.fill").foregroundStyle(.orange).padding(6).shadow(radius: 2) }
                }
            Text(b.title).font(.callout.weight(.semibold)).lineLimit(1)
            Text(b.authorText).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(9)
        .background(sel ? Color.accentColor.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 14))
        .overlay { if sel { RoundedRectangle(cornerRadius: 14).strokeBorder(Color.accentColor, lineWidth: 2) } }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { store.openReader?(b.id) }
        .onTapGesture {
            let f = NSEvent.modifierFlags
            if f.contains(.command) { if sel { store.selection.remove(b.id) } else { store.selection.insert(b.id) } }
            else if f.contains(.shift), let last = store.selection.first.flatMap({ s in store.visible.firstIndex { $0.id == s } }), let cur = store.visible.firstIndex(where: { $0.id == b.id }) {
                store.selection = Set(store.visible[min(last, cur)...max(last, cur)].map(\.id))
            } else { store.selection = [b.id] }
        }
        .contextMenu { BookContextMenu(ids: sel ? store.selection : [b.id]) }
    }
}
