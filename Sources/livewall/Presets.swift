import Foundation

/// Bundled pages, found as <slug>.html in the first preset folder that has them.
enum Presets {
    /// Search order: $LIVEWALL_PRESETS, ~/.local/share/livewall/presets, then presets/
    /// in the repo when running from its .build folder.
    static var dirs: [URL] {
        var dirs: [URL] = []
        if let env = ProcessInfo.processInfo.environment["LIVEWALL_PRESETS"], !env.isEmpty {
            dirs.append(URL(fileURLWithPath: (env as NSString).expandingTildeInPath, isDirectory: true))
        }
        dirs.append(FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/livewall/presets", isDirectory: true))
        if let repo = repoRoot { dirs.append(repo.appendingPathComponent("presets", isDirectory: true)) }
        return dirs
    }

    /// Walks up from the real executable (.build/<triple>/release/livewall) to the folder with Package.swift.
    private static var repoRoot: URL? {
        guard var dir = Bundle.main.executableURL?.resolvingSymlinksInPath().deletingLastPathComponent() else { return nil }
        for _ in 0..<5 {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("Package.swift").path) { return dir }
            dir.deleteLastPathComponent()
        }
        return nil
    }

    /// slug -> file, earlier folders winning.
    static func all() -> [(slug: String, file: URL)] {
        var found: [String: URL] = [:]
        for dir in dirs.reversed() {
            let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            for f in files where f.pathExtension == "html" { found[f.deletingPathExtension().lastPathComponent] = f }
        }
        return found.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    static func find(_ slug: String) -> URL? { all().first { $0.slug == slug }?.file }

    static func title(of file: URL) -> String {
        guard let html = try? String(contentsOf: file, encoding: .utf8),
              let r = html.range(of: "(?is)<title[^>]*>(.*?)</title>", options: .regularExpression) else { return "" }
        return String(html[r]).replacingOccurrences(of: "(?is)</?title[^>]*>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func list() {
        let presets = all()
        guard !presets.isEmpty else {
            fail("no presets found in \(dirs.map(\.path).joined(separator: ", "))")
        }
        let width = presets.map(\.slug.count).max() ?? 0
        for p in presets {
            print(p.slug.padding(toLength: width, withPad: " ", startingAt: 0) + "  " + title(of: p.file))
        }
    }
}
