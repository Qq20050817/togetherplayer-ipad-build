package backend

import (
	"encoding/json"
	"math"
	"strings"
	"time"
	"together/poc/internal/core"
	"unicode/utf8"
)

type Profile struct {
	SourceID     string  `json:"sourceId"`
	UserID       string  `json:"userId"`
	Name         string  `json:"name"`
	Offset       float64 `json:"timelineOffset"`
	Duration     float64 `json:"duration"`
	Position     float64 `json:"position"`
	Ready        bool    `json:"ready"`
	Buffering    bool    `json:"buffering"`
	Online       bool    `json:"online"`
	LastSeen     float64 `json:"lastSeen"`
	WaitingSince float64 `json:"-"`
	Window       float64 `json:"-"`
	Events       int     `json:"-"`
}
type Message struct {
	ID        int64   `json:"id"`
	UserID    string  `json:"userId"`
	Name      string  `json:"name"`
	Text      string  `json:"text"`
	ClientID  string  `json:"clientMessageId"`
	Timestamp float64 `json:"timestamp"`
}

func (s *Server) profile(m *Member) *Profile {
	p := s.profiles[m.ID]
	if p == nil {
		p = &Profile{UserID: m.ID, Name: "好友"}
		if r := s.rooms[m.RoomID]; r != nil && r.HostID == m.ID {
			p.Name = "房主"
		}
		s.profiles[m.ID] = p
	}
	return p
}
func (s *Server) roster(roomID string) []*Profile {
	out := []*Profile{}
	for _, m := range s.members {
		if m.RoomID == roomID {
			p := *s.profile(m)
			p.Online = s.peers[m.ID] != nil
			out = append(out, &p)
		}
	}
	return out
}
func (s *Server) history(roomID string) []Message {
	rows, e := s.db.Query(`SELECT id,user_id,name,text,client_id,created_at FROM messages WHERE room_id=? ORDER BY id DESC LIMIT 50`, roomID)
	if e != nil {
		return []Message{}
	}
	defer rows.Close()
	out := []Message{}
	for rows.Next() {
		var m Message
		if rows.Scan(&m.ID, &m.UserID, &m.Name, &m.Text, &m.ClientID, &m.Timestamp) == nil {
			out = append(out, m)
		}
	}
	for a, b := 0, len(out)-1; a < b; a, b = a+1, b-1 {
		out[a], out[b] = out[b], out[a]
	}
	return out
}
func (s *Server) saveProfile(p *Profile) error {
	b, _ := json.Marshal(map[string]any{"name": p.Name, "timelineOffset": p.Offset})
	_, e := s.db.Exec(`INSERT OR REPLACE INTO member_profiles(id,payload) VALUES(?,?)`, p.UserID, string(b))
	return e
}
func finite(x float64) bool { return !math.IsNaN(x) && !math.IsInf(x, 0) }
func (s *Server) handleFeature(m *Member, p *peer, c Command, t float64) bool {
	r := s.rooms[m.RoomID]
	profile := s.profile(m)
	fail := func(code string) { s.send(p, map[string]any{"type": "ERROR", "error": code, "room": r}) }
	switch c.Type {
	case "PLAYER_STATUS", "PROFILE_UPDATE", "CHAT_MESSAGE", "CHAT_TYPING", "REACTION", "ROOM_SETTINGS", "ROOM_MEDIA", "ROOM_LEAVE", "ROOM_CLOSE":
	default:
		return false
	}
	if t-profile.Window >= 1000 {
		profile.Window = t
		profile.Events = 0
	}
	profile.Events++
	if profile.Events > 30 {
		fail("RATE_LIMIT")
		return true
	}
	switch c.Type {
	case "PLAYER_STATUS":
		var v struct {
			SourceID  string  `json:"sourceId"`
			Ready     bool    `json:"ready"`
			Buffering bool    `json:"buffering"`
			Position  float64 `json:"position"`
			Duration  float64 `json:"duration"`
		}
		if json.Unmarshal(c.Data, &v) != nil || !finite(v.Position) || !finite(v.Duration) || v.Position < 0 || v.Duration < 0 || v.Duration > 86400000 {
			fail("INVALID_STATUS")
			return true
		}
		wasReady, wasBuffering, wasSource := profile.Ready, profile.Buffering, profile.SourceID
		profile.Ready = v.Ready
		profile.SourceID = ""
		if validBaiduReference(r.MediaURL) {
			if v.SourceID == r.MediaURL {
				profile.SourceID = v.SourceID
			} else {
				profile.Ready = false
				v.Duration = 0
				v.Position = 0
			}
		}
		profile.Buffering = v.Buffering
		profile.Position = v.Position
		profile.Duration = v.Duration
		profile.LastSeen = t
		if s.telemetry != nil && (wasReady != profile.Ready || wasBuffering != profile.Buffering || wasSource != profile.SourceID) {
			s.telemetryMu.Lock()
			s.telemetry.Encode(map[string]any{"roomId": m.RoomID, "userId": m.ID, "serverTimestamp": t, "data": map[string]any{"diagnostic": true, "event": "serverReadinessChanged", "ready": profile.Ready, "buffering": profile.Buffering, "sourceMatched": !validBaiduReference(r.MediaURL) || profile.SourceID == r.MediaURL, "durationMs": profile.Duration, "positionMs": profile.Position, "version": r.Version}})
			s.telemetryMu.Unlock()
		}
		if m.ID == r.HostID && v.Duration > 0 {
			duration := v.Duration - profile.Offset
			if duration > 0 && math.Abs(r.Duration-duration) > 200 {
				next := *r
				next.Duration = duration
				if s.save(&next, nil) == nil {
					*r = next
				}
			}
		}
		// Persist a canonical anchor at most every two seconds, without changing
		// the command version. This prevents a restart rewinding to the last PLAY.
		if m.ID == r.HostID && r.State == "playing" && t >= r.ExecuteAt && t-r.UpdatedAt >= 2000 {
			next := *r
			next.Position = r.Timeline.At(t)
			next.UpdatedAt = t
			if s.save(&next, nil) == nil {
				*r = next
			}
		}
		s.updatePlayback(r, t)
	case "PROFILE_UPDATE":
		var v struct {
			Name   string  `json:"name"`
			Offset float64 `json:"timelineOffset"`
		}
		if json.Unmarshal(c.Data, &v) != nil || !finite(v.Offset) || math.Abs(v.Offset) > 600000 || utf8.RuneCountInString(strings.TrimSpace(v.Name)) > 32 {
			fail("INVALID_PROFILE")
			return true
		}
		next := *profile
		next.Name = strings.TrimSpace(v.Name)
		if next.Name == "" {
			next.Name = profile.Name
		}
		next.Offset = v.Offset
		if s.saveProfile(&next) != nil {
			fail("STORAGE")
			return true
		}
		*profile = next
		s.broadcast(r.ID, map[string]any{"type": "PRESENCE", "members": s.roster(r.ID), "serverTimestamp": t})
	case "CHAT_MESSAGE":
		var v struct {
			Text string `json:"text"`
			ID   string `json:"clientMessageId"`
		}
		if json.Unmarshal(c.Data, &v) != nil || utf8.RuneCountInString(v.Text) > 1000 || strings.TrimSpace(v.Text) == "" || len(v.ID) == 0 || len(v.ID) > 80 {
			fail("INVALID_MESSAGE")
			return true
		}
		if _, e := s.db.Exec(`INSERT OR IGNORE INTO messages(room_id,user_id,name,text,client_id,created_at) VALUES(?,?,?,?,?,?)`, r.ID, m.ID, profile.Name, v.Text, v.ID, t); e != nil {
			fail("STORAGE")
			return true
		}
		var msg Message
		if e := s.db.QueryRow(`SELECT id,user_id,name,text,client_id,created_at FROM messages WHERE room_id=? AND user_id=? AND client_id=?`, r.ID, m.ID, v.ID).Scan(&msg.ID, &msg.UserID, &msg.Name, &msg.Text, &msg.ClientID, &msg.Timestamp); e != nil {
			fail("STORAGE")
			return true
		}
		s.broadcast(r.ID, map[string]any{"type": "CHAT_MESSAGE", "message": msg})
		s.db.Exec(`DELETE FROM messages WHERE room_id=? AND id NOT IN(SELECT id FROM messages WHERE room_id=? ORDER BY id DESC LIMIT 500)`, r.ID, r.ID)
	case "CHAT_TYPING":
		s.broadcast(r.ID, map[string]any{"type": "CHAT_TYPING", "userId": m.ID, "name": profile.Name, "expiresAt": t + 3000})
	case "REACTION":
		var v struct {
			Emoji string `json:"emoji"`
		}
		json.Unmarshal(c.Data, &v)
		allowed := map[string]bool{"😂": true, "😱": true, "😭": true, "🤯": true, "❤️": true, "👀": true}
		if !allowed[v.Emoji] {
			fail("INVALID_REACTION")
			return true
		}
		s.broadcast(r.ID, map[string]any{"type": "REACTION", "userId": m.ID, "emoji": v.Emoji, "serverTimestamp": t})
	case "ROOM_SETTINGS", "ROOM_MEDIA":
		if m.ID != r.HostID {
			fail("HOST_REQUIRED")
			return true
		}
		if c.Sequence <= m.Sequence {
			fail("OLD_SEQUENCE")
			return true
		}
		if c.BaseVersion != r.Version {
			fail("STALE_VERSION")
			return true
		}
		next := *r
		member := *m
		member.Sequence = c.Sequence
		if c.Type == "ROOM_SETTINGS" {
			var v struct {
				Wait bool `json:"waitForPeer"`
			}
			if json.Unmarshal(c.Data, &v) != nil {
				fail("INVALID_SETTINGS")
				return true
			}
			next.WaitForPeer = v.Wait
			next.Version++
			if !v.Wait && next.AutoResume && (!validBaiduReference(next.MediaURL) || s.baiduReady(&next, t)) {
				next.Control("PLAY", 0, t)
				next.AutoResume = false
				next.PauseReason = ""
			}
		} else {
			var v struct {
				URL   string `json:"mediaUrl"`
				Title string `json:"title"`
			}
			if json.Unmarshal(c.Data, &v) != nil || !safeMediaURL(v.URL) || utf8.RuneCountInString(v.Title) > 160 {
				fail("INVALID_SOURCE")
				return true
			}
			next.MediaURL = v.URL
			next.Title = strings.TrimSpace(v.Title)
			next.Duration = 0
			next.AutoResume = false
			next.PauseReason = ""
			next.Control("SEEK", 0, t)
			next.Timeline.State = "paused"
			next.UpdatedAt = t
			next.ExecuteAt = t
			next.Before = next.Timeline
		}
		if s.save(&next, &member) != nil {
			fail("STORAGE")
			return true
		}
		*r = next
		*m = member
		if c.Type == "ROOM_MEDIA" {
			for _, v := range s.members {
				if v.RoomID == r.ID {
					q := s.profile(v)
					q.Ready = false
					q.SourceID = ""
					q.Duration = 0
					q.LastSeen = 0
				}
			}
		}
		s.broadcast(r.ID, s.snapshot(m, "STATE"))
	case "ROOM_CLOSE":
		if m.ID != r.HostID {
			fail("HOST_REQUIRED")
			return true
		}
		s.removeRoom(r.ID, "ROOM_CLOSE")
	case "ROOM_LEAVE":
		if m.ID == r.HostID {
			s.removeRoom(r.ID, "ROOM_CLOSE")
			return true
		}
		if _, e := s.db.Exec(`DELETE FROM members WHERE id=?`, m.ID); e != nil {
			fail("STORAGE")
			return true
		}
		s.db.Exec(`DELETE FROM member_profiles WHERE id=?`, m.ID)
		delete(s.members, m.ID)
		delete(s.profiles, m.ID)
		s.send(p, map[string]any{"type": "ROOM_LEAVE"})
		delete(s.peers, m.ID)
		s.broadcast(r.ID, map[string]any{"type": "PRESENCE", "members": s.roster(r.ID), "serverTimestamp": t})
	}
	return true
}
func (s *Server) autoControl(r *core.Room, kind, reason string, t float64) {
	next := *r
	next.Control(kind, 0, t)
	// Freeze a buffering room at a fresh stalled playhead, not several seconds
	// ahead of it. Seeking the stalled client forward can discard its recovery data.
	if kind == "PAUSE" && reason == "buffering" {
		for _, m := range s.members {
			if m.RoomID != r.ID {
				continue
			}
			p := s.profile(m)
			if s.peers[m.ID] == nil || p.LastSeen <= 0 || t-p.LastSeen >= 3000 || p.Duration <= 0 || (!p.Buffering && p.Ready) {
				continue
			}
			if validBaiduReference(r.MediaURL) && p.SourceID != r.MediaURL {
				continue
			}
			if finite(p.Position) && p.Position >= 0 && p.Position < next.Position {
				next.Position = p.Position
			}
		}
	}
	next.PauseReason = reason
	next.AutoResume = reason == "buffering" || reason == "disconnected"
	if s.save(&next, nil) != nil {
		return
	}
	*r = next
	if s.telemetry != nil {
		s.telemetryMu.Lock()
		s.telemetry.Encode(map[string]any{"roomId": r.ID, "serverTimestamp": t, "data": map[string]any{"diagnostic": true, "event": "automaticRoomControl", "operation": kind, "pauseReason": reason, "positionMs": r.Position, "autoResume": r.AutoResume, "version": r.Version}})
		s.telemetryMu.Unlock()
	}
	s.broadcast(r.ID, map[string]any{"type": "STATE", "room": r, "members": s.roster(r.ID), "serverTimestamp": t})
}
func (s *Server) updatePlayback(r *core.Room, t float64) {
	if t < r.ExecuteAt {
		return
	}
	pos, state := r.At(t)
	if state == "playing" && r.Duration > 0 && pos >= r.Duration {
		next := *r
		next.Control("PAUSE", 0, t)
		next.Position = r.Duration
		next.AutoResume = false
		next.PauseReason = "ended"
		if s.save(&next, nil) == nil {
			*r = next
			s.broadcast(r.ID, map[string]any{"type": "STATE", "room": r, "members": s.roster(r.ID), "serverTimestamp": t})
		}
		return
	}
	if !r.WaitForPeer && !validBaiduReference(r.MediaURL) {
		return
	}
	allReady := true
	if validBaiduReference(r.MediaURL) {
		allReady = s.baiduReady(r, t)
	}
	reason := ""
	for _, m := range s.members {
		if m.RoomID != r.ID {
			continue
		}
		p := s.profile(m)
		online := s.peers[m.ID] != nil && t-p.LastSeen < 5000 && p.LastSeen > 0
		ready := online && p.Ready && !p.Buffering && (!validBaiduReference(r.MediaURL) || p.SourceID == r.MediaURL)
		if !ready {
			allReady = false
			if p.WaitingSince == 0 {
				p.WaitingSince = t
			}
			if t-p.WaitingSince >= 2000 {
				if !online {
					reason = "disconnected"
				} else if reason == "" {
					reason = "buffering"
				}
			}
		} else {
			p.WaitingSince = 0
		}
	}
	if state == "playing" && reason != "" {
		s.autoControl(r, "PAUSE", reason, t)
	}
	if state == "paused" && r.AutoResume && allReady {
		s.autoControl(r, "PLAY", "", t)
	}
}
func (s *Server) removeRoom(id, kind string) {
	tx, e := s.db.Begin()
	if e != nil {
		return
	}
	defer tx.Rollback()
	for _, q := range []string{`DELETE FROM messages WHERE room_id=?`, `DELETE FROM member_profiles WHERE id IN(SELECT id FROM members WHERE room_id=?)`, `DELETE FROM members WHERE room_id=?`, `DELETE FROM rooms WHERE id=?`} {
		if _, e = tx.Exec(q, id); e != nil {
			return
		}
	}
	if tx.Commit() != nil {
		return
	}
	s.broadcast(id, map[string]any{"type": kind, "roomId": id})
	for uid, m := range s.members {
		if m.RoomID == id {
			delete(s.members, uid)
			delete(s.profiles, uid)
			delete(s.peers, uid)
		}
	}
	delete(s.rooms, id)
}
func (s *Server) runRooms() {
	defer close(s.finished)
	ticker := time.NewTicker(500 * time.Millisecond)
	defer ticker.Stop()
	for {
		select {
		case <-s.stop:
			return
		case <-ticker.C:
			s.mu.Lock()
			t := now()
			for id, r := range s.rooms {
				if r.ExpiresAt <= t {
					s.removeRoom(id, "ROOM_CLOSE")
				} else {
					s.refreshSpeedHolds(r, t)
					s.updatePlayback(r, t)
				}
			}
			s.mu.Unlock()
		}
	}
}
