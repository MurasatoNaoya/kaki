package main

// NOTE: Go does not permit import "C" in _test.go files (cmd/go restriction).
// The round-trip through malloc/free is exercised via snapshotForTest(), a thin
// helper in cgo_shims.go that calls goSnapshot/goFreeSnapshot internally and
// returns a plain []float64.  All snapshot-layout assertions below are identical
// to the plan's original test.

import "testing"

func TestGoSnapshotRoundTrip(t *testing.T) {
	resetStore()
	goSetColor(0.1, 0.2, 0.3, 0.4)
	goSetWidth(5)
	goBeginStroke(10, 20)
	goAddPoint(30, 40)
	goEndStroke()

	got := snapshotForTest()

	if len(got) != 11 {
		t.Fatalf("want 11 floats, got %d", len(got))
	}
	want := []float64{1, 0.1, 0.2, 0.3, 0.4, 5, 2, 10, 20, 30, 40}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("at %d: want %v got %v (full %v)", i, want[i], got[i], got)
		}
	}
}
