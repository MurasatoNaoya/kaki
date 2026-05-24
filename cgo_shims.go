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
	if buf == nil {
		*outLen = 0
		return nil
	}
	arr := unsafe.Slice((*C.double)(buf), n)
	for i, v := range snap {
		arr[i] = C.double(v)
	}
	*outLen = C.int(n)
	return (*C.double)(buf)
}

//export goFreeSnapshot
func goFreeSnapshot(p *C.double) { C.free(unsafe.Pointer(p)) }

// snapshotForTest is not called in production; it exists because Go forbids import "C" in _test.go files.
// snapshotForTest calls goSnapshot/goFreeSnapshot and returns a plain []float64.
// This helper exists solely because Go does not allow import "C" in _test.go files;
// the test calls this instead of goSnapshot directly.
func snapshotForTest() []float64 {
	var n C.int
	ptr := goSnapshot(&n)
	defer goFreeSnapshot(ptr)
	count := int(n)
	arr := unsafe.Slice(ptr, count)
	out := make([]float64, count)
	for i := range out {
		out[i] = float64(arr[i])
	}
	return out
}
