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

// SetMode forces draw mode to an explicit state. Unlike ToggleMode it is
// idempotent, which is what the Escape break-glass needs: exiting must always
// land in the off state, never flip back on if already off.
func (s *Store) SetMode(on bool) {
	s.drawMode = on
}

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
