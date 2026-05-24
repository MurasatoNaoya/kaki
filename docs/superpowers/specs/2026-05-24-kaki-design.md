# Kaki — Design (v2 of ScreenPen)

**Date:** 2026-05-24
**Status:** Approved for planning
**Supersedes UI of:** `2026-05-24-screenpen-design.md` (v1). The Go core is reused unchanged.

## Goal

Evolve the working ScreenPen v1 overlay into **Kaki** — a polished, Dock-resident
macOS annotation app with a visible, distinctive control HUD. Same drawing engine;
new identity and a real UI.

Kaki (柿) is Japanese for *persimmon*; 柿色 *kakiiro* is a traditional Japanese burnt
orange, which is the app's signature accent.

Still a **Go + C project**: the Go `store` package and the cgo shims are reused as-is.
All new work is Objective-C/AppKit in `bridge.m`.

> **Not a web app.** Kaki is a native macOS Dock application (Go + Objective-C/cgo).
> The file `design/kaki-hud-mockup.html` is a *throwaway* visual reference used only to
> agree on the look during design. It is not shipped, not bundled, and no web technology
> (HTML/CSS/JS, web views) appears in the product. Every visual is drawn with AppKit.

## What carries over unchanged from v1

- `internal/store` (Go) — strokes, pen colour/width, draw-mode flag, `Snapshot()`. **No change.**
- `cgo_shims.go` — `goBeginStroke/AddPoint/EndStroke/Undo/Clear/ToggleMode/SetColor/SetWidth/Snapshot/FreeSnapshot`. **No change**; the HUD calls these.
- The full-screen transparent overlay window + `CanvasView` rendering and mouse capture. **Behaviour unchanged.**
- Carbon global hotkeys **⌥⌘D** (toggle draw) and **⌥⌘C** (clear).
- The `.app`-bundle-launched-via-`open` requirement (the v1 fix). `build.sh` produces the bundle.

## What changes

1. **Rebrand → Kaki.** Bundle `Kaki.app`, `CFBundleName` Kaki, bundle id `com.kaki.app`.
2. **Dock app.** Activation policy Accessory → **Regular** (Dock icon). Remove `LSUIElement`
   from `Info.plist`. Add a minimal app menu (**Kaki ▸ Quit ⌘Q**).
3. **Remove the menu-bar status item** entirely. The HUD replaces it. The old
   `NSStatusItem`/`MenuController` menu code is deleted.
4. **Add the Control HUD** (below).

## Aesthetic direction — "Sumi & Persimmon"

Japanese ink-wash minimalism. Reference mockup: `design/kaki-hud-mockup.html`.

- **Panel:** charcoal *washi* glass — translucent dark, fine grain, rounded corners
  (~22px), soft deep shadow. AppKit: `NSVisualEffectView` (dark, behind-window blend)
  + a tinted `CALayer` with `cornerRadius` and a grain image overlay.
- **Accent:** persimmon `#E0633A` (柿色) as the single sharp accent — selection rings,
  active width pill, the Draw button.
- **Type:** **Shippori Mincho** (bundled in the app) for the 柿 kanji + "kaki" wordmark;
  system sans (SF Pro / Hiragino) for labels and buttons.
- **Motion:** panel rises on launch; swatches scale on hover; selection ring animates in;
  Draw button softly pulses (layer shadow animation) while drawing is on. Restrained.

## The Control HUD

A small, always-on-top, titleless, **draggable** `NSPanel` (`NSWindowStyleMaskNonactivatingPanel`),
at a window level **above the overlay** so clicking it operates controls and never draws.
Contents, top to bottom:

- **Wordmark row:** 柿 kanji + "kaki", and a drag affordance. The **柿 glyph is recoloured
  live to the current pen colour** (acts as an ink indicator) — a **flat colour change, no
  glow**. Legibility only: the glyph carries a subtle 1px light hairline/outline so very
  dark or black inks remain visible against the dark panel.
- **Colour grid (4×2):** 7 preset swatches — **red, orange, yellow, green, blue, black,
  white** — plus a **`+`** cell that opens the native `NSColorPanel`. White swatch gets a
  light border. Clicking a swatch → `goSetColor` + highlights it (persimmon ring) + recolours 柿.
  Choosing from the colour panel → `goSetColor` + recolours 柿; no preset stays highlighted.
- **Width row:** 3 pills — thin / medium / thick = **2 / 5 / 10 px** → `goSetWidth`; active
  one highlighted in persimmon.
- **Actions:** **Draw** (toggle → `goToggleMode`; fills persimmon + pulses when on),
  **Undo** (`goUndo` + redraw), **Clear** (`goClear` + redraw), as icon buttons.
- **Footnote:** the two hotkeys as hint text.

### Pen-state ownership

The HUD tracks the *visual* selected state (which swatch/width is highlighted, current 柿
colour) in Objective-C. The Go `store` remains the single source of truth for stroke data
and applies colour/width to subsequent strokes via the existing setters. No new Go state.

## Window & lifecycle behaviour

- Overlay: unchanged — transparent, click-through when draw mode off, captures drags when on.
- HUD: floats above everything, movable, non-activating (doesn't steal focus from your work).
- Dock-app conventions:
  - **Close the HUD → it hides** (app keeps running, Dock icon stays).
  - **Click the Dock icon → re-show the HUD** (via `applicationShouldHandleReopen:`).
  - **⌘Q / Dock-menu Quit → terminate.**
- The overlay window has no close button (borderless), so only the HUD is user-closable.

## Components & files

| Component | Side | Change |
|-----------|------|--------|
| `internal/store` | Go | none |
| `cgo_shims.go` | Go | none |
| `bridge.m` | Obj-C | remove status item/menu controller; switch to Regular policy; add app menu + reopen handling; add `ControlHUD` (panel, swatches, width pills, action buttons, colour-panel handling, 柿 recolour); keep overlay + hotkeys |
| `Info.plist` | — | rename to Kaki; remove `LSUIElement`; bundle-id `com.kaki.app`; add font under `Contents/Resources` and reference if needed |
| `build.sh` | — | build into `Kaki.app`; copy bundled font into `Contents/Resources` |
| `design/kaki-hud-mockup.html` | — | reference mockup (committed) |
| bundled font | — | Shippori Mincho (OFL) in `Contents/Resources/`; registered at launch via `CTFontManagerRegisterFontsForURL` |

## Error handling

- Colour-panel cancel → no change.
- Font registration failure → fall back to a system serif for the wordmark; log a warning;
  the app continues. (Belt-and-suspenders so a missing/garbled font never blocks launch.)
- No destructive operations beyond Clear, which is non-persistent (nothing is saved to disk).

## Testing

- Go `store` tests are unchanged and must still pass (`go test ./...`).
- No new pure-logic Go code is added, so no new unit tests are warranted.
- The HUD and lifecycle are verified **manually** against a checklist, launched via
  `open Kaki.app`: HUD appears; each swatch sets colour and recolours 柿; black/white legible;
  `+` opens the colour panel and applies; width pills change thickness; Draw toggles drawing
  and pulses; Undo/Clear work; ⌥⌘D/⌥⌘C work; close hides; Dock-click re-shows; ⌘Q quits.

## Non-goals (v2)

- Multi-monitor (still main display only).
- Saving/exporting annotations.
- Shapes, text, highlighter, eraser.
- Resizable/skinnable HUD, themes, preferences window.
- Per-stroke colour editing after the fact.
