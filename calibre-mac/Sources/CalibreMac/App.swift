import SwiftUI
import AppKit

@main
struct CalibreMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = LibraryStore.shared

    var body: some Scene {
        Window("Calibre", id: "main") {
            ContentView()
                .environment(store)
                .frame(minWidth: 980, minHeight: 620)
        }
        .defaultSize(width: 1360, height: 860)
        .windowToolbarStyle(.unified)
        .commands { AppCommands(store: store) }

        WindowGroup("Lettura", id: "reader", for: Int.self) { $id in
            if let id { ReaderView(bookID: id).environment(store) }
        }
        .defaultSize(width: 940, height: 840)

        Settings { SettingsView().environment(store) }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { Engine.shared.stop() }
}

struct AppCommands: Commands {
    var store: LibraryStore

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Aggiungi libri…") { store.showImporter = true }.keyboardShortcut("o")
            Button("Aggiungi libro vuoto") { store.addEmpty() }
            Divider()
            Button("Apri libreria…") { LibraryPicker.open() }.keyboardShortcut("o", modifiers: [.command, .shift])
            Button("Nuova libreria…") { LibraryPicker.create() }
            Menu("Librerie recenti") {
                ForEach(store.recentLibraries, id: \.self) { p in
                    Button((p as NSString).lastPathComponent) { Task { await store.openLibrary(p) } }
                }
            }
        }
        CommandMenu("Libro") {
            Button("Modifica metadati…") { store.showEdit = true }.keyboardShortcut("e").disabled(store.selection.isEmpty)
            Button("Converti…") { store.showConvert = true }.keyboardShortcut("k", modifiers: [.command, .shift]).disabled(store.selection.isEmpty)
            Button("Leggi") { if let id = store.selection.first { store.openReader?(id) } }.keyboardShortcut(.return, modifiers: .command).disabled(store.selection.isEmpty)
            Button("Invia a e-reader…") { store.devices = DeviceScanner.scan(); store.showSend = true }.keyboardShortcut("d", modifiers: [.command, .shift]).disabled(store.selection.isEmpty)
            Button("Anteprima") { if let b = store.selectedBooks.first { store.preview(b) } }.keyboardShortcut("y").disabled(store.selection.isEmpty)
            Divider()
            Button("Segna / deseleziona") { store.toggleMark(Array(store.selection)) }.keyboardShortcut("m").disabled(store.selection.isEmpty)
            Button("Mostra nel Finder") { store.revealInFinder(store.selectedBooks) }.keyboardShortcut("r", modifiers: [.command, .shift]).disabled(store.selection.isEmpty)
            Button("Libro a caso") { store.randomBook() }.keyboardShortcut("r", modifiers: [.command, .option])
            Divider()
            Button("Rimuovi…") { store.showDelete = true }.keyboardShortcut(.delete).disabled(store.selection.isEmpty)
        }
        CommandGroup(after: .sidebar) {
            Button("Elenco") { store.viewMode = .list }.keyboardShortcut("1")
            Button("Griglia") { store.viewMode = .grid }.keyboardShortcut("2")
            Divider()
            Button(store.showInspector ? "Nascondi dettagli" : "Mostra dettagli") { store.showInspector.toggle() }.keyboardShortcut("i", modifiers: [.command, .option])
        }
    }
}

enum LibraryPicker {
    @MainActor static func open() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false
        p.message = "Scegli la cartella della libreria Calibre"
        p.prompt = "Apri"
        if p.runModal() == .OK, let u = p.url { Task { await LibraryStore.shared.openLibrary(u.path) } }
    }
    @MainActor static func create() {
        let p = NSSavePanel()
        p.nameFieldStringValue = "Calibre Library"
        p.message = "Scegli dove creare la nuova libreria"
        p.prompt = "Crea"
        if p.runModal() == .OK, let u = p.url {
            try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
            Task { await LibraryStore.shared.openLibrary(u.path) }
        }
    }
}
