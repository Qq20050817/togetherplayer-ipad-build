package core

import (
	"math"
	"testing"
)

func TestScheduledControlAndReplacement(t *testing.T) {
	r := Room{Timeline: Timeline{State: "playing", Position: 1000, UpdatedAt: 1000, PlaybackRate: 1}, Version: 1}
	r.Control("PAUSE", 0, 2000)
	if p, s := r.At(2200); p != 2200 || s != "playing" {
		t.Fatalf("early pause: %v %v", p, s)
	}
	if p, s := r.At(3000); p != 2750 || s != "paused" {
		t.Fatalf("wrong pause: %v %v", p, s)
	}
	r.Control("PLAY", 0, 2300)
	if p, s := r.At(2900); p != 2900 || s != "playing" {
		t.Fatalf("replaced pending pause applied: %v %v", p, s)
	}
	r.Control("SEEK", 50000, 4000)
	if p, _ := r.At(4750); p != 50000 {
		t.Fatal(p)
	}
	if p, _ := r.At(5750); p != 51000 {
		t.Fatal(p)
	}
}
func TestDriftCorrectionBoundaries(t *testing.T) {
	for _, v := range []struct {
		error, speed float64
		seek         bool
	}{{199, 1, false}, {200, 1.02, false}, {-300, .98, false}, {500, 1.05, false}, {-1500, .95, false}, {1501, 1, true}} {
		speed, seek := Correct(v.error, true)
		if math.Abs(speed-v.speed) > 1e-8 || seek != v.seek {
			t.Fatal(v, speed, seek)
		}
	}
}
