PREFIX ?= $(HOME)/.local

.PHONY: build install uninstall clean

build:
	swift build -c release

# User-level install, no sudo: the binary to ~/.local/bin, presets to ~/.local/share/livewall/presets.
install: build
	PREFIX="$(PREFIX)" sh scripts/install.sh .build/release/livewall

uninstall:
	rm -f "$(PREFIX)/bin/livewall"
	rm -rf "$(PREFIX)/share/livewall"

clean:
	rm -rf .build
