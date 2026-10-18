import Foundation

/// Tipi di e-reader riconosciuti e relative preferenze di formato.
enum DeviceKind: String, Sendable {
    case kindle, kobo, generic

    var title: String {
        switch self { case .kindle: "Kindle"; case .kobo: "Kobo"; case .generic: "Volume rimovibile" }
    }
    var icon: String {
        switch self { case .kindle, .kobo: "book.closed"; case .generic: "externaldrive" }
    }
    /// Formati accettati dal dispositivo, in ordine di preferenza.
    var formats: [String] {
        switch self {
        case .kindle: ["azw3", "mobi", "pdf", "txt"]
        case .kobo: ["kepub", "epub", "pdf"]
        case .generic: ["epub", "pdf", "mobi", "azw3"]
        }
    }
    /// Formato in cui convertire quando il libro non ne ha uno compatibile.
    var convertTarget: String {
        switch self { case .kindle: "azw3"; case .kobo, .generic: "epub" }
    }
    var profile: String {
        switch self { case .kindle: "kindle"; case .kobo: "kobo"; case .generic: "default" }
    }
}

struct Device: Identifiable, Hashable, Sendable {
    var url: URL
    var name: String
    var kind: DeviceKind
    var free: Int64?
    var total: Int64?
    var id: String { url.path }

    /// Cartella di destinazione predefinita per i libri.
    var defaultDir: URL {
        let fm = FileManager.default
        switch kind {
        case .kindle: return url.appendingPathComponent("documents")
        case .kobo: return url
        case .generic:
            for n in ["Books", "eBooks", "Libri", "Documents"] where fm.fileExists(atPath: url.appendingPathComponent(n).path) {
                return url.appendingPathComponent(n)
            }
            return url
        }
    }
}

/// Cosa fare per inviare un libro: copiare un formato esistente o convertirlo.
struct SendPlan: Equatable, Sendable {
    var source: String
    var ext: String
    var needsConversion: Bool
}

enum DeviceScanner {
    /// Volumi montati che somigliano a un e-reader.
    static func scan() -> [Device] {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeIsEjectableKey, .volumeIsRemovableKey, .volumeIsInternalKey,
                                      .volumeIsLocalKey, .volumeIsReadOnlyKey, .volumeAvailableCapacityKey, .volumeTotalCapacityKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        let fm = FileManager.default
        return urls.compactMap { u -> Device? in
            guard u.path.hasPrefix("/Volumes/"), let v = try? u.resourceValues(forKeys: Set(keys)) else { return nil }
            guard v.volumeIsLocal == true, v.volumeIsReadOnly != true else { return nil }
            let name = v.volumeName ?? u.lastPathComponent
            let isKobo = fm.fileExists(atPath: u.appendingPathComponent(".kobo").path)
            let isKindle = name.lowercased().contains("kindle")
                || (fm.fileExists(atPath: u.appendingPathComponent("documents").path) && fm.fileExists(atPath: u.appendingPathComponent("system").path))
            let removable = (v.volumeIsEjectable == true || v.volumeIsRemovable == true) && v.volumeIsInternal != true
            guard isKobo || isKindle || removable else { return nil }
            return Device(url: u, name: name, kind: isKobo ? .kobo : (isKindle ? .kindle : .generic),
                          free: v.volumeAvailableCapacity.map(Int64.init), total: v.volumeTotalCapacity.map(Int64.init))
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Sceglie il file da copiare; se nessun formato è compatibile indica la conversione dal miglior sorgente.
    static func plan(formatPaths: [String: String], kind: DeviceKind) -> SendPlan? {
        for f in kind.formats { if let p = formatPaths[f] { return SendPlan(source: p, ext: f, needsConversion: false) } }
        let order = ["epub", "azw3", "mobi", "kepub", "docx", "fb2", "txt", "html", "pdf"]
        for f in order { if let p = formatPaths[f] { return SendPlan(source: p, ext: kind.convertTarget, needsConversion: true) } }
        if let p = formatPaths.values.first { return SendPlan(source: p, ext: kind.convertTarget, needsConversion: true) }
        return nil
    }

    static func fileName(title: String, author: String, ext: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters)
        func clean(_ s: String) -> String { s.components(separatedBy: bad).joined(separator: " ").trimmingCharacters(in: .whitespaces) }
        var base = clean(title)
        if !author.isEmpty { base += " - " + clean(author) }
        return String(base.prefix(120)) + "." + ext
    }
}
