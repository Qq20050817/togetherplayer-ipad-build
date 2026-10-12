package backend

import (
	"encoding/json"
	"fmt"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"
	"together/poc/internal/core"
)

func featureRoom(t *testing.T) (*Server, *Member, *Member, *core.Room, *peer, *peer) {
	t.Helper()
	s, e := New(filepath.Join(t.TempDir(), "db"), nil)
	if e != nil {
		t.Fatal(e)
	}
	t.Cleanup(s.Close)
	h := &Member{ID: "host", RoomID: "r", Hash: "h"}
	g := &Member{ID: "guest", RoomID: "r", Hash: "g"}
	r := &core.Room{ID: "r", HostID: h.ID, MediaURL: "https://example.com/movie.mp4", Version: 1, WaitForPeer: true, ExpiresAt: now() + 100000, Timeline: core.Timeline{State: "paused", PlaybackRate: 1}}
	a := &peer{out: make(chan []byte, 64)}
	b := &peer{out: make(chan []byte, 64)}
	s.mu.Lock()
	s.rooms[r.ID] = r
	s.members[h.ID] = h
	s.members[g.ID] = g
	s.peers[h.ID] = a
	s.peers[g.ID] = b
	s.save(r, h)
	s.save(nil, g)
	s.mu.Unlock()
	// Dummy peers have no sockets and must be removed before normal Server.Close.
	t.Cleanup(func() { s.mu.Lock(); delete(s.peers, h.ID); delete(s.peers, g.ID); s.mu.Unlock() })
	return s, h, g, r, a, b
}
func featureEvent(t *testing.T, p *peer) map[string]any {
	t.Helper()
	select {
	case b := <-p.out:
		var v map[string]any
		json.Unmarshal(b, &v)
		return v
	case <-time.After(time.Second):
		t.Fatal("missing event")
		return nil
	}
}
func TestChatDedupProfileHistoryAndCloseRevocation(t *testing.T) {
	s, h, g, r, a, b := featureRoom(t)
	s.mu.Lock()
	defer s.mu.Unlock()
	s.handleFeature(g, b, Command{Type: "PROFILE_UPDATE", Data: json.RawMessage(`{"name":"好友","timelineOffset":8000}`)}, now())
	featureEvent(t, a)
	featureEvent(t, b)
	c := Command{Type: "CHAT_MESSAGE", Data: json.RawMessage(`{"text":"这里😂","clientMessageId":"msg-1"}`)}
	s.handleFeature(g, b, c, now())
	first := featureEvent(t, a)["message"].(map[string]any)
	featureEvent(t, b)
	s.handleFeature(g, b, c, now())
	again := featureEvent(t, a)["message"].(map[string]any)
	featureEvent(t, b)
	if first["id"] != again["id"] || len(s.history(r.ID)) != 1 {
		t.Fatal("duplicate chat persisted")
	}
	if s.profile(g).Offset != 8000 {
		t.Fatal("alignment not saved")
	}
	s.handleFeature(g, b, Command{Type: "ROOM_CLOSE"}, now())
	if featureEvent(t, b)["error"] != "HOST_REQUIRED" {
		t.Fatal("guest closed room")
	}
	s.handleFeature(h, a, Command{Type: "ROOM_CLOSE"}, now())
	featureEvent(t, a)
	featureEvent(t, b)
	if s.rooms[r.ID] != nil || s.members[g.ID] != nil || len(s.history(r.ID)) != 0 {
		t.Fatal("room close retained credentials/chat")
	}
}
func TestBufferPauseResumeAndManualPauseAuthority(t *testing.T) {
	s, h, g, r, a, b := featureRoom(t)
	s.mu.Lock()
	defer s.mu.Unlock()
	t0 := now()
	for _, m := range []*Member{h, g} {
		p := s.profile(m)
		p.Ready = true
		p.LastSeen = t0
	}
	r.Timeline = core.Timeline{State: "playing", Position: 10000, UpdatedAt: t0, PlaybackRate: 1}
	gp := s.profile(g)
	gp.Buffering = true
	gp.Ready = false
	s.updatePlayback(r, t0)
	s.updatePlayback(r, t0+1900)
	if r.State != "playing" {
		t.Fatal("brief buffering paused")
	}
	s.profile(h).LastSeen = t0 + 2100
	gp.LastSeen = t0 + 2100
	s.updatePlayback(r, t0+2100)
	if r.State != "paused" || !r.AutoResume || r.PauseReason != "buffering" {
		t.Fatal("sustained buffering did not pause", r)
	}
	featureEvent(t, a)
	featureEvent(t, b)
	paused := r.Position
	gp.Ready = true
	gp.Buffering = false
	gp.LastSeen = t0 + 3000
	s.profile(h).LastSeen = t0 + 3000
	s.updatePlayback(r, t0+3000)
	if r.State != "playing" || r.AutoResume || r.Position != paused {
		t.Fatal("ready resume lost paused timeline", r)
	}
	featureEvent(t, a)
	featureEvent(t, b)
	s.handle(h, a, Command{Type: "PAUSE", Sequence: 1, BaseVersion: r.Version})
	featureEvent(t, a)
	featureEvent(t, b)
	s.updatePlayback(r, t0+6000)
	if r.State != "paused" || r.AutoResume {
		t.Fatal("manual pause was auto-resumed")
	}
}
func TestMediaEndReplayAndWaitDisabled(t *testing.T) {
	s, h, g, r, a, b := featureRoom(t)
	s.mu.Lock()
	defer s.mu.Unlock()
	t0 := now()
	r.WaitForPeer = false
	r.Duration = 98000
	r.Timeline = core.Timeline{State: "playing", Position: 99000, UpdatedAt: t0, PlaybackRate: 1}
	s.updatePlayback(r, t0)
	if r.State != "paused" || r.Position != 98000 || r.PauseReason != "ended" {
		t.Fatal("end not canonical")
	}
	featureEvent(t, a)
	featureEvent(t, b)
	s.handle(h, a, Command{Type: "PLAY", Sequence: 1, BaseVersion: r.Version})
	featureEvent(t, a)
	featureEvent(t, b)
	if r.Position != 0 || r.State != "playing" {
		t.Fatal("play at end did not replay")
	}
	s.profile(g).Ready = false
	s.updatePlayback(r, t0+5000)
	if r.State != "playing" {
		t.Fatal("disabled waiting paused")
	}
}
func TestSourceSecretsAndReactionValidation(t *testing.T) {
	for _, u := range []string{"https://u:p@example.org/v.mp4", "https://example.org/?access_token=full", "file:///movie.mp4"} {
		if safeMediaURL(u) {
			t.Fatal("sensitive/nonHTTP source accepted")
		}
	}
	s, _, g, _, _, b := featureRoom(t)
	s.mu.Lock()
	defer s.mu.Unlock()
	s.handleFeature(g, b, Command{Type: "REACTION", Data: json.RawMessage(`{"emoji":"bad"}`)}, now())
	if featureEvent(t, b)["error"] != "INVALID_REACTION" {
		t.Fatal("unvalidated reaction")
	}
}
func TestFeatureWebSocketHistorySurvivesReconnect(t *testing.T) {
	s, e := New(filepath.Join(t.TempDir(), "db"), nil)
	if e != nil {
		t.Fatal(e)
	}
	defer s.Close()
	ts := httptest.NewServer(s.Handler())
	defer ts.Close()
	h := post(t, ts.URL+"/rooms", `{"mediaUrl":"https://example.org/v.mp4"}`, 201)
	c := dial(t, ts.URL, h)
	read(t, c)
	write(t, c, Command{Type: "CHAT_MESSAGE", Data: json.RawMessage(`{"text":"hi","clientMessageId":"m1"}`)})
	if read(t, c)["type"] != "CHAT_MESSAGE" {
		t.Fatal("missing chat")
	}
	c.Close()
	c = dial(t, ts.URL, h)
	defer c.Close()
	v := read(t, c)
	if len(v["messages"].([]any)) != 1 {
		t.Fatal("reconnect lost chat")
	}
}

func TestWelcomeHistoryFitsPublicRelayAndRetainsNewest(t *testing.T) {
	s, h, _, r, _, _ := featureRoom(t)
	s.mu.Lock()
	defer s.mu.Unlock()
	for i := 0; i < 50; i++ {
		_, e := s.db.Exec(`INSERT INTO messages(room_id,user_id,name,text,client_id,created_at) VALUES(?,?,?,?,?,?)`, r.ID, h.ID, "房主", strings.Repeat("😂", 1000), fmt.Sprint(i), now())
		if e != nil {
			t.Fatal(e)
		}
	}
	b, e := json.Marshal(s.snapshot(h, "WELCOME"))
	if e != nil || len(b) > 7800 {
		t.Fatalf("relay frame overflow: %d %v", len(b), e)
	}
	var v struct {
		Messages []Message `json:"messages"`
	}
	json.Unmarshal(b, &v)
	if len(v.Messages) == 0 || v.Messages[len(v.Messages)-1].ClientID != "49" {
		t.Fatal("latest history lost")
	}
}
func TestRoomSettingsAcknowledgementAndSourceChange(t *testing.T) {
	s, h, g, r, a, b := featureRoom(t)
	s.mu.Lock()
	defer s.mu.Unlock()
	c := Command{Type: "ROOM_SETTINGS", Sequence: 1, BaseVersion: r.Version, Data: json.RawMessage(`{"waitForPeer":false}`)}
	s.handle(h, a, c)
	ack := featureEvent(t, a)
	featureEvent(t, b)
	if ack["ackUserId"] != h.ID || ack["ackSequence"].(float64) != 1 || r.WaitForPeer {
		t.Fatal("missing operation acknowledgement")
	}
	s.profile(g).Ready = true
	s.profile(g).Duration = 90000
	s.handle(h, a, Command{Type: "ROOM_MEDIA", Sequence: 2, BaseVersion: r.Version, Data: json.RawMessage(`{"mediaUrl":"https://example.com/new.m3u8","title":"新影片"}`)})
	featureEvent(t, a)
	featureEvent(t, b)
	if p, state := r.At(now()); p != 0 || state != "paused" {
		t.Fatal("new source inherited old pre-execution timeline")
	}
	if r.Title != "新影片" || r.State != "paused" || r.Position != 0 || s.profile(g).Ready || s.profile(g).Duration != 0 {
		t.Fatal("source change did not invalidate readiness")
	}
	s.handle(g, b, Command{Type: "CONTROL_REQUEST", Sequence: 1, Data: json.RawMessage(`{"type":"ROOM_CLOSE"}`)})
	if featureEvent(t, b)["error"] != "INVALID_REQUEST" {
		t.Fatal("invalid control request forwarded")
	}
}
func TestDisconnectWaitAndResumeDisabled(t *testing.T) {
	s, h, g, r, _, _ := featureRoom(t)
	s.mu.Lock()
	defer s.mu.Unlock()
	t0 := now()
	r.State = "playing"
	r.UpdatedAt = t0
	r.ExecuteAt = 0
	s.profile(h).LastSeen = t0
	s.profile(h).Ready = true
	s.profile(g).LastSeen = t0
	s.profile(g).Ready = true
	delete(s.peers, g.ID)
	s.updatePlayback(r, t0)
	s.updatePlayback(r, t0+2100)
	if r.State != "paused" || r.PauseReason != "disconnected" {
		t.Fatal("disconnect did not pause")
	}
	r.WaitForPeer = false
	r.AutoResume = false
	r.PauseReason = ""
	r.State = "playing"
	r.ExecuteAt = 0
	s.updatePlayback(r, t0+9000)
	if r.State != "playing" {
		t.Fatal("disabled waiting paused room")
	}
}

func TestBufferFreezeDoesNotForceStalledPeerForward(t *testing.T) {
	s, h, g, r, a, b := featureRoom(t)
	s.mu.Lock()
	defer s.mu.Unlock()
	t0 := now()
	r.MediaURL = testBaiduSource
	r.Timeline = core.Timeline{State: "playing", Position: 10000, UpdatedAt: t0, PlaybackRate: 1}
	for _, m := range []*Member{h, g} {
		p := s.profile(m)
		p.Ready = true
		p.LastSeen = t0 + 2100
		p.Duration = 100000
		p.SourceID = testBaiduSource
		p.Position = 12000
	}
	gp := s.profile(g)
	gp.Ready = false
	gp.Buffering = true
	gp.Position = 10000
	gp.WaitingSince = t0
	s.updatePlayback(r, t0+2100)
	if r.Position != 10000 || !r.AutoResume {
		t.Fatal("buffer pause advanced stalled playhead", r.Position)
	}
	featureEvent(t, a)
	featureEvent(t, b)
	gp.Ready = true
	gp.Buffering = false
	gp.LastSeen = t0 + 3000
	s.profile(h).LastSeen = t0 + 3000
	s.updatePlayback(r, t0+3000)
	if r.Position != 10000 || r.State != "playing" {
		t.Fatal("resume lost recovery anchor")
	}
	featureEvent(t, a)
	featureEvent(t, b)
}
func TestBufferFreezeRejectsWrongSourceAndStalePosition(t *testing.T) {
	for _, mode := range []string{"wrong-source", "stale"} {
		t.Run(mode, func(t *testing.T) {
			s, h, g, r, a, b := featureRoom(t)
			s.mu.Lock()
			defer s.mu.Unlock()
			t0 := now()
			r.MediaURL = testBaiduSource
			r.Timeline = core.Timeline{State: "playing", Position: 10000, UpdatedAt: t0, PlaybackRate: 1}
			for _, m := range []*Member{h, g} {
				p := s.profile(m)
				p.Ready = true
				p.LastSeen = t0 + 2100
				p.Duration = 100000
				p.SourceID = testBaiduSource
			}
			gp := s.profile(g)
			gp.Buffering = true
			gp.Ready = false
			gp.Position = 0
			if mode == "wrong-source" {
				gp.SourceID = "old-film"
			} else {
				gp.LastSeen = t0 - 5000
			}
			s.autoControl(r, "PAUSE", "buffering", t0+2100)
			if r.Position <= 10000 {
				t.Fatal("untrusted position rewound room", r.Position)
			}
			featureEvent(t, a)
			featureEvent(t, b)
		})
	}
}
