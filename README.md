# 柿 kaki

A minimal macOS screen-annotation tool. Toggle draw mode, sketch over anything on screen and clear it away. Controls live in a single dark-glass "Smoke Bar" built on macOS Liquid Glass.

Native app: Go core, Objective-C / AppKit shell via cgo. No web views, no Electron.

## Use

```bash
./build.sh        # builds Kaki.app
open Kaki.app     # launch (must run as a bundle, not the bare binary)
```

A Dock icon appears with the Smoke Bar near the top of the screen.

- **Draw** on the bar, or **Option-Command-D**, toggles draw mode. When off, clicks pass through to the apps beneath.
- **Colour**: seven preset swatches plus a custom picker. The 柿 wordmark recolours to the active pen.
- **Width**: thin / medium / thick.
- **Undo** `↶`, **Clear** `⌫` (or Option-Command-C).
- **Escape** breaks out of draw mode instantly.
- **×** hides the bar; click the Dock icon to bring it back.

## Build requirements

- macOS 26 or later (the HUD uses `NSGlassEffectView`, the system Liquid Glass surface).
- Go toolchain and the Xcode Command Line Tools (cgo compiles the AppKit layer).

## Layout

```
main.go            entry point; locks the main thread for AppKit
bridge.m / .h      transparent full-screen overlay, mouse capture, global hotkeys, app menu
hud.m / hud.h      the Smoke Bar control HUD (Liquid Glass)
cgo_shims.go       C-callable wrappers over the Go store
internal/store     pen state: strokes, colour, width, draw mode
assets/            bundled wordmark font (Shippori Mincho subset) and app icon
design/            design exploration mockups (history; excluded from language stats)
build.sh           builds Kaki.app
```

The name is 柿 (kaki), Japanese for persimmon; 柿色 (kakiiro), a burnt orange, is the accent colour.
