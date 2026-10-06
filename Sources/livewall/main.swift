import Foundation

enum CLI {
    static func set(_ args: [String]) {
        let (flags, given) = parseFlags(args, valued: ["--key", "--screen", "--fps"],
                                             boolean: ["--wallpaper-hash", "--no-wallpaper-hash", "--random"])
        var positional = given
        if flags["--random"] != nil {
            guard positional.isEmpty else { fail("--random takes no path or URL") }
            guard let pick = Presets.all().randomElement() else { fail("no presets to pick from") }
            positional = [pick.slug]
        }
        guard positional.count == 1 else { fail("set needs exactly one preset, path or URL (see livewall --help)") }
        let key = flags["--key"] ?? "option"
        guard Wallpaper.modifierFlags[key] != nil else { fail("--key must be option, control, command or fn") }
        let screen = flags["--screen"] ?? "all"
        guard ["all", "main"].contains(screen) else { fail("--screen must be all or main") }
        var fps: Int?
        if let f = flags["--fps"] {
            guard let n = Int(f), n > 0 else { fail("--fps must be a positive number") }
            fps = n
        }
        let url = resolve(positional[0], hash: flags["--no-wallpaper-hash"] == nil, fps: fps)

        stopRunning(quiet: true)
        let pid = spawnDaemon(["daemon", "--url", url.absoluteString, "--key", key, "--screen", screen])
        print("livewall: showing \(url.absoluteString) (pid \(pid))")
    }

    static func stop() {
        if !stopRunning(quiet: false) { print("livewall: not running") }
    }

    static func status() {
        guard let s = readState(), isAlive(s.pid) else {
            clearState()
            print("livewall: not running")
            exit(1)
        }
        let started = s.started.map { DateFormatter.localizedString(from: $0, dateStyle: .short, timeStyle: .short) } ?? "?"
        print("""
        running   pid \(s.pid), since \(started)
        url       \(s.url)
        key       hold \(s.key) to interact
        screens   \(s.screen)
        log       \(Paths.log.path)
        """)
    }

    static func reload() {
        guard let s = readState(), isAlive(s.pid) else { fail("not running") }
        kill(s.pid, SIGUSR1)
        print("livewall: reloading \(s.url)")
    }

    static let usage = """
    livewall: an HTML page or URL as your live desktop wallpaper.

    usage:
      livewall set <preset|path|url> [opts]  show a page on the desktop (replaces any running one)
      livewall set --random [opts]           show a random preset
      livewall presets                       list presets (alias: list)
      livewall stop                          remove it
      livewall status                        show what is running
      livewall reload                        reload the page(s)
      livewall --version
      livewall --help

    set options:
      --key option|control|command|fn   hold this key to click/drag/scroll the page (default: option)
      --screen all|main                 every screen, or only the menu-bar screen (default: all)
      --fps N                           append ?fps=N for pages that read it (livewall itself does not cap it)
      --wallpaper-hash                  append #wallpaper to local files (default)
      --no-wallpaper-hash               load local files without it

    Presets are <slug>.html files, searched in $LIVEWALL_PRESETS, ~/.local/share/livewall/presets,
    then presets/ in the repo when run from its .build folder.
    Files live in ~/Library/Application Support/livewall/ (state.json, livewall.pid, livewall.log).
    """
    /// Turns a path or URL into the URL the daemon loads.
    static func resolve(_ input: String, hash: Bool, fps: Int?) -> URL {
        var url: URL
        if let u = URL(string: input), let scheme = u.scheme?.lowercased(), ["http", "https", "file"].contains(scheme) {
            url = u
        } else {
            url = URL(fileURLWithPath: (input as NSString).expandingTildeInPath).standardizedFileURL
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
                if isDir.boolValue { url.appendPathComponent("index.html") }
            } else if !input.contains("/"), let preset = Presets.find(input) {
                url = preset
            } else {
                fail("no such file or preset: \(input) (see livewall presets)")
            }
        }
        guard var c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { fail("bad url \(input)") }
        if let fps { c.queryItems = (c.queryItems ?? []) + [URLQueryItem(name: "fps", value: String(fps))] }
        if hash, url.isFileURL, c.fragment == nil { c.fragment = "wallpaper" }
        return c.url ?? url
    }

    /// Re-executes this binary as a detached `daemon` and waits until it reports in.
    static func spawnDaemon(_ args: [String]) -> Int32 {
        Paths.ensureDir()
        if !FileManager.default.fileExists(atPath: Paths.log.path) {
            FileManager.default.createFile(atPath: Paths.log.path, contents: nil)
        }
        guard let logHandle = try? FileHandle(forWritingTo: Paths.log) else { fail("cannot open \(Paths.log.path)") }
        logHandle.seekToEndOfFile()

        let p = Process()
        p.executableURL = Bundle.main.executableURL
        p.arguments = args
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = logHandle
        p.standardError = logHandle
        do { try p.run() } catch { fail("cannot start daemon: \(error.localizedDescription)") }

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if readState()?.pid == p.processIdentifier { return p.processIdentifier }
            if !p.isRunning { fail("daemon exited early, see \(Paths.log.path)") }
            usleep(50_000)
        }
        fail("daemon did not report in after 5s, see \(Paths.log.path)")
    }

    /// Sends SIGTERM to the running daemon and waits for it to go. Returns whether one was running.
    @discardableResult
    static func stopRunning(quiet: Bool) -> Bool {
        guard let state = readState(), isAlive(state.pid) else {
            clearState()
            return false
        }
        kill(state.pid, SIGTERM)
        for _ in 0..<60 where isAlive(state.pid) { usleep(50_000) }
        if isAlive(state.pid) { kill(state.pid, SIGKILL) }
        clearState()
        if !quiet { print("livewall: stopped pid \(state.pid)") }
        return true
    }
}

let args = Array(CommandLine.arguments.dropFirst())
switch args.first {
case "set": CLI.set(Array(args.dropFirst()))
case "stop": CLI.stop()
case "presets", "list": Presets.list()
case "status": CLI.status()
case "reload": CLI.reload()
case "daemon": Daemon.run(Array(args.dropFirst())) // hidden: what `set` re-execs
case "-v", "--version", "version": print("livewall \(livewallVersion)")
case nil, "-h", "--help", "help": print(CLI.usage)
default: fail("unknown command '\(args[0])', see livewall --help")
}
