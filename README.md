# livewall

A tiny macOS command-line tool that shows an HTML file or URL as your live desktop
wallpaper, on every screen. Hold a modifier key (Option by default) to click, drag and
scroll the page; let go and it is wallpaper again. No app, no menu bar item, no
permissions prompt. Swift + AppKit + WebKit, macOS 13+.

```sh
livewall set ~/Documents/personal/night-city/index.html
```

## Build and install

```sh
swift build -c release
mkdir -p ~/.local/bin
cp .build/release/livewall ~/.local/bin/   # make sure ~/.local/bin is on your PATH
```

To start it at login, add `livewall set …` to your shell profile or a login item yourself;
livewall does not install anything.

## Commands

| command | what it does |
| --- | --- |
| `livewall set <path-or-url> [options]` | starts the wallpaper daemon (replacing any running one) and returns |
| `livewall stop` | stops it |
| `livewall status` | url, key, screens, pid and log path of the running daemon |
| `livewall reload` | reloads the page on every screen (e.g. after editing the file) |
| `livewall --help` | usage |

Options for `set`:

- `--key option|control|command|fn` – the key to hold for interaction (default `option`).
- `--screen all|main` – every screen, or only the one with the menu bar (default `all`).
- `--fps N` – appends `?fps=N` to the URL for pages that read it. livewall does not cap the
  frame rate itself; WebKit renders at the display's refresh rate.
- `--wallpaper-hash` / `--no-wallpaper-hash` – local files get `#wallpaper` appended by default
  (unless the URL already has a fragment), so a page can switch to a calmer wallpaper mode.

A local path becomes a `file://` URL with read access to its folder, so relative assets load;
a folder path loads its `index.html`.

The daemon is the same binary re-executed as `livewall daemon …` in its own session, so
closing the terminal does not kill it. It keeps `state.json`, `livewall.pid` and
`livewall.log` in `~/Library/Application Support/livewall/`.

## How it works

- One borderless, non-activating `NSPanel` per screen at `CGWindowLevelForKey(.desktopWindow)`,
  on all Spaces, stationary in Mission Control, out of the window cycle, and ignoring the
  mouse. The app runs with the `.accessory` activation policy, so it has no Dock icon and is
  not in the app switcher. Screens being added, removed or resized are tracked.
- A `WKWebView` fills each panel. Media may autoplay but is always muted. The window and the
  area under the page are black, so a transparent or failed page shows black rather than garbage.

### Hold-to-interact

- Every 40 ms the daemon reads `CGEventSource.flagsState(.combinedSessionState)`. Reading the
  modifier state needs no Accessibility or Input Monitoring permission (an event tap or global
  key monitor would). The key counts as held only when it is the sole modifier down, for at
  least 120 ms, so shortcuts like Option+arrow or Cmd+Option+Esc don't trigger it.
- While held, the panels move to `desktopIconWindow + 1` (above the Finder icons, still below
  every app window) and stop ignoring the mouse. The panel under the pointer becomes key
  **without activating the app**, which is what a non-activating panel is for: the page gets
  mouse-moved/hover and keyboard events, and the web view's `acceptsFirstMouse` makes the very
  first click go to the page instead of being swallowed to focus the window. Down, move, and
  up all reach the page, so canvas drags work.
- On release, the panels go back to desktop level and ignore the mouse again. Keyboard focus is
  handed back by re-ordering the key panel (a non-activating panel giving up key returns focus to
  the active app) and re-activating the app that was frontmost when you pressed the key.

### Energy

- While the screen is locked or the displays sleep, the panels are ordered out, so WebKit
  treats the page as hidden: `requestAnimationFrame` stops and timers are throttled.
- When the wallpaper is fully covered by windows, WebKit's own occlusion handling throttles
  the page. livewall also dispatches `livewall:visibility` on `document`
  (`event.detail.visible`), so a page can stop its own work.

## Limits

- It is Safari's engine (WebKit), not Chrome: use features Safari supports.
- While the key is held, the page covers the desktop icons; you can't see or click them until you let go.
- Interaction only works where the wallpaper is visible; app windows stay on top.
- A live page costs CPU/GPU (and battery) whenever the desktop is visible. Pages should keep
  their wallpaper mode light.
- If focus doesn't come back to the app you were in after release, click it once. macOS 14+
  can refuse activation requests from background apps.
