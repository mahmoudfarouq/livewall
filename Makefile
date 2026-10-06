PREFIX ?= $(HOME)/.local
BIN = $(PREFIX)/bin
SHARE = $(PREFIX)/share/livewall/presets

.PHONY: build install uninstall clean

build:
	swift build -c release

# User-level install, no sudo: the binary to ~/.local/bin, presets to ~/.local/share/livewall/presets.
install: build
	mkdir -p "$(BIN)" "$(SHARE)"
	cp .build/release/livewall "$(BIN)/livewall"
	cp presets/*.html "$(SHARE)/"
	@echo "installed $(BIN)/livewall and $$(ls presets/*.html | wc -l | tr -d " ") presets"

uninstall:
	rm -f "$(BIN)/livewall"
	rm -rf "$(PREFIX)/share/livewall"

clean:
	rm -rf .build
