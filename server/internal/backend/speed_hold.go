package backend

import (
	"encoding/json"
	"together/poc/internal/core"
)

type speedHold struct {
	ID    string
	Until float64
}

// Renewable leases make lost releases, backgrounding and crashes safe.
func (s *Server) handleSpeedHold(m *Member, p *peer, c Command, t float64) {
	profile := s.profile(m)
	if t-profile.Window >= 1000 {
		profile.Window = t
		profile.Events = 0
	}
	profile.Events++
	if profile.Events > 30 {
		s.send(p, map[string]any{"type": "ERROR", "error": "RATE_LIMIT"})
		return
	}
	var d struct {
		Active bool   `json:"active"`
		ID     string `json:"holdId"`
	}
	r := s.rooms[m.RoomID]
	if json.Unmarshal(c.Data, &d) != nil || len(d.ID) < 1 || len(d.ID) > 64 {
		s.send(p, map[string]any{"type": "ERROR", "error": "INVALID_REQUEST", "room": r})
		return
	}
	if s.speedHolds == nil {
		s.speedHolds = map[string]map[string]speedHold{}
	}
	holds := s.speedHolds[m.RoomID]
	if holds == nil {
		holds = map[string]speedHold{}
		s.speedHolds[m.RoomID] = holds
	}
	if d.Active {
		_, state := r.At(t)
		if state != "playing" || r.State != "playing" {
			return
		}
		if old, ok := holds[m.ID]; ok && old.ID != d.ID && old.Until > t {
			return
		}
		holds[m.ID] = speedHold{d.ID, t + 2000}
	} else if old, ok := holds[m.ID]; ok && old.ID == d.ID {
		delete(holds, m.ID)
	}
	s.refreshSpeedHolds(r, t)
}
func (s *Server) releaseSpeedHold(room, user string, t float64) {
	delete(s.speedHolds[room], user)
	if r := s.rooms[room]; r != nil {
		s.refreshSpeedHolds(r, t)
	}
}
func (s *Server) refreshSpeedHolds(r *core.Room, t float64) {
	holds := s.speedHolds[r.ID]
	if r.State != "playing" {
		for user := range holds {
			delete(holds, user)
		}
	}
	for user, h := range holds {
		if h.Until <= t {
			delete(holds, user)
		}
	}
	rate := 1.0
	if len(holds) > 0 {
		rate = 2
	}
	if r.PlaybackRate == rate {
		return
	}
	next := *r
	timeline := r.Timeline
	if t < r.ExecuteAt {
		timeline = r.Before
	}
	at := t + 150
	next.Before = core.Timeline{State: timeline.State, Position: timeline.At(t), UpdatedAt: t, PlaybackRate: timeline.PlaybackRate}
	next.Timeline = core.Timeline{State: timeline.State, Position: next.Before.At(at), UpdatedAt: at, PlaybackRate: rate}
	next.ExecuteAt = at
	next.Version++
	if s.save(&next, nil) != nil {
		return
	}
	*r = next
	s.broadcast(r.ID, map[string]any{"type": "STATE", "room": r})
}
