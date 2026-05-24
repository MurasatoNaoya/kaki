# ScreenPen — Design

**Date:** 2026-05-24
**Status:** Approved for planning

## Goal

A free, EpicPen-style screen-annotation tool for macOS: a transparent always-on-top
overlay you can draw on anytime, toggled by a global hotkey. Built in **Go** with the
AppKit layer written as **Objective-C in the cgo preamble**.

This is a deliberate language choice. Go is not the path of least resistance for an
AppKit overlay, but keeping the project in Go is a stated goal, and the design pushes as
much real work into Go as possible so the choice pays off.

## Non-goals (v1)

- Multi-monitor support — **main display only** for v1; multi-monitor is v2.
- Saving/exporting annotations to disk.
- Shapes, text, highlighter modes — freehand pen only.
- Pressure sensitivity.
- App bundle / notarization / distribution — run as a plain `go build` binary for now.

## Architecture

Go is **authoritative for all state**; Objective-C is a thin rendering and input shell
that holds no drawing state.

- **Go (source of truth):** the stroke list, current pen color + width, draw-mode
  on/off flag. Owns undo and clear (plain list operations). Exposes C-callable functions.
- **Objective-C (cgo preamble):** the transparent overlay window, the view that renders
  strokes and captures mouse input, the menu-bar item, and global hotkey registration.
  Holds no state — it asks Go.

Input flows Obj-C → Go. Rendering pulls Go → Obj-C.

## Components

| Component        | Side   | Responsibility |
|------------------|--------|----------------|
| `store`          | Go     | Strokes, pen settings, mode flag. Pure logic, unit-testable without cgo. |
| C-export shims   | Go     | `goBeginStroke`, `goAddPoint`, `goEndStroke`, `goUndo`, `goClear`, `goToggleMode`, `goSetColor`, `goSetWidth`, `goSnapshot`, `goFreeSnapshot` |
| `OverlayWindow`  | Obj-C  | Borderless, transparent, top-level `NSPanel` at a high window level. `ignoresMouseEvents` toggles with draw mode so clicks pass through when drawing is off. |
| `CanvasView`     | Obj-C  | `drawRect:` renders strokes from a Go snapshot; `mouseDown/Dragged/Up` forward points to Go, then `setNeedsDisplay`. |
| `StatusItem`     | Obj-C  | Menu-bar icon + menu: color, width, clear, quit. |
| `hotkeys`        | Obj-C  | Carbon `RegisterEventHotKey` for toggle-draw and clear. Chosen over `CGEventTap` because it needs **no Accessibility permission**. |

## Data model (Go)

```
type Point struct { X, Y float64 }

type Stroke struct {
    Points     []Point
    R, G, B, A float64   // 0..1
    Width      float64
}

type Store struct {
    strokes    []Stroke
    current    *Stroke   // stroke in progress, nil when not drawing
    penR,G,B,A float64
    penWidth   float64
    drawMode   bool
}
```

Operations: `BeginStroke` (starts `current` with current pen settings), `AddPoint`,
`EndStroke` (appends `current` to `strokes`), `Undo` (pop last from `strokes`),
`Clear` (truncate `strokes`), `ToggleMode`, `SetColor`, `SetWidth`, `Snapshot`.

## Data flow — rendering

Rendering needs the whole stroke list each `drawRect:`. To avoid hundreds of tiny cgo
calls per frame, Go serializes everything into **one flat buffer** per redraw:

```
goSnapshot() -> pointer to float64 buffer + length:
  [ strokeCount,
    per stroke: R, G, B, A, width, pointCount, x0,y0, x1,y1, ... ]
```

- Go `C.malloc`s the buffer, fills it, returns pointer + element count.
- Obj-C reads it, draws each stroke as a `CGPath`/`NSBezierPath`, then calls
  `goFreeSnapshot(ptr)` which `C.free`s it.
- One cgo call per frame; Go stays authoritative; no duplicated state.

The `malloc`/`free` pair is the single place a leak can hide, so it is confined to
`goSnapshot` / `goFreeSnapshot` and nowhere else.

On `mouseDragged`, Obj-C calls `goAddPoint`, then `setNeedsDisplay`; the view pulls a
fresh snapshot on the next `drawRect:`.

## Draw-mode toggle behaviour

- **Mode ON:** `window.ignoresMouseEvents = NO`; window accepts mouse events; cursor draws.
- **Mode OFF:** `window.ignoresMouseEvents = YES`; all clicks pass through to apps beneath.
  Existing strokes remain visible (overlay stays on screen); the user just can't draw or
  interact with the overlay.

## Threading & lifecycle

- AppKit must own the main thread: `runtime.LockOSThread()` in `main`, then hand control
  to `[NSApp run]` via a cgo call that does not return until quit.
- `setActivationPolicy(.accessory)` → menu-bar agent app: no dock icon, does not steal
  focus from the frontmost app.
- Carbon hotkeys register against the app's event target; no Accessibility prompt.

## Hotkeys (v1 defaults)

- **Toggle draw mode:** `⌥⌘D` (configurable later; hardcoded for v1).
- **Clear screen:** `⌥⌘C`.
- Color/width changes go through the menu-bar menu in v1.

## Testing strategy

- **Go `store`** is pure and fully unit-tested: begin/add/end builds correct strokes,
  undo pops the last stroke, clear empties, snapshot serializes to the exact expected
  flat-buffer layout (the serialization format is the contract with Obj-C, so it gets
  explicit round-trip / layout assertions).
- **cgo boundary**: a small Go test calls the exported shims and asserts the snapshot
  buffer contents, exercising `malloc`/`free` under the race detector to catch leaks/
  misuse.
- **AppKit shell**: verified manually (draw, toggle, undo, clear, click-through), since
  UI rendering and global hotkeys aren't unit-testable without a display session.

## Risks & mitigations

- **cgo crashes** surface as C stack traces, not Go ones — keep Obj-C logic minimal and
  push branching into testable Go.
- **Manual memory** in the snapshot buffer — confined to one function pair, tested under
  the race detector.
- **Main-display-only** is a known v1 limitation, called out so multi-monitor isn't
  mistaken for a bug.
