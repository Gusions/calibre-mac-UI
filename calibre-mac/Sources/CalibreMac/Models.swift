import Foundation

struct Book: Identifiable, Hashable, Sendable {
    let id: Int
    var title: String
    var authors: [String]
    var authorSort: String
    var titleSort: String
    var series: String
    var seriesIndex: Double
    var publisher: String
    var tags: [String]
    var languages: [String]
    var rating: Int
    var comments: String
    var formats: [String]
    var formatPaths: [String: String]
    var size: Int
    var added: Date
    var pubdate: Date?
    var modified: Date
    var identifiers: [String: String]

    static func == (a: Book, b: Book) -> Bool { a.id == b.id && a.modified == b.modified && a.rating == b.rating }
    func hash(into h: inout Hasher) { h.combine(id) }

    var authorText: String { authors.joined(separator: ", ") }
    var seriesLabel: String {
        guard !series.isEmpty else { return "" }
        guard seriesIndex > 0 else { return series }
        let n = seriesIndex == seriesIndex.rounded() ? String(Int(seriesIndex)) : String(seriesIndex)
        return "\(series) #\(n)"
    }
    var year: Int { pubdate.map { Calendar.current.component(.year, from: $0) } ?? 0 }
    var seriesSort: String { series.lowercased() }
    var publisherSort: String { publisher.lowercased() }
    var plainComments: String {
        comments.replacingOccurrences(of: "<br\\s*/?>|</p>|</div>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    var languageNames: [String] {
        languages.map { Locale.current.localizedString(forLanguageCode: $0)?.capitalized ?? $0 }
    }
    var haystack: String {
        ([title, authorText, series, publisher, plainComments] + tags + formats).joined(separator: " ").lowercased()
    }
    var bestPath: String? {
        for f in ["epub", "azw3", "mobi", "kepub", "pdf", "docx", "fb2", "txt", "html"] { if let p = formatPaths[f] { return p } }
        return formatPaths.values.first
    }

    init?(json j: [String: Any]) {
        guard let id = j["application_id"] as? Int else { return nil }
        func str(_ k: String) -> String { (j[k] as? String) ?? "" }
        func arr(_ k: String) -> [String] { (j[k] as? [String]) ?? [] }
        self.id = id
        title = str("title")
        authors = arr("authors")
        authorSort = str("author_sort").lowercased()
        titleSort = (str("title_sort").isEmpty ? str("title") : str("title_sort")).lowercased()
        series = str("series")
        seriesIndex = (j["series_index"] as? Double) ?? 0
        publisher = str("publisher")
        tags = arr("tags")
        languages = arr("languages")
        rating = Int(((j["rating"] as? Double) ?? 0).rounded())
        comments = str("comments")
        formats = arr("formats")
        var paths: [String: String] = [:]
        var size = 0
        for (k, v) in (j["format_metadata"] as? [String: Any]) ?? [:] {
            if let m = v as? [String: Any] {
                if let p = m["path"] as? String { paths[k.lowercased()] = p }
                size += (m["size"] as? Int) ?? 0
            }
        }
        formatPaths = paths
        self.size = size
        added = Book.date(str("timestamp")) ?? .distantPast
        let pd = Book.date(str("pubdate"))
        pubdate = (pd != nil && Calendar.current.component(.year, from: pd!) > 1900) ? pd : nil
        modified = Book.date(str("last_modified")) ?? .distantPast
        identifiers = (j["identifiers"] as? [String: String]) ?? [:]
    }

    private static let iso1: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f }()
    private static let iso2: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }()
    static func date(_ s: String) -> Date? { iso1.date(from: s) ?? iso2.date(from: s) }
}

enum Kind: String, CaseIterable, Hashable, Sendable {
    case author, series, tag, publisher, format, rating, language
    var title: String {
        switch self {
        case .author: "Autori"; case .series: "Serie"; case .tag: "Tag"; case .publisher: "Editori"
        case .format: "Formati"; case .rating: "Valutazioni"; case .language: "Lingue"
        }
    }
    var icon: String {
        switch self {
        case .author: "person"; case .series: "books.vertical"; case .tag: "tag"; case .publisher: "building.2"
        case .format: "doc"; case .rating: "star"; case .language: "globe"
        }
    }
    func values(of b: Book) -> [String] {
        switch self {
        case .author: b.authors
        case .series: b.series.isEmpty ? [] : [b.series]
        case .tag: b.tags
        case .publisher: b.publisher.isEmpty ? [] : [b.publisher]
        case .format: b.formats.map { $0.uppercased() }
        case .rating: b.rating > 0 ? [String(b.rating)] : []
        case .language: b.languageNames
        }
    }
}

enum Smart: String, CaseIterable, Hashable, Sendable {
    case all, recent, marked, top
    var title: String { switch self { case .all: "Tutti i libri"; case .recent: "Aggiunti di recente"; case .marked: "Segnati"; case .top: "Cinque stelle" } }
    var icon: String { switch self { case .all: "books.vertical"; case .recent: "clock"; case .marked: "bookmark"; case .top: "star" } }
}

enum SideItem: Hashable {
    case smart(Smart)
    case saved(UUID)
    case tag(Kind, String)
}

struct SavedSearch: Codable, Identifiable, Hashable { var id = UUID(); var name: String; var query: String }
struct CategoryItem: Identifiable, Hashable { var kind: Kind; var name: String; var count: Int; var id: String { kind.rawValue + "|" + name } }
struct TagKey: Hashable { var kind: Kind; var value: String }

struct Job: Identifiable {
    enum State { case running, done, failed }
    let id = UUID()
    var title: String
    var progress: Double?
    var state: State = .running
    var message = ""
}

struct Query {
    var terms: [String] = []
    var fields: [(String, String)] = []
    init(_ s: String) {
        var cur = "", quoted = false
        var tokens: [String] = []
        for c in s {
            if c == "\"" { quoted.toggle(); cur.append(c) }
            else if c == " " && !quoted { if !cur.isEmpty { tokens.append(cur); cur = "" } }
            else { cur.append(c) }
        }
        if !cur.isEmpty { tokens.append(cur) }
        let keys = ["autore", "author", "titolo", "title", "serie", "series", "tag", "tags", "editore", "publisher", "formato", "format", "rating", "valutazione", "lingua", "language"]
        for t in tokens {
            let t = t.replacingOccurrences(of: "\"", with: "").lowercased()
            if let i = t.firstIndex(of: ":"), keys.contains(String(t[..<i])) {
                fields.append((String(t[..<i]), String(t[t.index(after: i)...])))
            } else { terms.append(t) }
        }
    }
    var isEmpty: Bool { terms.isEmpty && fields.isEmpty }
    func matches(_ b: Book) -> Bool {
        for (k, v) in fields {
            let ok: Bool
            switch k {
            case "autore", "author": ok = b.authorText.lowercased().contains(v)
            case "titolo", "title": ok = b.title.lowercased().contains(v)
            case "serie", "series": ok = v.isEmpty || v == "false" ? b.series.isEmpty : b.series.lowercased().contains(v)
            case "tag", "tags": ok = v.isEmpty || v == "false" ? b.tags.isEmpty : b.tags.contains { $0.lowercased().contains(v) }
            case "editore", "publisher": ok = b.publisher.lowercased().contains(v)
            case "formato", "format": ok = b.formats.contains { $0.lowercased() == v }
            case "rating", "valutazione": ok = String(b.rating) == v
            case "lingua", "language": ok = b.languageNames.contains { $0.lowercased().contains(v) } || b.languages.contains(v)
            default: ok = true
            }
            if !ok { return false }
        }
        let h = b.haystack
        return terms.allSatisfy { h.contains($0) }
    }
}
