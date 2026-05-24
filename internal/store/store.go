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
