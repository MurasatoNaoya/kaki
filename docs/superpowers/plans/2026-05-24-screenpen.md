# ScreenPen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A free EpicPen-style macOS screen-annotation overlay — draw anywhere on the main display, toggled by a global hotkey — with all state owned by Go and AppKit as a thin Objective-C shell over cgo.

**Architecture:** A pure-Go `store` package owns strokes, pen settings, and draw mode (fully unit-tested). A set of `//export`ed cgo shims expose that state to C. An Objective-C bridge (`bridge.m`) implements a transparent always-on-top `NSPanel`, a canvas view that renders by pulling a flat float64 snapshot from Go and forwards mouse input back to Go, a menu-bar item, and Carbon global hotkeys.

**Tech Stack:** Go 1.26 (cgo), Objective-C, AppKit (Cocoa), Carbon (RegisterEventHotKey). macOS arm64.

---

## File Structure

- `go.mod` — module definition.
- `internal/store/store.go` — pure Go state: `Point`, `Stroke`, `Store`, all operations, `Snapshot()`. No cgo. The brain.
- `internal/store/store_test.go` — unit tests for the store.
- `bridge.h` — C declarations for the Obj-C entry point (`RunApp`).
- `bridge.m` — Objective-C: overlay window, canvas view, menu bar, hotkeys. Calls back into Go via `_cgo_export.h`.
- `cgo_shims.go` — `//export`ed C-callable wrappers around a process-global `*store.Store`, plus `goSnapshot`/`goFreeSnapshot`. Holds the cgo preamble (CFLAGS/LDFLAGS, `#include "bridge.h"`).
- `main.go` — locks the OS thread and hands control to `RunApp`.

**Concurrency note for the implementer:** all AppKit callbacks run on the main thread, and the global store is touched only from those callbacks, so the store needs **no mutex**. Do not add one.

**Coordinate note:** capture (`mouseDown`/`Dragged`) and rendering (`drawRect:`) both use the view's default bottom-left origin coordinate space. Store raw coordinates as-is; never flip. As long as both sides use the same space, strokes land where drawn.

---

### Task 1: Project scaffold

**Files:**
- Create: `go.mod`
- Create: `main.go`

- [ ] **Step 1: Create the Go module**

Run:
```bash
cd ~/screenpen && go mod init screenpen
```
Expected: creates `go.mod` containing `module screenpen` and a `go 1.26` line.

- [ ] **Step 2: Create a placeholder `main.go` so the module builds**

`main.go`:
```go
package main

func main() {}
```

- [ ] **Step 3: Verify it builds**

Run: `cd ~/screenpen && go build ./...`
Expected: no output, exit 0.

- [ ] **Step 4: Commit**

```bash
cd ~/screenpen && git add go.mod main.go && git commit -m "chore: scaffold Go module"
```

---

### Task 2: Store types and stroke construction (TDD)

**Files:**
- Create: `internal/store/store.go`
- Test: `internal/store/store_test.go`

- [ ] **Step 1: Write the failing test**

`internal/store/store_test.go`:
```go
package store

import "testing"

func TestBeginAddEndBuildsStroke(t *testing.T) {
	s := New()
	s.BeginStroke(10, 20)
	s.AddPoint(30, 40)
	s.EndStroke()

	if got := len(s.strokes); got != 1 {
		t.Fatalf("want 1 stroke, got %d", got)
	}
	st := s.strokes[0]
	if len(st.Points) != 2 {
		t.Fatalf("want 2 points, got %d", len(st.Points))
	}
	if st.Points[0] != (Point{10, 20}) || st.Points[1] != (Point{30, 40}) {
		t.Fatalf("unexpected points: %+v", st.Points)
	}
	// default pen: red, width 3
	if st.R != 1 || st.G != 0 || st.B != 0 || st.A != 1 || st.Width != 3 {
		t.Fatalf("unexpected pen on stroke: %+v", st)
	}
}

func TestAddPointWithoutBeginIsNoop(t *testing.T) {
	s := New()
	s.AddPoint(1, 1) // no current stroke
	if len(s.strokes) != 0 {
		t.Fatalf("want 0 strokes, got %d", len(s.strokes))
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/screenpen && go test ./internal/store/`
Expected: FAIL — `undefined: New` (package does not compile).

- [ ] **Step 3: Write minimal implementation**

`internal/store/store.go`:
```go
package store

// Point is a single coordinate in the view's bottom-left-origin space.
type Point struct{ X, Y float64 }

// Stroke is one continuous freehand line with a fixed colour and width.
type Stroke struct {
	Points     []Point
	R, G, B, A float64 // colour components, 0..1
	Width      float64
}

// Store owns all annotation state. Not safe for concurrent use; it is only
// ever touched on the AppKit main thread.
type Store struct {
	strokes  []Stroke
	current  *Stroke
	penR     float64
	penG     float64
	penB     float64
	penA     float64
	penWidth float64
	drawMode bool
}

// New returns a Store with a red, width-3 pen and draw mode off.
func New() *Store {
	return &Store{penR: 1, penG: 0, penB: 0, penA: 1, penWidth: 3}
}

// BeginStroke starts a new in-progress stroke at (x, y) using current pen settings.
func (s *Store) BeginStroke(x, y float64) {
	s.current = &Stroke{
		Points: []Point{{x, y}},
		R:      s.penR, G: s.penG, B: s.penB, A: s.penA,
		Width: s.penWidth,
	}
}

// AddPoint appends a point to the in-progress stroke. No-op if none is in progress.
func (s *Store) AddPoint(x, y float64) {
	if s.current == nil {
		return
	}
	s.current.Points = append(s.current.Points, Point{x, y})
}

// EndStroke commits the in-progress stroke. No-op if none is in progress.
func (s *Store) EndStroke() {
	if s.current == nil {
		return
	}
	s.strokes = append(s.strokes, *s.current)
	s.current = nil
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ~/screenpen && go test ./internal/store/`
Expected: PASS (ok screenpen/internal/store).

- [ ] **Step 5: Commit**

```bash
cd ~/screenpen && git add internal/store/ && git commit -m "feat: store stroke construction"
```

---

### Task 3: Undo and Clear (TDD)

**Files:**
- Modify: `internal/store/store.go`
- Test: `internal/store/store_test.go`

- [ ] **Step 1: Write the failing test**

Append to `internal/store/store_test.go`:
```go
func TestUndoRemovesLastStroke(t *testing.T) {
	s := New()
	s.BeginStroke(0, 0)
	s.EndStroke()
	s.BeginStroke(1, 1)
	s.EndStroke()

	s.Undo()
	if len(s.strokes) != 1 {
		t.Fatalf("want 1 stroke after undo, got %d", len(s.strokes))
	}
	if s.strokes[0].Points[0] != (Point{0, 0}) {
		t.Fatalf("undo removed the wrong stroke: %+v", s.strokes[0])
	}
}

func TestUndoOnEmptyIsNoop(t *testing.T) {
	s := New()
	s.Undo() // must not panic
	if len(s.strokes) != 0 {
		t.Fatalf("want 0 strokes, got %d", len(s.strokes))
	}
}

func TestClearRemovesAllStrokes(t *testing.T) {
	s := New()
	s.BeginStroke(0, 0)
	s.EndStroke()
	s.BeginStroke(1, 1)
	s.EndStroke()

	s.Clear()
	if len(s.strokes) != 0 {
		t.Fatalf("want 0 strokes after clear, got %d", len(s.strokes))
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/screenpen && go test ./internal/store/`
Expected: FAIL — `s.Undo undefined` and `s.Clear undefined`.

- [ ] **Step 3: Write minimal implementation**

Append to `internal/store/store.go`:
```go
// Undo removes the most recently committed stroke. No-op when empty.
func (s *Store) Undo() {
	if len(s.strokes) == 0 {
		return
	}
	s.strokes = s.strokes[:len(s.strokes)-1]
}

// Clear removes all committed strokes. The in-progress stroke (if any) is left
// untouched so an active drag is not interrupted mid-flight.
func (s *Store) Clear() {
	s.strokes = nil
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ~/screenpen && go test ./internal/store/`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd ~/screenpen && git add internal/store/ && git commit -m "feat: undo and clear"
```

---

### Task 4: Pen settings and draw mode (TDD)

**Files:**
- Modify: `internal/store/store.go`
- Test: `internal/store/store_test.go`

- [ ] **Step 1: Write the failing test**

Append to `internal/store/store_test.go`:
```go
func TestSetColorAndWidthApplyToNextStroke(t *testing.T) {
	s := New()
	s.SetColor(0, 0, 1, 1) // blue
	s.SetWidth(7)
	s.BeginStroke(0, 0)
	s.EndStroke()

	st := s.strokes[0]
	if st.B != 1 || st.R != 0 || st.G != 0 || st.A != 1 {
		t.Fatalf("colour not applied: %+v", st)
	}
	if st.Width != 7 {
		t.Fatalf("width not applied: %v", st.Width)
	}
}

func TestToggleModeFlipsAndReturnsNewState(t *testing.T) {
	s := New()
	if s.DrawMode() {
		t.Fatal("draw mode should default to off")
	}
	if got := s.ToggleMode(); got != true {
		t.Fatalf("first toggle should return true, got %v", got)
	}
	if !s.DrawMode() {
		t.Fatal("draw mode should be on after toggle")
	}
	if got := s.ToggleMode(); got != false {
		t.Fatalf("second toggle should return false, got %v", got)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/screenpen && go test ./internal/store/`
Expected: FAIL — `s.SetColor undefined`, `s.SetWidth undefined`, `s.DrawMode undefined`, `s.ToggleMode undefined`.

- [ ] **Step 3: Write minimal implementation**

Append to `internal/store/store.go`:
```go
// SetColor sets the pen colour applied to subsequently begun strokes.
func (s *Store) SetColor(r, g, b, a float64) {
	s.penR, s.penG, s.penB, s.penA = r, g, b, a
}

// SetWidth sets the pen width applied to subsequently begun strokes.
func (s *Store) SetWidth(w float64) {
	s.penWidth = w
}

// DrawMode reports whether drawing is currently enabled.
func (s *Store) DrawMode() bool {
	return s.drawMode
}

// ToggleMode flips draw mode and returns the new state.
func (s *Store) ToggleMode() bool {
	s.drawMode = !s.drawMode
	return s.drawMode
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ~/screenpen && go test ./internal/store/`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd ~/screenpen && git add internal/store/ && git commit -m "feat: pen settings and draw mode"
```

---

### Task 5: Snapshot serialization (TDD)

This is the contract with Objective-C, so it gets exact layout assertions.

**Files:**
- Modify: `internal/store/store.go`
- Test: `internal/store/store_test.go`

- [ ] **Step 1: Write the failing test**

Append to `internal/store/store_test.go`:
```go
func TestSnapshotLayout(t *testing.T) {
	s := New()
	s.SetColor(0.1, 0.2, 0.3, 0.4)
	s.SetWidth(5)
	s.BeginStroke(10, 20)
	s.AddPoint(30, 40)
	s.EndStroke()

	got := s.Snapshot()
	want := []float64{
		1,                    // stroke count
		0.1, 0.2, 0.3, 0.4,   // RGBA
		5,                    // width
		2,                    // point count
		10, 20, 30, 40,       // points
	}
	if len(got) != len(want) {
		t.Fatalf("len mismatch: want %d got %d (%v)", len(want), len(got), got)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("at %d: want %v got %v (full %v)", i, want[i], got[i], got)
		}
	}
}

func TestSnapshotIncludesInProgressStroke(t *testing.T) {
	s := New()
	s.BeginStroke(1, 2) // not ended
	got := s.Snapshot()
	if got[0] != 1 {
		t.Fatalf("in-progress stroke should be counted; got count %v (%v)", got[0], got)
	}
}

func TestSnapshotEmpty(t *testing.T) {
	s := New()
	got := s.Snapshot()
	if len(got) != 1 || got[0] != 0 {
		t.Fatalf("empty snapshot should be [0], got %v", got)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/screenpen && go test ./internal/store/`
Expected: FAIL — `s.Snapshot undefined`.

- [ ] **Step 3: Write minimal implementation**

Append to `internal/store/store.go`:
```go
// Snapshot serializes all strokes (committed plus any in-progress one) into a
// flat slice for the renderer. Layout:
//
//	[ strokeCount,
//	  per stroke: R, G, B, A, width, pointCount, x0,y0, x1,y1, ... ]
//
// This layout is the exact contract consumed by bridge.m; changing it requires
// changing the Obj-C reader in lockstep.
func (s *Store) Snapshot() []float64 {
	all := s.strokes
	if s.current != nil {
		all = append(append([]Stroke(nil), s.strokes...), *s.current)
	}

	out := []float64{float64(len(all))}
	for _, st := range all {
		out = append(out, st.R, st.G, st.B, st.A, st.Width, float64(len(st.Points)))
		for _, p := range st.Points {
			out = append(out, p.X, p.Y)
		}
	}
	return out
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ~/screenpen && go test ./internal/store/`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd ~/screenpen && git add internal/store/ && git commit -m "feat: flat-buffer snapshot serialization"
```

---

### Task 6: cgo export shims (TDD)

**Files:**
- Create: `bridge.h`
- Create: `cgo_shims.go`
- Test: `cgo_shims_test.go`

- [ ] **Step 1: Create the bridge header (needed so the preamble compiles)**

`bridge.h`:
```c
#ifndef SCREENPEN_BRIDGE_H
#define SCREENPEN_BRIDGE_H

// RunApp starts the AppKit run loop and does not return until the app quits.
void RunApp(void);

#endif
```

- [ ] **Step 2: Write the failing test**

`cgo_shims_test.go`:
```go
package main

import (
	"testing"
	"unsafe"
)

// #include <stdlib.h>
import "C"

func TestGoSnapshotRoundTrip(t *testing.T) {
	resetStore()
	goSetColor(0.1, 0.2, 0.3, 0.4)
	goSetWidth(5)
	goBeginStroke(10, 20)
	goAddPoint(30, 40)
	goEndStroke()

	var n C.int
	ptr := goSnapshot(&n)
	defer goFreeSnapshot(ptr)

	if int(n) != 11 {
		t.Fatalf("want 11 floats, got %d", int(n))
	}
	got := make([]float64, int(n))
	arr := (*[1 << 20]C.double)(unsafe.Pointer(ptr))
	for i := range got {
		got[i] = float64(arr[i])
	}
	want := []float64{1, 0.1, 0.2, 0.3, 0.4, 5, 2, 10, 20, 30, 40}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("at %d: want %v got %v (full %v)", i, want[i], got[i], got)
		}
	}
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd ~/screenpen && go test .`
Expected: FAIL — `resetStore`, `goSetColor`, etc. undefined.

- [ ] **Step 4: Write the shims**

`cgo_shims.go`:
```go
package main

/*
#cgo CFLAGS: -x objective-c
#cgo LDFLAGS: -framework Cocoa -framework Carbon
#include <stdlib.h>
#include "bridge.h"
*/
import "C"

import (
	"unsafe"

	"screenpen/internal/store"
)

// gStore is the single process-global state. Touched only on the AppKit main
// thread (and in tests), so it needs no synchronization.
var gStore = store.New()

// resetStore is used by tests to get a clean store.
func resetStore() { gStore = store.New() }

//export goBeginStroke
func goBeginStroke(x, y C.double) { gStore.BeginStroke(float64(x), float64(y)) }

//export goAddPoint
func goAddPoint(x, y C.double) { gStore.AddPoint(float64(x), float64(y)) }

//export goEndStroke
func goEndStroke() { gStore.EndStroke() }

//export goUndo
func goUndo() { gStore.Undo() }

//export goClear
func goClear() { gStore.Clear() }

//export goToggleMode
func goToggleMode() C.int {
	if gStore.ToggleMode() {
		return 1
	}
	return 0
}

//export goSetColor
func goSetColor(r, g, b, a C.double) {
	gStore.SetColor(float64(r), float64(g), float64(b), float64(a))
}

//export goSetWidth
func goSetWidth(w C.double) { gStore.SetWidth(float64(w)) }

// goSnapshot returns a malloc'd C array of doubles (caller must goFreeSnapshot it)
// and writes the element count to *outLen. Layout is defined by store.Snapshot.
//
//export goSnapshot
func goSnapshot(outLen *C.int) *C.double {
	snap := gStore.Snapshot()
	n := len(snap)
	buf := C.malloc(C.size_t(n) * C.size_t(unsafe.Sizeof(C.double(0))))
	arr := (*[1 << 20]C.double)(buf)
	for i, v := range snap {
		arr[i] = C.double(v)
	}
	*outLen = C.int(n)
	return (*C.double)(buf)
}

//export goFreeSnapshot
func goFreeSnapshot(p *C.double) { C.free(unsafe.Pointer(p)) }
```

Note: with `//export` directives present, every file in the package needs the cgo comment-or-not rules satisfied. `main.go` will get its real body in Task 10; for now it still only contains `package main` + empty `main`, which is fine.

- [ ] **Step 5: Run the test (and the race detector) to verify it passes**

Run: `cd ~/screenpen && go test . && go test -race -run TestGoSnapshotRoundTrip .`
Expected: both PASS. The race run exercises the malloc/free path clean.

- [ ] **Step 6: Commit**

```bash
cd ~/screenpen && git add bridge.h cgo_shims.go cgo_shims_test.go && git commit -m "feat: cgo export shims with snapshot round-trip test"
```

---

### Task 7: Objective-C overlay window and canvas rendering

No unit test — verified by building and by manual checks in Task 10. Write complete code.

**Files:**
- Create: `bridge.m`

- [ ] **Step 1: Write the overlay window, canvas view, and RunApp skeleton**

`bridge.m`:
```objc
#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#include "bridge.h"
#include "_cgo_export.h" // declares goBeginStroke, goAddPoint, ... goSnapshot, etc.

// Globals so the hotkey handler and menu can reach the window/view.
static NSWindow *gWindow = nil;
static NSView   *gCanvas = nil;

// ---- Canvas: renders Go's snapshot and forwards mouse input to Go ----

@interface CanvasView : NSView
@end

@implementation CanvasView

- (BOOL)isFlipped { return NO; } // bottom-left origin, matches mouse coords

- (void)drawRect:(NSRect)dirtyRect {
    [[NSColor clearColor] set];
    NSRectFill(dirtyRect);

    int n = 0;
    double *buf = goSnapshot(&n);
    if (buf == NULL || n < 1) {
        if (buf) goFreeSnapshot(buf);
        return;
    }

    int i = 0;
    int strokeCount = (int)buf[i++];
    for (int s = 0; s < strokeCount; s++) {
        double r = buf[i++], g = buf[i++], b = buf[i++], a = buf[i++];
        double width = buf[i++];
        int pts = (int)buf[i++];

        NSBezierPath *path = [NSBezierPath bezierPath];
        [path setLineWidth:width];
        [path setLineCapStyle:NSLineCapStyleRound];
        [path setLineJoinStyle:NSLineJoinStyleRound];

        for (int p = 0; p < pts; p++) {
            double x = buf[i++], y = buf[i++];
            if (p == 0) {
                [path moveToPoint:NSMakePoint(x, y)];
            } else {
                [path lineToPoint:NSMakePoint(x, y)];
            }
        }
        [[NSColor colorWithCalibratedRed:r green:g blue:b alpha:a] set];
        [path stroke];
    }
    goFreeSnapshot(buf);
}

- (void)mouseDown:(NSEvent *)e {
    NSPoint p = [self convertPoint:[e locationInWindow] fromView:nil];
    goBeginStroke(p.x, p.y);
    [self setNeedsDisplay:YES];
}

- (void)mouseDragged:(NSEvent *)e {
    NSPoint p = [self convertPoint:[e locationInWindow] fromView:nil];
    goAddPoint(p.x, p.y);
    [self setNeedsDisplay:YES];
}

- (void)mouseUp:(NSEvent *)e {
    goEndStroke();
    [self setNeedsDisplay:YES];
}

@end
```

- [ ] **Step 2: Build to verify it compiles**

Run: `cd ~/screenpen && go build ./...`
Expected: FAIL — `RunApp` is declared in `bridge.h` but not yet defined (linker error `undefined symbol _RunApp`). This is expected; the definition arrives in Task 9.

If you instead get an Objective-C **compile** error (not a link error), fix it now before moving on.

- [ ] **Step 3: Commit**

```bash
cd ~/screenpen && git add bridge.m && git commit -m "feat: Obj-C canvas view rendering and mouse capture"
```

---

### Task 8: Menu-bar status item

**Files:**
- Modify: `bridge.m`

- [ ] **Step 1: Add a menu controller and builder above `RunApp`'s eventual location**

Append to `bridge.m` (after the `@end` of `CanvasView`):
```objc
// ---- Menu bar: colour, width, clear, quit ----

static NSStatusItem *gStatusItem = nil;

@interface MenuController : NSObject
@end

@implementation MenuController

- (void)setRed:(id)s   { goSetColor(1, 0, 0, 1); }
- (void)setGreen:(id)s { goSetColor(0, 0.7, 0, 1); }
- (void)setBlue:(id)s  { goSetColor(0, 0, 1, 1); }
- (void)setYellow:(id)s{ goSetColor(1, 0.85, 0, 1); }

- (void)setThin:(id)s   { goSetWidth(2); }
- (void)setMedium:(id)s { goSetWidth(5); }
- (void)setThick:(id)s  { goSetWidth(10); }

- (void)clearAll:(id)s {
    goClear();
    [gCanvas setNeedsDisplay:YES];
}

- (void)quit:(id)s { [NSApp terminate:nil]; }

@end

static MenuController *gMenuController = nil;

static void buildStatusItem(void) {
    gStatusItem = [[NSStatusBar systemStatusBar]
        statusItemWithLength:NSVariableStatusItemLength];
    gStatusItem.button.title = @"✎";

    gMenuController = [[MenuController alloc] init];
    NSMenu *menu = [[NSMenu alloc] init];

    NSMenu *colorMenu = [[NSMenu alloc] init];
    [colorMenu addItemWithTitle:@"Red"    action:@selector(setRed:)    keyEquivalent:@""].target = gMenuController;
    [colorMenu addItemWithTitle:@"Green"  action:@selector(setGreen:)  keyEquivalent:@""].target = gMenuController;
    [colorMenu addItemWithTitle:@"Blue"   action:@selector(setBlue:)   keyEquivalent:@""].target = gMenuController;
    [colorMenu addItemWithTitle:@"Yellow" action:@selector(setYellow:) keyEquivalent:@""].target = gMenuController;
    NSMenuItem *colorItem = [[NSMenuItem alloc] initWithTitle:@"Colour" action:nil keyEquivalent:@""];
    [colorItem setSubmenu:colorMenu];
    [menu addItem:colorItem];

    NSMenu *widthMenu = [[NSMenu alloc] init];
    [widthMenu addItemWithTitle:@"Thin"   action:@selector(setThin:)   keyEquivalent:@""].target = gMenuController;
    [widthMenu addItemWithTitle:@"Medium" action:@selector(setMedium:) keyEquivalent:@""].target = gMenuController;
    [widthMenu addItemWithTitle:@"Thick"  action:@selector(setThick:)  keyEquivalent:@""].target = gMenuController;
    NSMenuItem *widthItem = [[NSMenuItem alloc] initWithTitle:@"Width" action:nil keyEquivalent:@""];
    [widthItem setSubmenu:widthMenu];
    [menu addItem:widthItem];

    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Clear (⌥⌘C)" action:@selector(clearAll:) keyEquivalent:@""].target = gMenuController;
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Quit" action:@selector(quit:) keyEquivalent:@""].target = gMenuController;

    gStatusItem.menu = menu;
}
```

- [ ] **Step 2: Build to verify it still compiles (link error for `RunApp` still expected)**

Run: `cd ~/screenpen && go build ./...`
Expected: same `undefined symbol _RunApp` link error, no Obj-C compile errors. If a compile error appears, fix it.

- [ ] **Step 3: Commit**

```bash
cd ~/screenpen && git add bridge.m && git commit -m "feat: menu-bar colour/width/clear/quit"
```

---

### Task 9: Global hotkeys and RunApp

**Files:**
- Modify: `bridge.m`

- [ ] **Step 1: Add hotkey handling and the `RunApp` entry point**

Append to `bridge.m`:
```objc
// ---- Global hotkeys (Carbon — no Accessibility permission needed) ----

enum { HOTKEY_TOGGLE = 1, HOTKEY_CLEAR = 2 };

static OSStatus hotKeyHandler(EventHandlerCallRef next, EventRef e, void *ud) {
    (void)next; (void)ud;
    EventHotKeyID hk;
    GetEventParameter(e, kEventParamDirectObject, typeEventHotKeyID, NULL,
                      sizeof(hk), NULL, &hk);

    if (hk.id == HOTKEY_TOGGLE) {
        int on = goToggleMode();
        // Drawing on => capture mouse; off => clicks pass through.
        [gWindow setIgnoresMouseEvents:(on ? NO : YES)];
        if (on) {
            [gWindow makeKeyAndOrderFront:nil];
        }
    } else if (hk.id == HOTKEY_CLEAR) {
        goClear();
        [gCanvas setNeedsDisplay:YES];
    }
    return noErr;
}

static void registerHotKeys(void) {
    EventTypeSpec spec = { kEventClassKeyboard, kEventHotKeyPressed };
    InstallApplicationEventHandler(&hotKeyHandler, 1, &spec, NULL, NULL);

    EventHotKeyRef ref;
    // ⌥⌘D toggle draw mode. kVK_ANSI_D == 2.
    EventHotKeyID toggleID = { 'tgld', HOTKEY_TOGGLE };
    RegisterEventHotKey(2, optionKey | cmdKey, toggleID,
                        GetApplicationEventTarget(), 0, &ref);

    // ⌥⌘C clear. kVK_ANSI_C == 8.
    EventHotKeyID clearID = { 'tglc', HOTKEY_CLEAR };
    RegisterEventHotKey(8, optionKey | cmdKey, clearID,
                        GetApplicationEventTarget(), 0, &ref);
}

// ---- Entry point ----

void RunApp(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        // Accessory => menu-bar agent: no dock icon, does not steal focus.
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];

        NSRect frame = [[NSScreen mainScreen] frame];

        gWindow = [[NSPanel alloc]
            initWithContentRect:frame
                      styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                        backing:NSBackingStoreBuffered
                          defer:NO];
        [gWindow setOpaque:NO];
        [gWindow setBackgroundColor:[NSColor clearColor]];
        [gWindow setLevel:NSStatusWindowLevel + 1]; // float above normal windows
        [gWindow setIgnoresMouseEvents:YES];         // start in pass-through (draw off)
        [gWindow setHasShadow:NO];
        [gWindow setCollectionBehavior:
            NSWindowCollectionBehaviorCanJoinAllSpaces |
            NSWindowCollectionBehaviorStationary];

        gCanvas = [[CanvasView alloc] initWithFrame:frame];
        [gWindow setContentView:gCanvas];
        [gWindow orderFrontRegardless];

        buildStatusItem();
        registerHotKeys();

        [NSApp run];
    }
}
```

- [ ] **Step 2: Build to verify everything links now**

Run: `cd ~/screenpen && go build ./...`
Expected: PASS — no errors (the `RunApp` symbol now exists). Produces no binary yet because `main` is still empty, but `./...` compiling clean is the goal.

- [ ] **Step 3: Commit**

```bash
cd ~/screenpen && git add bridge.m && git commit -m "feat: global hotkeys and RunApp entry point"
```

---

### Task 10: Wire main and verify end-to-end (manual)

**Files:**
- Modify: `main.go`

- [ ] **Step 1: Wire `main` to RunApp on the locked main thread**

Replace the entire contents of `main.go` with:
```go
package main

/*
#include "bridge.h"
*/
import "C"

import "runtime"

func init() {
	// AppKit must own the main OS thread.
	runtime.LockOSThread()
}

func main() {
	C.RunApp()
}
```

- [ ] **Step 2: Build the binary**

Run: `cd ~/screenpen && go build -o screenpen . && ls -la screenpen`
Expected: a `screenpen` binary exists.

- [ ] **Step 3: Run it**

Run: `cd ~/screenpen && ./screenpen`
Expected: a `✎` icon appears in the menu bar; no dock icon; your other apps stay usable (clicks pass through).

- [ ] **Step 4: Manual verification checklist**

Confirm each, one at a time:
- [ ] Press **⌥⌘D** → draw mode on. Click-drag on screen draws a red line.
- [ ] Draw a second stroke. Both strokes are visible.
- [ ] Open the menu-bar `✎` → **Colour → Blue**, **Width → Thick**. Next stroke is thick blue.
- [ ] Menu-bar `✎` → **Clear** (or **⌥⌘C**) → all strokes vanish.
- [ ] Press **⌥⌘D** again → draw mode off. Clicks now pass through to apps beneath (you can click desktop icons through the overlay).
- [ ] Draw something, then test **undo**: (undo has no hotkey in v1 — confirm `goUndo` is reachable. If you want it usable now, add a menu item `[menu addItemWithTitle:@"Undo" action:@selector(undo:) ...]` with a `MenuController` method `- (void)undo:(id)s { goUndo(); [gCanvas setNeedsDisplay:YES]; }`. This is the one spot to extend before declaring v1 done.)
- [ ] Menu-bar `✎` → **Quit** → app exits cleanly, menu-bar icon disappears.

- [ ] **Step 5: Address the undo gap**

The spec lists undo as a v1 must-have but Task 8's menu omitted it. Add the undo menu item and handler now:

In `MenuController` `@implementation` (bridge.m), add:
```objc
- (void)undo:(id)s {
    goUndo();
    [gCanvas setNeedsDisplay:YES];
}
```
In `buildStatusItem`, before the first separator, add:
```objc
[menu addItemWithTitle:@"Undo" action:@selector(undo:) keyEquivalent:@""].target = gMenuController;
```
Rebuild and confirm undo removes the last stroke.

- [ ] **Step 6: Commit**

```bash
cd ~/screenpen && git add main.go bridge.m && git commit -m "feat: wire main entry point and add undo menu item"
```

---

## Self-Review notes

- **Spec coverage:** toggle draw mode (Task 4 + 9), colour/width picker (Task 4 + 8), clear (Task 3 + 8/9), undo (Task 3 + 10 step 5), flat-buffer snapshot (Task 5/6), main-display-only (`mainScreen` in Task 9), no-Accessibility hotkeys (Carbon, Task 9), menu-bar agent (accessory policy, Task 9), main-thread lock (Task 10). All present.
- **Type consistency:** `goSnapshot(*C.int) *C.double` / `goFreeSnapshot(*C.double)` used identically in shims (Task 6) and reader (Task 7). `Snapshot()` layout asserted in Task 5 matches the reader's parse order in Task 7. Pen defaults (red, width 3) consistent between Task 2 and the store's `New`.
- **Undo gap:** caught during review — Task 8's menu initially omitted undo; Task 10 step 5 closes it explicitly rather than silently. Flagged here so the executor doesn't treat it as an oversight.
