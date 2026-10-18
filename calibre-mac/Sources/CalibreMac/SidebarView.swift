import SwiftUI

struct SidebarView: View {
    private var store: LibraryStore { LibraryStore.shared }
    @State private var filter = ""
    @State private var expanded: Set<Kind> = [.author, .tag]
    @State private var renaming: TagKey?
    @State private var newName = ""
    @State private var removing: TagKey?

    var body: some View {
        @Bindable var store = store
        List(selection: $store.sidebar) {
            Section("Libreria") {
                ForEach(Smart.allCases, id: \.self) { s in
                    Label(s.title, systemImage: s.icon)
                        .badge(count(s))
                        .tag(SideItem.smart(s))
                }
            }
            if !store.savedSearches.isEmpty {
                Section("Ricerche salvate") {
                    ForEach(store.savedSearches) { s in
                        Label(s.name, systemImage: "magnifyingglass")
                            .tag(SideItem.saved(s.id))
                            .contextMenu { Button("Elimina", role: .destructive) { store.savedSearches.removeAll { $0.id == s.id }; store.sidebar.remove(.saved(s.id)) } }
                    }
                }
            }
            Section("Esplora") {
                ForEach(Kind.allCases, id: \.self) { k in
                    let items = filtered(k)
                    if filter.isEmpty || !items.isEmpty {
                        DisclosureGroup(isExpanded: Binding(get: { !filter.isEmpty || expanded.contains(k) }, set: { if $0 { expanded.insert(k) } else { expanded.remove(k) } })) {
                            ForEach(items) { it in row(it) }
                        } label: {
                            Label(k.title, systemImage: k.icon).badge(items.count)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, spacing: 0) {
            Button { LibraryPicker.open() } label: {
                HStack(spacing: 9) {
                    Image(systemName: "books.vertical.fill").foregroundStyle(.white).frame(width: 28, height: 28)
                        .background(LinearGradient(colors: [.indigo, .blue], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 7))
                    VStack(alignment: .leading, spacing: 0) {
                        Text((store.engine.libraryPath as NSString).lastPathComponent).fontWeight(.semibold).lineLimit(1)
                        Text("\(store.books.count) libri").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(.secondary)
                }
                .padding(8).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8).padding(.top, 6)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease").foregroundStyle(.secondary)
                TextField("Filtra categorie", text: $filter).textFieldStyle(.plain)
                Button { store.sidebarByCount.toggle() } label: { Image(systemName: store.sidebarByCount ? "number" : "textformat.abc") }
                    .buttonStyle(.plain).help("Ordina per nome o per numero di libri")
                Picker("", selection: $store.matchAll) { Text("E").tag(true); Text("O").tag(false) }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 62).help("Più voci: tutte (E) o almeno una (O)")
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .overlay(alignment: .top) { Divider() }
        }
        .alert("Rinomina “\(renaming?.value ?? "")”", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Nuovo nome", text: $newName)
            Button("Rinomina") { if let r = renaming, !newName.isEmpty { store.edit(kind: r.kind, value: r.value, to: newName) }; renaming = nil }
            Button("Annulla", role: .cancel) { renaming = nil }
        } message: { Text("Vale per tutti i libri che usano questa voce.") }
        .confirmationDialog("Rimuovere “\(removing?.value ?? "")” da tutti i libri?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button("Rimuovi", role: .destructive) { if let r = removing { store.edit(kind: r.kind, value: r.value, to: nil) }; removing = nil }
            Button("Annulla", role: .cancel) { removing = nil }
        }
    }

    private func filtered(_ k: Kind) -> [CategoryItem] {
        let l = store.items(k)
        let q = filter.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? l : l.filter { $0.name.lowercased().contains(q) }
    }

    private func count(_ s: Smart) -> Int {
        switch s {
        case .all: store.books.count
        case .recent: store.books.filter { $0.added > Date().addingTimeInterval(-30 * 86400) }.count
        case .marked: store.books.filter { store.marked.contains($0.id) }.count
        case .top: store.books.filter { $0.rating >= 5 }.count
        }
    }

    @ViewBuilder private func row(_ it: CategoryItem) -> some View {
        let key = TagKey(kind: it.kind, value: it.name)
        let isEx = store.excluded.contains(key)
        Group {
            if it.kind == .rating { Text(String(repeating: "★", count: Int(it.name) ?? 0)).foregroundStyle(.orange) }
            else { Text(it.name).strikethrough(isEx).foregroundStyle(isEx ? .red : .primary) }
        }
        .badge(it.count)
        .tag(SideItem.tag(it.kind, it.name))
        .contextMenu {
            Button(isEx ? "Non escludere" : "Escludi (NON)", systemImage: "minus.circle") {
                if isEx { store.excluded.remove(key) } else { store.excluded.insert(key); store.sidebar.remove(.tag(it.kind, it.name)) }
            }
            if [.tag, .author, .series, .publisher].contains(it.kind) {
                Divider()
                Button("Rinomina…", systemImage: "pencil") { newName = it.name; renaming = key }
                if it.kind == .tag || it.kind == .author {
                    Menu("Unisci in", systemImage: "arrow.triangle.merge") {
                        ForEach(store.items(it.kind).filter { $0.name != it.name }.prefix(40)) { o in
                            Button(o.name) { store.edit(kind: it.kind, value: it.name, to: o.name) }
                        }
                    }
                }
                if it.kind != .author { Button("Rimuovi da tutti i libri…", systemImage: "trash", role: .destructive) { removing = key } }
            }
        }
    }
}
