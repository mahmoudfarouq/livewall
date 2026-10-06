import AppKit
import WebKit

/// Borderless panel that sits at desktop level on one screen.
final class WallpaperPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Web view that takes the first click instead of swallowing it to focus the window.
final class WallpaperWebView: WKWebView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The daemon: one panel + web view per screen, kept in sync with the display setup.
final class Wallpaper: NSObject, NSApplicationDelegate, WKNavigationDelegate {
    private var opts: Options
    private let url: URL
    private var windows: [CGDirectDisplayID: (panel: WallpaperPanel, web: WallpaperWebView)] = [:]
    private var signalSources: [DispatchSourceSignal] = []
    private var locked = false, asleep = false
    private var paused: Bool { locked || asleep }

    init(_ opts: Options) {
        guard let url = URL(string: opts.url) else { fail("bad url \(opts.url)") }
        self.opts = opts
        self.url = url
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        syncScreens()

        let nc = NotificationCenter.default
        nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            // macOS can post this in bursts; coalesce them into one sync.
            NSObject.cancelPreviousPerformRequests(withTarget: self as Any, selector: #selector(Wallpaper.screensChanged), object: nil)
            self?.perform(#selector(Wallpaper.screensChanged), with: nil, afterDelay: 0.3)
        }
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.asleep = true; self?.applyPause()
        }
        ws.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.asleep = false; self?.applyPause()
        }
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            self?.locked = true; self?.applyPause()
        }
        dnc.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            self?.locked = false; self?.applyPause()
        }

        onSignal(SIGTERM) { [weak self] in self?.shutdown() }
        onSignal(SIGINT) { [weak self] in self?.shutdown() }

        opts.pid = getpid()
        opts.started = Date()
        writeState(opts)
        log("started pid \(opts.pid) url \(url.absoluteString) screens \(windows.count)")
    }

    // MARK: screens

    @objc private func screensChanged() { syncScreens() }

    private func syncScreens() {
        let screens = opts.screen == "main" ? Array(NSScreen.screens.prefix(1)) : NSScreen.screens
        var live = Set<CGDirectDisplayID>()
        for screen in screens {
            let id = screen.displayID
            live.insert(id)
            if let existing = windows[id] {
                if existing.panel.frame != screen.frame { existing.panel.setFrame(screen.frame, display: true) }
            } else {
                windows[id] = makeWindow(for: screen)
            }
        }
        for id in windows.keys where !live.contains(id) {
            windows[id]?.panel.close()
            windows[id] = nil
        }
        log("screens: \(windows.count) window(s)")
    }

    private func makeWindow(for screen: NSScreen) -> (panel: WallpaperPanel, web: WallpaperWebView) {
        let panel = WallpaperPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                                   backing: .buffered, defer: false)
        panel.setFrame(screen.frame, display: false)
        panel.level = Self.desktopLevel
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.hasShadow = false
        panel.isOpaque = true
        panel.backgroundColor = .black // shows if the page is transparent or fails to load

        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.mediaTypesRequiringUserActionForPlayback = []
        // Autoplay is allowed, but the wallpaper never makes sound.
        config.userContentController.addUserScript(WKUserScript(
            source: "document.addEventListener('play', e => { e.target.muted = true }, true);",
            injectionTime: .atDocumentStart, forMainFrameOnly: false))

        let web = WallpaperWebView(frame: NSRect(origin: .zero, size: screen.frame.size), configuration: config)
        web.autoresizingMask = [.width, .height]
        web.underPageBackgroundColor = .black
        web.navigationDelegate = self
        panel.contentView = web
        load(web)
        if !paused { panel.orderFrontRegardless() }
        return (panel, web)
    }

    private func load(_ web: WKWebView) {
        if url.isFileURL {
            web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            web.load(URLRequest(url: url))
        }
    }

    static let desktopLevel = NSWindow.Level(Int(CGWindowLevelForKey(.desktopWindow)))

    // MARK: energy

    /// Ordering the windows out while the screen is locked or asleep makes WebKit treat the
    /// page as hidden, which stops requestAnimationFrame and throttles timers.
    private func applyPause() {
        log(paused ? "pausing (locked or asleep)" : "resuming")
        for w in windows.values {
            if paused { w.panel.orderOut(nil) } else { w.panel.orderFrontRegardless() }
        }
    }

    // MARK: lifecycle

    private func onSignal(_ sig: Int32, _ handler: @escaping () -> Void) {
        signal(sig, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
        source.setEventHandler(handler: handler)
        source.resume()
        signalSources.append(source)
    }

    private func shutdown() {
        log("stopping pid \(getpid())")
        if readState()?.pid == getpid() { clearState() }
        exit(0)
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        log("loaded \(webView.url?.absoluteString ?? "?")")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        log("load failed: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        log("load failed: \(error.localizedDescription)")
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        log("web content process terminated, reloading")
        load(webView)
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

enum Daemon {
    static func run(_ args: [String]) {
        let (flags, _) = parseFlags(args, valued: ["--url", "--key", "--screen"])
        guard let url = flags["--url"] else { fail("daemon needs --url") }
        var opts = Options(url: url)
        opts.key = flags["--key"] ?? opts.key
        opts.screen = flags["--screen"] ?? opts.screen

        setsid()                 // leave the terminal's session so closing it doesn't kill us
        signal(SIGHUP, SIG_IGN)

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory) // no Dock icon, not in the app switcher
        let delegate = Wallpaper(opts)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
