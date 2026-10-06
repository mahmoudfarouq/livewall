import Foundation

enum CLI {
    static func set(_ args: [String]) {
        let (flags, positional) = parseFlags(args, valued: ["--key", "--screen"],
                                             boolean: ["--wallpaper-hash", "--no-wallpaper-hash"])
        guard positional.count == 1 else { fail("usage: livewall set <path-or-url> [options]") }
        let key = flags["--key"] ?? "option"
        let screen = flags["--screen"] ?? "all"
        let hash = flags["--no-wallpaper-hash"] == nil
        let url = resolve(positional[0], hash: hash)

        stopRunning(quiet: true)
        let pid = spawnDaemon(["daemon", "--url", url.absoluteString, "--key", key, "--screen", screen])
        print("livewall: showing \(url.absoluteString) (pid \(pid))")
    }

    static func stop() {
        if !stopRunning(quiet: false) { print("livewall: not running") }
    }

    /// Turns a path or URL into the URL the daemon loads.
    static func resolve(_ input: String, hash: Bool) -> URL {
        var url: URL
        if let u = URL(string: input), let scheme = u.scheme?.lowercased(), ["http", "https", "file"].contains(scheme) {
            url = u
        } else {
            url = URL(fileURLWithPath: (input as NSString).expandingTildeInPath).standardizedFileURL
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else {
                fail("no such file: \(url.path)")
            }
            if isDir.boolValue { url.appendPathComponent("index.html") }
        }
        if hash, url.isFileURL, url.fragment == nil, let withHash = URL(string: url.absoluteString + "#wallpaper") {
            url = withHash
        }
        return url
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
case "daemon": Daemon.run(Array(args.dropFirst()))
default: print("usage: livewall set <path-or-url> | stop")
}
