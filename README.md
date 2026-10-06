# livewall

[![CI](https://github.com/mahmoudfarouq/livewall/actions/workflows/ci.yml/badge.svg)](https://github.com/mahmoudfarouq/livewall/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/mahmoudfarouq/livewall)](https://github.com/mahmoudfarouq/livewall/releases/latest)

A tiny macOS command-line tool that shows an HTML page as your live desktop wallpaper,
on every screen. Hold a modifier key (Option by default) to click, drag and scroll the page;
let go and it is wallpaper again. No app, no menu bar item, no permission prompts.
It comes with a set of hand-made pages (presets), and takes any local file or URL too.

```sh
livewall set night-city
```

## Install

### One line (no Swift needed)

```sh
curl -fsSL https://raw.githubusercontent.com/mahmoudfarouq/livewall/main/scripts/install.sh | sh
```

This downloads the latest [release](https://github.com/mahmoudfarouq/livewall/releases), a
universal binary (Apple silicon and Intel) with the presets, and installs the binary to
`~/.local/bin/livewall` and the presets to `~/.local/share/livewall/presets`, for your user
only (no sudo). Make sure `~/.local/bin` is on your `PATH`. Set `PREFIX` to install somewhere
else, e.g. `curl … | PREFIX=/opt/livewall sh`.

To update, run the same command again. To uninstall:

```sh
rm -f ~/.local/bin/livewall && rm -rf ~/.local/share/livewall
```

The binary isn't notarized. If you download a release archive with a browser instead, macOS
quarantines it; the installer clears that flag on the installed copy. Each release also has a
`.sha256` checksum for the archive.

### From source

Requires macOS 13 or later and a Swift toolchain (Xcode or the Command Line Tools, Swift 5.9+).
Only AppKit and WebKit are used; there are no third-party dependencies.

```sh
git clone https://github.com/mahmoudfarouq/livewall.git && cd livewall
make install
```

`make install` builds a release binary and runs the same installer. `make uninstall` removes
both. To build without installing, run `swift build -c release` and use
`.build/release/livewall`, which finds the presets in the repo.

livewall doesn't add itself to login items. To start it at login, run `livewall set …` from
your shell profile or a login item.

## Usage

| command | what it does |
| --- | --- |
| `livewall set <preset\|path\|url> [options]` | starts the wallpaper daemon (replacing any running one) and returns |
| `livewall set --random [options]` | shows a random preset |
| `livewall presets` (or `list`) | lists the presets with their titles |
| `livewall stop` | stops it |
| `livewall status` | url, key, screens, pid and log path of the running daemon |
| `livewall reload` | reloads the page on every screen (e.g. after editing the file) |
| `livewall --version` | the installed version |
| `livewall --help` | usage |

```sh
livewall set ink-water                       # a preset
livewall set ~/Sites/my-piece/index.html     # a local file (or a folder with index.html)
livewall set https://example.com --screen main --key control
```

Options for `set`:

- `--key option|control|command|fn`: the key to hold for interaction (default `option`).
- `--screen all|main`: every screen, or only the one with the menu bar (default `all`).
- `--fps N`: appends `?fps=N` to the URL for pages that read it. livewall does not cap the
  frame rate itself; WebKit renders at the display's refresh rate.
- `--wallpaper-hash` / `--no-wallpaper-hash`: local files and presets get `#wallpaper`
  appended by default (unless the URL already has a fragment), so a page can switch to a
  calmer wallpaper mode. Newer pieces read it; ink-water, night-city, pocket-universe and word-creatures ignore it for now.

An existing path or URL always wins over a preset name. A local path becomes a `file://` URL
with read access to its folder, so relative assets load.

The daemon is the same binary re-executed as `livewall daemon …` in its own session, so
closing the terminal does not kill it. It keeps `state.json`, `livewall.pid` and
`livewall.log` in `~/Library/Application Support/livewall/`.

## Presets

| slug | title |
| --- | --- |
| `dream-archive` | Dream Archive |
| `glassblower` | Glassblower's Bench |
| `ink-water` | Floating Ink |
| `last-train` | The Last Train |
| `lighthouse-keeper` | Lighthouse Keeper |
| `murmuration` | Fen Murmuration |
| `mycelium` | The Wood Wide Web |
| `night-city` | Lights Left On |
| `orrery` | Clockwork Orrery |
| `pocket-universe` | Pocket Universe |
| `sand-garden` | Sand Garden |
| `tide-pool` | Tide Pool |
| `weather-jar` | Weather in a Jar |
| `word-creatures` | Living Type Specimen |

Each preset is one self-contained HTML file in `presets/`, named `<slug>.html`
(`night-city` loads three.js from cdnjs, so it needs a network connection).

**Adding your own:** drop an HTML file into `presets/` (the file name is the slug, the
`<title>` is what `livewall presets` shows) and run `make install` again. livewall looks for
presets in this order, and the first match wins:

1. `$LIVEWALL_PRESETS`
2. `<prefix>/share/livewall/presets`, next to the installed binary (`<prefix>/bin/livewall`)
3. `~/.local/share/livewall/presets`
4. `presets/` in the repo, when running from its `.build` folder

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

## Development

CI builds a universal binary on every push and pull request, smoke-tests the CLI and the
installer, and checks that every preset has a `<title>` and a charset.

To cut a release, tag `main` and push the tag:

```sh
git tag v0.2.0 && git push origin v0.2.0
```

The release workflow stamps the version into the binary (`livewall --version`), builds it,
packages `livewall-macos-universal.tar.gz` (the same name every release, so the
`latest/download` link above always works) with the presets, the installer, the
README and the license, and publishes a GitHub release with generated notes and a checksum.

## License

MIT, see [LICENSE](LICENSE).
