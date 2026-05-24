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
