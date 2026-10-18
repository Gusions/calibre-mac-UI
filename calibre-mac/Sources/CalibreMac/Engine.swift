import Foundation
import Observation
import Darwin

struct ToolError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

final class OutputBox: @unchecked Sendable {
    private let lock = NSLock()
    private var s = ""
    func add(_ t: String) { lock.lock(); s += t; lock.unlock() }
    var value: String { lock.lock(); defer { lock.unlock() }; return s }
}

/// Gestisce il motore di Calibre in modalità headless: calibre-server per le letture,
/// calibredb / ebook-convert per le scritture. Nessuna GUI Qt viene mai avviata.
@Observable @MainActor
final class Engine {
    static let shared = Engine()

    var port = 0
    var libraryID = ""
    var libraryPath = ""
    var ready = false
    var starting = false
    var error: String?
    private var server: Process?

    var calibreDir: String {
        get { UserDefaults.standard.string(forKey: "calibreDir") ?? "/Applications/calibre.app/Contents/MacOS" }
        set { UserDefaults.standard.set(newValue, forKey: "calibreDir") }
    }
    func tool(_ name: String) -> String { calibreDir + "/" + name }
    var calibreInstalled: Bool { FileManager.default.isExecutableFile(atPath: tool("calibre-server")) }
    var baseURL: URL { URL(string: "http://127.0.0.1:\(port)")! }
    var remote: String { "http://127.0.0.1:\(port)/#\(libraryID)" }

    func start(libraryPath path: String) async {
        stop()
        ready = false; error = nil; starting = true; libraryPath = path
        defer { starting = false }
        guard calibreInstalled else { error = "Calibre non trovato in \(calibreDir). Installalo o indica il percorso nelle Impostazioni."; return }
        if !FileManager.default.fileExists(atPath: path + "/metadata.db") {
            _ = try? await run(tool("calibredb"), ["--with-library", path, "list", "-f", "title"])
        }
        Self.killStaleServers()
        try? await Task.sleep(nanoseconds: 700_000_000)
        port = Self.freePort()
        let p = Process()
        // Wrapper: il server termina anche se l'app si chiude in modo anomalo (crash, kill).
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "\"$0\" \"$@\" & SP=$!; while kill -0 $PPID 2>/dev/null && kill -0 $SP 2>/dev/null; do sleep 1; done; kill $SP 2>/dev/null",
                       tool("calibre-server"), "--port", "\(port)", "--listen-on", "127.0.0.1", "--enable-local-write", "--disable-use-bonjour", path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { self.error = "Impossibile avviare il server: \(error.localizedDescription)"; return }
        server = p
        for _ in 0..<80 {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if !p.isRunning { self.error = "Il server Calibre si è fermato. La libreria è aperta in un’altra applicazione?"; return }
            if let (d, _) = try? await URLSession.shared.data(from: baseURL.appending(path: "ajax/library-info")),
               let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
               let id = j["default_library"] as? String {
                libraryID = id; ready = true; return
            }
        }
        error = "Il server Calibre non risponde."
    }

    /// Server avviati da una precedente esecuzione (es. dopo un crash) che terrebbero bloccata la libreria.
    nonisolated static func killStaleServers() {
        let k = Process()
        k.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        k.arguments = ["-f", "calibre-server --port [0-9]+ --listen-on 127.0.0.1 --enable-local-write --disable-use-bonjour"]
        try? k.run(); k.waitUntilExit()
    }

    func stop() {
        if let s = server, s.isRunning { s.terminate() }
        server = nil; ready = false
    }

    nonisolated static func freePort() -> Int {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = 0
        _ = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &len) } }
        return Int(UInt16(bigEndian: addr.sin_port))
    }

    nonisolated func run(_ exe: String, _ args: [String], onLine: (@Sendable (String) -> Void)? = nil) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: exe)
            p.arguments = args
            let pipe = Pipe()
            p.standardOutput = pipe; p.standardError = pipe
            let box = OutputBox()
            pipe.fileHandleForReading.readabilityHandler = { h in
                let d = h.availableData
                if d.isEmpty { return }
                let t = String(decoding: d, as: UTF8.self)
                box.add(t)
                if let onLine { for l in t.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) { onLine(String(l)) } }
            }
            p.terminationHandler = { proc in
                pipe.fileHandleForReading.readabilityHandler = nil
                box.add(String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
                if proc.terminationStatus == 0 { cont.resume(returning: box.value) }
                else { cont.resume(throwing: ToolError(message: String(box.value.trimmingCharacters(in: .whitespacesAndNewlines).suffix(500)))) }
            }
            do { try p.run() } catch { cont.resume(throwing: error) }
        }
    }

    func calibredb(_ args: [String]) async throws -> String {
        try await run(tool("calibredb"), ["--with-library", remote] + args)
    }

    nonisolated func fetchBooks(base: URL, lib: String, ids: [Int]?) async throws -> [Book] {
        var c = URLComponents(url: base.appending(path: "ajax/books/\(lib)"), resolvingAgainstBaseURL: false)!
        c.queryItems = [.init(name: "ids", value: ids.map { $0.map(String.init).joined(separator: ",") } ?? "all"), .init(name: "category_urls", value: "false")]
        let (d, _) = try await URLSession.shared.data(from: c.url!)
        guard let j = try JSONSerialization.jsonObject(with: d) as? [String: Any] else { return [] }
        return j.values.compactMap { ($0 as? [String: Any]).flatMap(Book.init(json:)) }
    }

    func coverURL(_ b: Book, full: Bool = false) -> URL? {
        guard ready else { return nil }
        var c = URLComponents(url: baseURL.appending(path: full ? "get/cover/\(b.id)/\(libraryID)" : "get/thumb/\(b.id)/\(libraryID)"), resolvingAgainstBaseURL: false)
        var q = [URLQueryItem(name: "v", value: String(Int(b.modified.timeIntervalSince1970)))]
        if !full { q.append(.init(name: "sz", value: "360x540")) }
        c?.queryItems = q
        return c?.url
    }
}
