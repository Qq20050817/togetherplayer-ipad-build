package backend

import (
	"encoding/json"
	"testing"
	"together/poc/internal/core"
)

const testBaiduSource = "baidu://11111111111111111111111111111111/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/6800248966"

func TestSoloMatchedSourceCanPlayAndPause(t *testing.T) {
	s, h, g, r, a, _ := featureRoom(t)
	s.mu.Lock()
	defer s.mu.Unlock()
	delete(s.members, g.ID)
	delete(s.peers, g.ID)
	r.MediaURL = testBaiduSource
	p := s.profile(h)
	p.SourceID, p.Ready, p.Duration, p.LastSeen = r.MediaURL, true, 120000, now()
	s.handle(h, a, Command{Type: "PLAY", Sequence: 1, BaseVersion: r.Version})
	if featureEvent(t, a)["type"] != "STATE" || r.Timeline.State != "playing" {
		t.Fatal("ready solo source could not play")
	}
	s.handle(h, a, Command{Type: "PAUSE", Sequence: 2, BaseVersion: r.Version})
	if featureEvent(t, a)["type"] != "STATE" || r.Timeline.State != "paused" {
		t.Fatal("solo source could not pause")
	}
}

func TestSoloSourceStillRequiresValidReadiness(t *testing.T) {
	for _, condition := range []string{"wrong-source", "not-ready", "buffering", "unknown-duration", "stale", "disconnected", "empty-room"} {
		t.Run(condition, func(t *testing.T) {
			s, h, g, r, a, _ := featureRoom(t)
			s.mu.Lock()
			defer s.mu.Unlock()
			delete(s.members, g.ID)
			delete(s.peers, g.ID)
			r.MediaURL = testBaiduSource
			p := s.profile(h)
			current := now()
			p.SourceID, p.Ready, p.Duration, p.LastSeen = r.MediaURL, true, 120000, current
			switch condition {
			case "wrong-source":
				p.SourceID = "old-film"
			case "not-ready":
				p.Ready = false
			case "buffering":
				p.Buffering = true
			case "unknown-duration":
				p.Duration = 0
			case "stale":
				p.LastSeen = current - 5000
			case "disconnected":
				delete(s.peers, h.ID)
			case "empty-room":
				delete(s.members, h.ID)
			}
			s.handle(h, a, Command{Type: "PLAY", Sequence: 1, BaseVersion: r.Version})
			if featureEvent(t, a)["error"] != "SOURCE_NOT_READY" || r.Timeline.State != "paused" {
				t.Fatal("invalid solo source allowed to play")
			}
		})
	}
}

func TestSecondMemberMustMatchBeforeAutomaticResume(t *testing.T) {
	s, h, g, r, _, _ := featureRoom(t)
	s.mu.Lock()
	defer s.mu.Unlock()
	delete(s.members, g.ID)
	r.MediaURL = testBaiduSource
	current := now()
	p := s.profile(h)
	p.SourceID, p.Ready, p.Duration, p.LastSeen = r.MediaURL, true, 120000, current
	r.Timeline = core.Timeline{State: "playing", PlaybackRate: 1}
	r.Before = r.Timeline
	r.UpdatedAt = current
	// Joining an unprepared member must pause an already playing solo room.
	s.members[g.ID] = g
	s.updatePlayback(r, current)
	s.updatePlayback(r, current+2001)
	if r.Timeline.State != "paused" || !r.AutoResume {
		t.Fatal("unready joining member did not pause playback")
	}
	p.LastSeen = current + 3000
	gp := s.profile(g)
	gp.SourceID, gp.Ready, gp.Duration, gp.LastSeen = "old-film", true, 120000, current+3000
	s.updatePlayback(r, current+3000)
	if r.Timeline.State != "paused" {
		t.Fatal("wrong joining source resumed playback")
	}
	gp.SourceID = r.MediaURL
	s.updatePlayback(r, current+3001)
	if r.Timeline.State != "playing" {
		t.Fatal("matched joining member did not resume playback")
	}
	// A registered guest going offline is not the same as a solo room.
	delete(s.peers, g.ID)
	if s.baiduReady(r, current+3002) {
		t.Fatal("disconnected guest bypassed source gate")
	}
}

func TestBaiduReferenceRejectsCredentialsAndMalformedIdentity(t *testing.T) {
	if !safeMediaURL(testBaiduSource) {
		t.Fatal("identity rejected")
	}
	for _, value := range []string{testBaiduSource + "?access_token=secret", testBaiduSource + "#secret", "baidu://user:password@11111111111111111111111111111111/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/1", "baidu://11111111111111111111111111111111/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/0", "baidu://11111111111111111111111111111111/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/9007199254740992"} {
		if safeMediaURL(value) {
			t.Fatal("invalid descriptor accepted")
		}
	}
}
func TestBaiduCannotPlayOldSourceOrBypassWaitToggle(t *testing.T) {
	s, h, g, r, a, b := featureRoom(t)
	s.mu.Lock()
	defer s.mu.Unlock()
	r.MediaURL = testBaiduSource
	r.WaitForPeer = false
	current := now()
	for _, m := range []*Member{h, g} {
		p := s.profile(m)
		p.Ready = true
		p.Duration = 100000
		p.LastSeen = current
	}
	s.handle(h, a, Command{Type: "PLAY", Sequence: 1, BaseVersion: r.Version})
	if featureEvent(t, a)["error"] != "SOURCE_NOT_READY" || r.Timeline.State != "paused" {
		t.Fatal("old-source playback allowed")
	}
	s.profile(h).SourceID = testBaiduSource
	s.profile(g).SourceID = testBaiduSource
	s.handle(h, a, Command{Type: "PLAY", Sequence: 2, BaseVersion: r.Version})
	featureEvent(t, a)
	featureEvent(t, b)
	if r.Timeline.State != "playing" {
		t.Fatal("matched players could not play")
	}
	// A delayed status from the previous film must revoke readiness immediately.
	s.handleFeature(g, b, Command{Type: "PLAYER_STATUS", Data: json.RawMessage(`{"ready":true,"duration":100000,"sourceId":"old-film"}`)}, current+1)
	if s.profile(g).Ready || s.profile(g).Duration != 0 || s.baiduReady(r, current+1) {
		t.Fatal("stale status retained readiness")
	}
	// The preference cannot override the mandatory source gate.
	r.AutoResume = true
	r.Timeline = core.Timeline{State: "paused", Position: 3000, PlaybackRate: 1}
	r.Before = r.Timeline
	r.ExecuteAt = 0
	r.UpdatedAt = current
	s.handleFeature(h, a, Command{Type: "ROOM_SETTINGS", Sequence: 3, BaseVersion: r.Version, Data: json.RawMessage(`{"waitForPeer":false}`)}, current+1)
	if r.Timeline.State != "paused" {
		t.Fatal("settings bypassed source matching")
	}
}
func TestBaiduSwapInvalidatesBothSourceAcks(t *testing.T) {
	s, h, g, r, a, b := featureRoom(t)
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, m := range []*Member{h, g} {
		p := s.profile(m)
		p.SourceID = testBaiduSource
		p.Ready = true
		p.Duration = 120000
		p.LastSeen = now()
	}
	data, _ := json.Marshal(map[string]string{"mediaUrl": testBaiduSource, "title": "同一电影"})
	s.handleFeature(h, a, Command{Type: "ROOM_MEDIA", Sequence: 1, BaseVersion: r.Version, Data: data}, now())
	featureEvent(t, a)
	featureEvent(t, b)
	for _, m := range []*Member{h, g} {
		p := s.profile(m)
		if p.Ready || p.SourceID != "" || p.LastSeen != 0 {
			t.Fatal("previous movie status reused")
		}
	}
}
