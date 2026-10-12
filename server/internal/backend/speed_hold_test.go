package backend

import (
	"encoding/json"
	"testing"
	"together/poc/internal/core"
)

func TestSpeedHoldGuestLeaseReleaseAndTimeline(t *testing.T) {
	s, h, g, r, a, b := featureRoom(t)
	s.mu.Lock()
	defer s.mu.Unlock()
	t0 := now()
	r.Timeline = core.Timeline{State: "playing", Position: 1000, UpdatedAt: t0, PlaybackRate: 1}
	r.Before = r.Timeline
	r.ExecuteAt = t0
	cmd := func(active bool, id string) Command {
		data, _ := json.Marshal(map[string]any{"active": active, "holdId": id})
		return Command{Type: "SPEED_HOLD", Data: data}
	}
	s.handleSpeedHold(g, b, cmd(true, "guest-hold"), t0)
	if r.PlaybackRate != 2 {
		t.Fatal("guest must accelerate both")
	}
	p, _ := r.At(t0 + 650)
	if p != 2150 {
		t.Fatalf("continuous rate timeline: %v", p)
	}
	version := r.Version
	s.handleSpeedHold(g, b, cmd(true, "guest-hold"), t0+700)
	if r.Version != version {
		t.Fatal("heartbeat must not create versions")
	}
	s.handleSpeedHold(h, a, cmd(true, "host-hold"), t0+800)
	s.handleSpeedHold(g, b, cmd(false, "guest-hold"), t0+900)
	if r.PlaybackRate != 2 {
		t.Fatal("other member still holds")
	}
	s.handleSpeedHold(h, a, cmd(false, "wrong-hold"), t0+950)
	if r.PlaybackRate != 2 {
		t.Fatal("stale release must be ignored")
	}
	s.releaseSpeedHold(r.ID, h.ID, t0+1000)
	if r.PlaybackRate != 1 {
		t.Fatal("disconnect restores rate")
	}
	s.handleSpeedHold(g, b, cmd(true, "lease"), t0+1300)
	s.refreshSpeedHolds(r, t0+3401)
	if r.PlaybackRate != 1 {
		t.Fatal("lost release lease expires")
	}
	r.Control("PAUSE", 0, t0+4000)
	s.handleSpeedHold(g, b, cmd(true, "paused"), t0+5000)
	if r.PlaybackRate != 1 || r.State != "paused" {
		t.Fatal("hold must not resume paused film")
	}
}
