import SwiftUI
import AppKit

extension LibraryStore {
    /// Osserva montaggio/smontaggio dei volumi per aggiornare l'elenco degli e-reader.
    func startDeviceMonitor() {
        guard !monitoring else { return }
        monitoring = true
        devices = DeviceScanner.scan()
        let nc = NSWorkspace.shared.notificationCenter
        for n in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didRenameVolumeNotification] {
            nc.addObserver(forName: n, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    self?.devices = DeviceScanner.scan()
                }
            }
        }
    }

    func sendToDevice(_ list: [Book], device: Device, dir: URL, eject: Bool) {
        guard !list.isEmpty else { return }
        runJob("Invio a \(device.name) (\(list.count))") { [engine] progress in
            let fm = FileManager.default
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            var sent = 0, failed: [String] = []
            for (i, b) in list.enumerated() {
                guard let plan = DeviceScanner.plan(formatPaths: b.formatPaths, kind: device.kind) else { failed.append(b.title); continue }
                let dest = dir.appendingPathComponent(DeviceScanner.fileName(title: b.title, author: b.authors.first ?? "", ext: plan.ext))
                var src = plan.source
                var tmp: URL?
                if plan.needsConversion {
                    let t = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                    try fm.createDirectory(at: t, withIntermediateDirectories: true)
                    tmp = t
                    let out = t.appendingPathComponent("book.\(plan.ext)").path
                    var args = [src, out]
                    if device.kind.profile != "default" { args += ["--output-profile", device.kind.profile] }
                    do { _ = try await engine.run(await engine.tool("ebook-convert"), args) } catch { failed.append(b.title); try? fm.removeItem(at: t); continue }
                    src = out
                }
                defer { if let tmp { try? fm.removeItem(at: tmp) } }
                do {
                    if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
                    try fm.copyItem(atPath: src, toPath: dest.path)
                    sent += 1
                } catch { failed.append(b.title) }
                progress(Double(i + 1) / Double(list.count))
            }
            await MainActor.run {
                self.say(failed.isEmpty ? "\(sent) libri inviati a \(device.name)" : "\(sent) inviati, \(failed.count) non riusciti: \(failed.prefix(2).joined(separator: ", "))")
            }
            if eject && failed.isEmpty {
                await MainActor.run { _ = try? NSWorkspace.shared.unmountAndEjectDevice(at: device.url) }
            }
            if !failed.isEmpty { throw ToolError(message: "Non inviati: " + failed.joined(separator: ", ")) }
        }
    }
}

struct SendToDeviceView: View {
    private var store: LibraryStore { LibraryStore.shared }
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Device.ID?
    @State private var customDir: URL?
    @State private var eject = true

    private var device: Device? { store.devices.first { $0.id == selected } ?? store.devices.first }
    private var books: [Book] { store.selectedBooks }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Invia a e-reader").font(.headline)
            Text(books.count == 1 ? (books.first?.title ?? "") : "\(books.count) libri").foregroundStyle(.secondary).lineLimit(1)

            if store.devices.isEmpty {
                ContentUnavailableView {
                    Label("Nessun e-reader trovato", systemImage: "externaldrive.badge.questionmark")
                } description: {
                    Text("Collega il Kindle o il Kobo via USB: viene riconosciuto appena compare in Finder. Altri lettori USB a memoria di massa appaiono come volumi rimovibili.")
                } actions: {
                    Button("Cerca di nuovo") { store.devices = DeviceScanner.scan() }
                }.frame(height: 190)
            } else {
                List(store.devices, selection: Binding(get: { device?.id }, set: { selected = $0; customDir = nil })) { d in
                    HStack(spacing: 10) {
                        Image(systemName: d.kind.icon).font(.title3).frame(width: 26).foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(d.name).fontWeight(.medium)
                            Text(subtitle(d)).font(.caption).foregroundStyle(.secondary)
                        }
                    }.tag(d.id)
                }
                .frame(height: min(190, CGFloat(store.devices.count) * 46 + 12))
                .listStyle(.bordered)

                if let d = device {
                    Form {
                        LabeledContent("Cartella") {
                            HStack {
                                Text(((customDir ?? d.defaultDir).path as NSString).abbreviatingWithTildeInPath).lineLimit(1).truncationMode(.middle)
                                Button("Cambia…") { chooseDir(d) }
                            }
                        }
                        LabeledContent("Formato") {
                            Text(formatNote(d)).foregroundStyle(.secondary)
                        }
                        Toggle("Espelli al termine", isOn: $eject)
                    }.formStyle(.grouped)
                }
            }

            HStack {
                Spacer()
                Button("Annulla", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Invia") {
                    if let d = device { store.sendToDevice(books, device: d, dir: customDir ?? d.defaultDir, eject: eject) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).disabled(device == nil)
            }
        }
        .padding(20).frame(width: 480)
        .onAppear { store.devices = DeviceScanner.scan() }
    }

    private func subtitle(_ d: Device) -> String {
        var parts = [d.kind.title]
        if let f = d.free, let t = d.total {
            parts.append("\(ByteCountFormatter.string(fromByteCount: f, countStyle: .file)) liberi di \(ByteCountFormatter.string(fromByteCount: t, countStyle: .file))")
        }
        return parts.joined(separator: " · ")
    }

    private func formatNote(_ d: Device) -> String {
        let plans = books.map { DeviceScanner.plan(formatPaths: $0.formatPaths, kind: d.kind) }
        let conv = plans.compactMap { $0 }.filter(\.needsConversion).count
        let nofile = plans.filter { $0 == nil }.count
        var s = d.kind.formats.prefix(3).map { $0.uppercased() }.joined(separator: " / ")
        if conv > 0 { s += " · \(conv) da convertire in \(d.kind.convertTarget.uppercased())" }
        if nofile > 0 { s += " · \(nofile) senza file" }
        return s
    }

    private func chooseDir(_ d: Device) {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true
        p.directoryURL = d.url; p.prompt = "Scegli"
        if p.runModal() == .OK { customDir = p.url }
    }
}
