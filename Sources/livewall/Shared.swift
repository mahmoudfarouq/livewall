import Foundation

/// Files the CLI and the daemon share, all under ~/Library/Application Support/livewall/.
enum Paths {
    static let dir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/livewall", isDirectory: true)
    static let pid = dir.appendingPathComponent("livewall.pid")
    static let state = dir.appendingPathComponent("state.json")
    static let log = dir.appendingPathComponent("livewall.log")

    static func ensureDir() {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
}

/// What the daemon shows. Written to state.json by the daemon once it is up.
struct Options: Codable {
    var url: String
    var key = "option"
    var screen = "all"
    var pid: Int32 = 0
    var started: Date?
}

func log(_ message: String) {
    let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
    FileHandle.standardError.write(Data(line.utf8))
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("livewall: \(message)\n".utf8))
    exit(1)
}

func isAlive(_ pid: Int32) -> Bool { pid > 0 && kill(pid, 0) == 0 }

func readState() -> Options? {
    guard let data = try? Data(contentsOf: Paths.state) else { return nil }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try? decoder.decode(Options.self, from: data)
}

func writeState(_ o: Options) {
    Paths.ensureDir()
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try? encoder.encode(o).write(to: Paths.state, options: .atomic)
    try? "\(o.pid)\n".write(to: Paths.pid, atomically: true, encoding: .utf8)
}

func clearState() {
    try? FileManager.default.removeItem(at: Paths.state)
    try? FileManager.default.removeItem(at: Paths.pid)
}

/// Parses `--flag value` pairs plus boolean flags; anything else is positional.
func parseFlags(_ args: [String], valued: Set<String>, boolean: Set<String> = [])
    -> (flags: [String: String], positional: [String]) {
    var flags: [String: String] = [:], positional: [String] = []
    var i = 0
    while i < args.count {
        let a = args[i]
        if valued.contains(a) {
            guard i + 1 < args.count else { fail("missing value for \(a)") }
            flags[a] = args[i + 1]
            i += 1
        } else if boolean.contains(a) {
            flags[a] = ""
        } else if a.hasPrefix("--") {
            fail("unknown option \(a)")
        } else {
            positional.append(a)
        }
        i += 1
    }
    return (flags, positional)
}
