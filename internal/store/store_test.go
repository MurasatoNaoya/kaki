package store

import (
	"slices"
	"testing"
)

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
	if got := s.ToggleMode(); !got {
		t.Fatalf("first toggle should return true, got %v", got)
	}
	if !s.DrawMode() {
		t.Fatal("draw mode should be on after toggle")
	}
	if got := s.ToggleMode(); got != false {
		t.Fatalf("second toggle should return false, got %v", got)
	}
}

func TestSetModeForcesStateRegardlessOfCurrent(t *testing.T) {
	s := New()
	// Off -> off: a panic exit must stay off, never toggle on.
	s.SetMode(false)
	if s.DrawMode() {
		t.Fatal("SetMode(false) on an already-off store must stay off")
	}
	// Off -> on.
	s.SetMode(true)
	if !s.DrawMode() {
		t.Fatal("SetMode(true) should turn draw mode on")
	}
	// On -> off (the break-glass case).
	s.SetMode(false)
	if s.DrawMode() {
		t.Fatal("SetMode(false) should turn draw mode off")
	}
}

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
	// count=1, RGBA=1,0,0,1, width=3, pointCount=1, point (1,2)
	want := []float64{1, 1, 0, 0, 1, 3, 1, 1, 2}
	if !slices.Equal(got, want) {
		t.Fatalf("in-progress snapshot mismatch:\n got  %v\n want %v", got, want)
	}
}

func TestSnapshotMixedCommittedAndInProgress(t *testing.T) {
	s := New()
	s.BeginStroke(10, 20)
	s.EndStroke() // committed
	s.BeginStroke(30, 40) // in-progress, not ended

	got := s.Snapshot()
	// count=2; each stroke: RGBA 1,0,0,1, width 3, pointCount 1, then its point
	want := []float64{2, 1, 0, 0, 1, 3, 1, 10, 20, 1, 0, 0, 1, 3, 1, 30, 40}
	if !slices.Equal(got, want) {
		t.Fatalf("mixed snapshot mismatch:\n got  %v\n want %v", got, want)
	}
}

func TestClearPreservesInProgressStroke(t *testing.T) {
	s := New()
	s.BeginStroke(0, 0)
	s.EndStroke()        // commit one stroke
	s.BeginStroke(5, 6) // start a new in-progress stroke (not ended)

	s.Clear()

	if len(s.strokes) != 0 {
		t.Fatalf("Clear should remove all committed strokes, got %d", len(s.strokes))
	}
	if s.current == nil {
		t.Fatal("Clear should preserve the in-progress stroke, but current is nil")
	}
}

func TestSnapshotEmpty(t *testing.T) {
	s := New()
	got := s.Snapshot()
	if len(got) != 1 || got[0] != 0 {
		t.Fatalf("empty snapshot should be [0], got %v", got)
	}
}
