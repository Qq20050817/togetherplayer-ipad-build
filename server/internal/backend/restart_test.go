package backend

import (
	"path/filepath"
	"testing"
	"together/poc/internal/core"
)

func TestRestartRequiresExplicitPlayAndPersistsPausedAnchor(t *testing.T) {
	for _, tc := range []struct {
		name, state string
		auto        bool
		reason      string
		changed     bool
	}{
		{"playing", "playing", false, "", true},
		{"buffering recovery", "paused", true, "buffering", true},
		{"disconnected recovery", "paused", true, "disconnected", true},
		{"manual pause", "paused", false, "", false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			path := filepath.Join(t.TempDir(), "room.db")
			s, err := New(path, nil)
			if err != nil {
				t.Fatal(err)
			}
			r := core.Room{ID: "restart", HostID: "host", MediaURL: "https://example.org/test.mp4", Version: 7, ExpiresAt: now() + 60000, AutoResume: tc.auto, PauseReason: tc.reason, Timeline: core.Timeline{State: tc.state, Position: 42000, UpdatedAt: now() - 10000, PlaybackRate: 1}}
			s.mu.Lock()
			err = s.save(&r, nil)
			s.mu.Unlock()
			if err != nil {
				t.Fatal(err)
			}
			s.Close()
			restored, err := New(path, nil)
			if err != nil {
				t.Fatal(err)
			}
			got := *restored.rooms[r.ID]
			if got.State != "paused" || got.Position != 42000 || got.AutoResume {
				t.Fatalf("restart advanced/resumed film: %+v", got)
			}
			if tc.changed && (got.Version != 8 || got.PauseReason != "server_restart") {
				t.Fatalf("restart missing paused command: %+v", got)
			}
			if !tc.changed && (got.Version != 7 || got.PauseReason != "") {
				t.Fatal("manual pause modified")
			}
			restored.mu.Lock()
			restored.updatePlayback(restored.rooms[r.ID], now())
			if restored.rooms[r.ID].State != "paused" {
				t.Fatal("automatic readiness resumed restored room")
			}
			restored.mu.Unlock()
			restored.Close()
			again, err := New(path, nil)
			if err != nil {
				t.Fatal(err)
			}
			defer again.Close()
			if again.rooms[r.ID].Version != got.Version || again.rooms[r.ID].AutoResume {
				t.Fatal("pause not persisted across second restart")
			}
		})
	}
}
