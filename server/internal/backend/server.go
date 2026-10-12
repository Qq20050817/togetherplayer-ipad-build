package backend

import (
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"
	"unicode/utf8"

	"github.com/gorilla/websocket"
	_ "modernc.org/sqlite"
	"together/poc/internal/core"
)

type Member struct {
	ID, RoomID, Hash string
	Sequence         int64
}
type peer struct {
	ws  *websocket.Conn
	out chan []byte
}
type Server struct {
	mu          sync.Mutex
	db          *sql.DB
	rooms       map[string]*core.Room
	members     map[string]*Member
	peers       map[string]*peer
	telemetry   *json.Encoder
	telemetryMu sync.Mutex
	profiles    map[string]*Profile
	speedHolds  map[string]map[string]speedHold
	stop        chan struct{}
	finished    chan struct{}
	closeOnce   sync.Once
}
type Command struct {
	Type        string          `json:"type"`
	Sequence    int64           `json:"sequence"`
	BaseVersion int64           `json:"baseVersion"`
	Position    float64         `json:"position"`
	T1          float64         `json:"t1"`
	Data        json.RawMessage `json:"data"`
}

var clockBase = time.Now()

func now() float64 {
	return float64(clockBase.UnixNano())/1e6 + float64(time.Since(clockBase).Nanoseconds())/1e6
}
func random(n int) string {
	b := make([]byte, n)
	if _, e := rand.Read(b); e != nil {
		panic(e)
	}
	return hex.EncodeToString(b)
}
func hash(t string) string { v := sha256.Sum256([]byte(t)); return hex.EncodeToString(v[:]) }
func New(path string, telemetry *json.Encoder) (*Server, error) {
	db, e := sql.Open("sqlite", path)
	if e != nil {
		return nil, e
	}
	db.SetMaxOpenConns(1)
	_, e = db.Exec(`PRAGMA journal_mode=WAL; CREATE TABLE IF NOT EXISTS rooms(id TEXT PRIMARY KEY,payload TEXT NOT NULL); CREATE TABLE IF NOT EXISTS members(id TEXT PRIMARY KEY,room_id TEXT NOT NULL,token_hash TEXT NOT NULL,sequence INTEGER NOT NULL); CREATE TABLE IF NOT EXISTS member_profiles(id TEXT PRIMARY KEY,payload TEXT NOT NULL); CREATE TABLE IF NOT EXISTS messages(id INTEGER PRIMARY KEY AUTOINCREMENT,room_id TEXT NOT NULL,user_id TEXT NOT NULL,name TEXT NOT NULL,text TEXT NOT NULL,client_id TEXT NOT NULL,created_at REAL NOT NULL,UNIQUE(room_id,user_id,client_id));`)
	if e != nil {
		return nil, e
	}
	s := &Server{db: db, rooms: map[string]*core.Room{}, members: map[string]*Member{}, peers: map[string]*peer{}, telemetry: telemetry, profiles: map[string]*Profile{}, stop: make(chan struct{}), finished: make(chan struct{})}
	rows, e := db.Query("SELECT payload FROM rooms")
	if e != nil {
		return nil, e
	}
	for rows.Next() {
		var v string
		rows.Scan(&v)
		r := new(core.Room)
		if json.Unmarshal([]byte(v), r) == nil && r.ExpiresAt > now() {
			s.rooms[r.ID] = r
		}
	}
	rows.Close()
	// A process/VM restart loses live readiness. Restore the last saved anchor,
	// not a timeline advanced across downtime, and require explicit PLAY.
	for _, r := range s.rooms {
		if r.State == "playing" || r.AutoResume || r.Before.State == "playing" && now() < r.ExecuteAt {
			r.Version++
			r.Timeline = core.Timeline{State: "paused", Position: r.Position, UpdatedAt: now(), PlaybackRate: 1}
			r.Before = r.Timeline
			r.ExecuteAt = r.UpdatedAt
			r.AutoResume = false
			r.PauseReason = "server_restart"
			if e = s.save(r, nil); e != nil {
				db.Close()
				return nil, e
			}
		}
	}
	rows, e = db.Query("SELECT id,room_id,token_hash,sequence FROM members")
	if e != nil {
		return nil, e
	}
	for rows.Next() {
		m := new(Member)
		rows.Scan(&m.ID, &m.RoomID, &m.Hash, &m.Sequence)
		if s.rooms[m.RoomID] != nil {
			s.members[m.ID] = m
		}
	}
	rows.Close()
	rows, e = s.db.Query("SELECT id,payload FROM member_profiles")
	if e == nil {
		for rows.Next() {
			var id, b string
			rows.Scan(&id, &b)
			if m := s.members[id]; m != nil {
				p := s.profile(m)
				json.Unmarshal([]byte(b), p)
			}
		}
		rows.Close()
	}
	go s.runRooms()
	return s, nil
}
func (s *Server) Close() {
	s.closeOnce.Do(func() {
		close(s.stop)
		<-s.finished
		s.mu.Lock()
		defer s.mu.Unlock()
		for _, p := range s.peers {
			p.ws.Close()
		}
		s.db.Close()
	})
}
func safeMediaURL(raw string) bool {
	if strings.HasPrefix(raw, "baidu:") {
		return validBaiduReference(raw)
	}
	u, e := url.Parse(raw)
	if e != nil || u.Host == "" || (u.Scheme != "http" && u.Scheme != "https") || u.User != nil || len(raw) > 4096 {
		return false
	}
	for k := range u.Query() {
		switch strings.ToLower(k) {
		case "access_token", "refresh_token", "cookie", "password":
			return false
		}
	}
	return true
}
func (s *Server) save(r *core.Room, m *Member) error {
	tx, e := s.db.Begin()
	if e != nil {
		return e
	}
	defer tx.Rollback()
	if r != nil {
		b, _ := json.Marshal(r)
		_, e = tx.Exec("INSERT OR REPLACE INTO rooms VALUES(?,?)", r.ID, string(b))
		if e != nil {
			return e
		}
	}
	if m != nil {
		_, e = tx.Exec("INSERT OR REPLACE INTO members VALUES(?,?,?,?)", m.ID, m.RoomID, m.Hash, m.Sequence)
		if e != nil {
			return e
		}
	}
	return tx.Commit()
}
func reply(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}
func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", func(w http.ResponseWriter, r *http.Request) { reply(w, 200, map[string]any{"ok": true}) })
	mux.HandleFunc("POST /rooms", s.create)
	mux.HandleFunc("POST /rooms/{id}/join", s.join)
	mux.HandleFunc("GET /ws", s.socket)
	return mux
}
func (s *Server) create(w http.ResponseWriter, r *http.Request) {
	var req struct {
		MediaURL string `json:"mediaUrl"`
		Title    string `json:"title"`
	}
	r.Body = http.MaxBytesReader(w, r.Body, 4096)
	if json.NewDecoder(r.Body).Decode(&req) != nil {
		reply(w, 400, map[string]string{"error": "invalid body"})
		return
	}
	if !safeMediaURL(req.MediaURL) || utf8.RuneCountInString(req.Title) > 160 {
		reply(w, 400, map[string]string{"error": "HTTP(S) media URL required"})
		return
	}
	// The backend never requests the media URL. Supply only a public/licensed PoC test source.
	s.mu.Lock()
	defer s.mu.Unlock()
	if len(s.rooms) >= 1000 {
		reply(w, 429, map[string]string{"error": "room capacity"})
		return
	}
	token := random(32)
	id := random(4)
	uid := random(8)
	room := &core.Room{ID: id, HostID: uid, MediaURL: req.MediaURL, Version: 1, Title: req.Title, WaitForPeer: true, ExpiresAt: now() + 6*3600*1000, Timeline: core.Timeline{State: "paused", PlaybackRate: 1, UpdatedAt: now()}}
	room.Before = room.Timeline
	m := &Member{ID: uid, RoomID: id, Hash: hash(token)}
	if s.save(room, m) != nil {
		reply(w, 500, map[string]string{"error": "storage"})
		return
	}
	s.rooms[id] = room
	s.members[uid] = m
	reply(w, 201, map[string]any{"roomId": id, "userId": uid, "token": token, "room": room})
}
func (s *Server) join(w http.ResponseWriter, r *http.Request) {
	s.mu.Lock()
	defer s.mu.Unlock()
	room := s.rooms[r.PathValue("id")]
	if room == nil || room.ExpiresAt <= now() {
		reply(w, 404, map[string]string{"error": "room unavailable"})
		return
	}
	count := 0
	for _, m := range s.members {
		if m.RoomID == room.ID {
			count++
		}
	}
	if count >= 2 {
		reply(w, 409, map[string]string{"error": "room full; reuse existing credentials to reconnect"})
		return
	}
	token := random(32)
	m := &Member{ID: random(8), RoomID: room.ID, Hash: hash(token)}
	if s.save(nil, m) != nil {
		reply(w, 500, map[string]string{"error": "storage"})
		return
	}
	s.members[m.ID] = m
	reply(w, 201, map[string]any{"roomId": room.ID, "userId": m.ID, "token": token, "room": room})
}
func (s *Server) auth(r *http.Request) (*Member, error) {
	h := r.Header.Get("Authorization")
	if !strings.HasPrefix(h, "Bearer ") {
		return nil, errors.New("unauthorized")
	}
	v := hash(strings.TrimPrefix(h, "Bearer "))
	for _, m := range s.members {
		if m.Hash == v && s.rooms[m.RoomID] != nil && s.rooms[m.RoomID].ExpiresAt > now() {
			return m, nil
		}
	}
	return nil, errors.New("unauthorized")
}
func (s *Server) send(p *peer, v any) {
	b, e := json.Marshal(v)
	if e != nil {
		return
	}
	select {
	case p.out <- b:
	default:
		p.ws.Close()
	}
}
func (s *Server) broadcast(room string, v any) {
	for id, p := range s.peers {
		if s.members[id] != nil && s.members[id].RoomID == room {
			s.send(p, v)
		}
	}
}
func (s *Server) snapshot(m *Member, kind string) any {
	v := map[string]any{"type": kind, "room": s.rooms[m.RoomID], "members": s.roster(m.RoomID), "lastSequence": m.Sequence, "serverTimestamp": now()}
	if kind == "STATE" {
		v["ackUserId"] = m.ID
		v["ackSequence"] = m.Sequence
	}
	if kind == "WELCOME" {
		messages := s.history(m.RoomID)
		v["messages"] = messages
		// Existing public gateway permits 8 KiB per outgoing application frame.
		// Keep latest history that fits, including escaped UTF-8 JSON overhead.
		for len(messages) > 0 {
			b, _ := json.Marshal(v)
			if len(b) <= 7800 {
				break
			}
			messages = messages[1:]
			v["messages"] = messages
		}
	}
	return v
}
func (s *Server) socket(w http.ResponseWriter, r *http.Request) {
	s.mu.Lock()
	m, e := s.auth(r)
	s.mu.Unlock()
	if e != nil {
		http.Error(w, "unauthorized", 401)
		return
	}
	ws, e := (&websocket.Upgrader{CheckOrigin: func(r *http.Request) bool { return r.Header.Get("Origin") == "" }}).Upgrade(w, r, nil)
	if e != nil {
		return
	}
	p := &peer{ws: ws, out: make(chan []byte, 64)}
	ws.SetReadLimit(8192)
	ws.SetReadDeadline(time.Now().Add(45 * time.Second))
	ws.SetPongHandler(func(string) error { return ws.SetReadDeadline(time.Now().Add(45 * time.Second)) })
	s.mu.Lock()
	if old := s.peers[m.ID]; old != nil {
		old.ws.Close()
	}
	s.peers[m.ID] = p
	s.send(p, s.snapshot(m, "WELCOME"))
	s.mu.Unlock()
	done := make(chan struct{})
	stop := make(chan struct{})
	go func() {
		defer close(done)
		ticker := time.NewTicker(15 * time.Second)
		defer ticker.Stop()
		for {
			select {
			case <-stop:
				return
			case v := <-p.out:
				ws.SetWriteDeadline(time.Now().Add(5 * time.Second))
				if ws.WriteMessage(websocket.TextMessage, v) != nil {
					ws.Close()
					return
				}
			case <-ticker.C:
				ws.SetWriteDeadline(time.Now().Add(5 * time.Second))
				if ws.WriteMessage(websocket.PingMessage, nil) != nil {
					ws.Close()
					return
				}
			}
		}
	}()
	defer func() {
		close(stop)
		ws.Close()
		s.mu.Lock()
		if s.peers[m.ID] == p {
			delete(s.peers, m.ID)
			s.releaseSpeedHold(m.RoomID, m.ID, now())
		}
		s.mu.Unlock()
		select {
		case <-done:
		case <-time.After(6 * time.Second):
		}
	}()
	for {
		var c Command
		if ws.ReadJSON(&c) != nil {
			return
		}
		ws.SetReadDeadline(time.Now().Add(45 * time.Second))
		s.mu.Lock()
		if s.peers[m.ID] != p {
			s.mu.Unlock()
			return
		}
		s.handle(m, p, c)
		s.mu.Unlock()
	}
}
func (s *Server) handle(m *Member, p *peer, c Command) {
	t2 := now()
	room := s.rooms[m.RoomID]
	fail := func(code string) { s.send(p, map[string]any{"type": "ERROR", "error": code, "room": room}) }
	if room == nil || room.ExpiresAt <= t2 {
		fail("EXPIRED")
		p.ws.Close()
		return
	}
	if c.Type == "SPEED_HOLD" {
		s.handleSpeedHold(m, p, c, t2)
		return
	}
	if s.handleFeature(m, p, c, t2) {
		return
	}
	switch c.Type {
	case "PING":
		s.send(p, map[string]any{"type": "PONG", "t1": c.T1, "t2": t2, "t3": now()})
	case "SYNC":
		s.send(p, s.snapshot(m, "SYNC"))
	case "PLAY", "PAUSE", "SEEK", "REPLAY":
		if m.ID != room.HostID {
			fail("HOST_REQUIRED")
			return
		}
		if c.Sequence <= m.Sequence {
			fail("OLD_SEQUENCE")
			return
		}
		if c.BaseVersion != room.Version {
			fail("STALE_VERSION")
			return
		}
		if validBaiduReference(room.MediaURL) && (c.Type == "PLAY" || c.Type == "REPLAY") && !s.baiduReady(room, t2) {
			fail("SOURCE_NOT_READY")
			return
		}
		if math.IsNaN(c.Position) || math.IsInf(c.Position, 0) || c.Position < 0 || c.Position > 86400000 {
			fail("INVALID_POSITION")
			return
		}
		next := *room
		if c.Type == "SEEK" && room.Duration > 0 && c.Position > room.Duration {
			fail("SEEK_AFTER_END")
			return
		}
		next.Control(c.Type, c.Position, t2)
		next.AutoResume = false
		next.PauseReason = ""
		nm := *m
		nm.Sequence = c.Sequence
		if s.save(&next, &nm) != nil {
			fail("STORAGE")
			return
		}
		*room = next
		*m = nm
		if s.telemetry != nil {
			s.telemetryMu.Lock()
			s.telemetry.Encode(map[string]any{"kind": "control", "roomId": m.RoomID, "userId": m.ID, "serverTimestamp": t2, "type": c.Type, "room": room})
			s.telemetryMu.Unlock()
		}
		s.broadcast(m.RoomID, s.snapshot(m, "STATE"))
	case "CONTROL_REQUEST":
		var requested Command
		if json.Unmarshal(c.Data, &requested) != nil || (requested.Type != "PLAY" && requested.Type != "PAUSE" && requested.Type != "SEEK" && requested.Type != "REPLAY") || !finite(requested.Position) || requested.Position < 0 || requested.Position > 86400000 {
			fail("INVALID_REQUEST")
			return
		}
		if c.Sequence <= m.Sequence {
			fail("OLD_SEQUENCE")
			return
		}
		nm := *m
		nm.Sequence = c.Sequence
		if s.save(nil, &nm) != nil {
			fail("STORAGE")
			return
		}
		*m = nm
		if host := s.peers[room.HostID]; host != nil {
			s.send(host, map[string]any{"type": "CONTROL_REQUEST", "userId": m.ID, "data": c.Data})
		} else {
			fail("HOST_OFFLINE")
		}
	case "TELEMETRY":
		if s.telemetry != nil {
			s.telemetryMu.Lock()
			s.telemetry.Encode(map[string]any{"roomId": m.RoomID, "userId": m.ID, "serverTimestamp": t2, "data": c.Data})
			s.telemetryMu.Unlock()
		}
	default:
		fail("UNKNOWN_TYPE")
	}
}
func (s *Server) String() string { return fmt.Sprintf("Together PoC") }
