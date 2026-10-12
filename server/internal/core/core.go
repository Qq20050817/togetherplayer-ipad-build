package core

import "math"

type Timeline struct {
	State        string  `json:"state"`
	Position     float64 `json:"position"` // milliseconds on canonical movie timeline
	UpdatedAt    float64 `json:"updatedAt"`
	PlaybackRate float64 `json:"playbackRate"`
}
type Room struct {
	ID        string  `json:"roomId"`
	HostID    string  `json:"hostId"`
	MediaURL  string  `json:"mediaUrl"`
	Version   int64   `json:"version"`
	ExecuteAt float64 `json:"executeAt"`
	Timeline
	Before      Timeline `json:"before"`
	Title       string   `json:"title"`
	Duration    float64  `json:"duration"`
	WaitForPeer bool     `json:"waitForPeer"`
	PauseReason string   `json:"pauseReason,omitempty"`
	AutoResume  bool     `json:"autoResume,omitempty"`
	ExpiresAt   float64  `json:"expiresAt"`
}

func (t Timeline) At(now float64) float64 {
	if t.State == "playing" {
		return math.Max(0, t.Position+math.Max(0, now-t.UpdatedAt)*t.PlaybackRate)
	}
	return t.Position
}
func (r Room) At(now float64) (float64, string) {
	t := r.Timeline
	if now < r.ExecuteAt {
		t = r.Before
	}
	return t.At(now), t.State
}
func (r *Room) Control(kind string, position, now float64) {
	// A newer command replaces pending work; Before retains what is actually playing now.
	current := r.Timeline
	if now < r.ExecuteAt {
		current = r.Before
	}
	p, s := r.At(now)
	r.Before = Timeline{State: s, Position: p, UpdatedAt: now, PlaybackRate: current.PlaybackRate}
	at := now + 750
	p, s = r.Before.At(at), r.Before.State
	switch kind {
	case "PLAY":
		s = "playing"
		if r.Duration > 0 && p >= r.Duration-150 {
			p = 0
		}
	case "REPLAY":
		p = 0
		s = "playing"
	case "PAUSE":
		s = "paused"
	case "SEEK":
		p = position
	}
	rate := current.PlaybackRate
	if s != "playing" {
		rate = 1
	}
	r.Timeline = Timeline{State: s, Position: p, UpdatedAt: at, PlaybackRate: rate}
	r.ExecuteAt = at
	r.Version++
}

// Correct returns the desired speed and whether a hard seek is required.
func Correct(errorMs float64, playing bool) (float64, bool) {
	if !playing {
		return 1, math.Abs(errorMs) > 200
	}
	a := math.Abs(errorMs)
	if a < 200 {
		return 1, false
	}
	if a > 1500 {
		return 1, true
	}
	delta := 0.02
	if a >= 500 {
		delta = 0.05
	}
	if errorMs < 0 {
		delta = -delta
	}
	return 1 + delta, false
}
