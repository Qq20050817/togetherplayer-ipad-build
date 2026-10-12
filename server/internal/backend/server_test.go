package backend

import (
	"bytes"
	"encoding/json"
	"github.com/gorilla/websocket"
	"io"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

type login struct {
	RoomID string `json:"roomId"`
	UserID string `json:"userId"`
	Token  string `json:"token"`
}

func post(t *testing.T, url, body string, status int) login {
	t.Helper()
	r, e := http.Post(url, "application/json", strings.NewReader(body))
	if e != nil {
		t.Fatal(e)
	}
	defer r.Body.Close()
	if r.StatusCode != status {
		b, _ := io.ReadAll(r.Body)
		t.Fatal(r.StatusCode, string(b))
	}
	var l login
	json.NewDecoder(r.Body).Decode(&l)
	return l
}
func dial(t *testing.T, url string, l login) *websocket.Conn {
	t.Helper()
	h := http.Header{}
	h.Set("Authorization", "Bearer "+l.Token)
	c, _, e := websocket.DefaultDialer.Dial(strings.Replace(url, "http", "ws", 1)+"/ws", h)
	if e != nil {
		t.Fatal(e)
	}
	return c
}
func read(t *testing.T, c *websocket.Conn) map[string]any {
	t.Helper()
	c.SetReadDeadline(time.Now().Add(2 * time.Second))
	var v map[string]any
	if e := c.ReadJSON(&v); e != nil {
		t.Fatal(e)
	}
	return v
}
func write(t *testing.T, c *websocket.Conn, v any) {
	t.Helper()
	if e := c.WriteJSON(v); e != nil {
		t.Fatal(e)
	}
}
func TestRoomProtocolRestartAndPermissions(t *testing.T) {
	path := filepath.Join(t.TempDir(), "db.sqlite")
	s, e := New(path, nil)
	if e != nil {
		t.Fatal(e)
	}
	ts := httptest.NewServer(s.Handler())
	host := post(t, ts.URL+"/rooms", `{"mediaUrl":"https://example.org/licensed.mp4"}`, 201)
	guest := post(t, ts.URL+"/rooms/"+host.RoomID+"/join", `{}`, 201)
	post(t, ts.URL+"/rooms/"+host.RoomID+"/join", `{}`, 409)
	_, res, e := websocket.DefaultDialer.Dial(strings.Replace(ts.URL, "http", "ws", 1)+"/ws", nil)
	if e == nil || res.StatusCode != 401 {
		t.Fatal("unauthenticated upgrade accepted")
	}
	h, g := dial(t, ts.URL, host), dial(t, ts.URL, guest)
	read(t, h)
	read(t, g)
	write(t, g, Command{Type: "PLAY", Sequence: 1, BaseVersion: 1})
	if read(t, g)["error"] != "HOST_REQUIRED" {
		t.Fatal("guest can control")
	}
	write(t, g, Command{Type: "CONTROL_REQUEST", Sequence: 1, Data: json.RawMessage(`{"type":"PLAY"}`)})
	if read(t, h)["type"] != "CONTROL_REQUEST" {
		t.Fatal("missing host request")
	}
	write(t, h, Command{Type: "PLAY", Sequence: 1, BaseVersion: 1})
	a, b := read(t, h), read(t, g)
	if a["type"] != "STATE" || b["type"] != "STATE" {
		t.Fatal(a, b)
	}
	room := a["room"].(map[string]any)
	if room["version"] != float64(2) || room["state"] != "playing" || room["executeAt"].(float64) <= now() {
		t.Fatal(room)
	}
	write(t, h, Command{Type: "PAUSE", Sequence: 1, BaseVersion: 2})
	if read(t, h)["error"] != "OLD_SEQUENCE" {
		t.Fatal("duplicate command accepted")
	}
	write(t, h, Command{Type: "SEEK", Sequence: 2, BaseVersion: 1})
	if read(t, h)["error"] != "STALE_VERSION" {
		t.Fatal("stale command accepted")
	}
	write(t, h, Command{Type: "SEEK", Sequence: 2, BaseVersion: 2, Position: 120000})
	read(t, h)
	read(t, g)
	write(t, g, Command{Type: "PING", T1: 123})
	pong := read(t, g)
	if pong["t1"] != float64(123) || pong["t3"].(float64) < pong["t2"].(float64) {
		t.Fatal(pong)
	}
	g.Close()
	g = dial(t, ts.URL, guest)
	welcome := read(t, g)
	if welcome["room"].(map[string]any)["version"] != float64(3) {
		t.Fatal("reconnect stale")
	}
	h.Close()
	g.Close()
	ts.Close()
	s.Close()
	s, e = New(path, nil)
	if e != nil {
		t.Fatal(e)
	}
	defer s.Close()
	ts = httptest.NewServer(s.Handler())
	defer ts.Close()
	h = dial(t, ts.URL, host)
	defer h.Close()
	welcome = read(t, h)
	if welcome["room"].(map[string]any)["version"] != float64(3) || welcome["room"].(map[string]any)["state"] != "paused" || welcome["lastSequence"] != float64(2) {
		t.Fatal("restart lost state", welcome)
	}
}
func TestTelemetryAndNoMediaFetch(t *testing.T) {
	fetched := false
	media := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { fetched = true }))
	defer media.Close()
	var out bytes.Buffer
	s, e := New(filepath.Join(t.TempDir(), "db"), json.NewEncoder(&out))
	if e != nil {
		t.Fatal(e)
	}
	defer s.Close()
	ts := httptest.NewServer(s.Handler())
	defer ts.Close()
	host := post(t, ts.URL+"/rooms", `{"mediaUrl":"`+media.URL+`/video.mp4"}`, 201)
	c := dial(t, ts.URL, host)
	defer c.Close()
	read(t, c)
	write(t, c, Command{Type: "TELEMETRY", Data: json.RawMessage(`{"errorMs":42}`)})
	write(t, c, Command{Type: "SYNC"})
	read(t, c)
	if fetched {
		t.Fatal("backend fetched video")
	}
	if !strings.Contains(out.String(), `"errorMs":42`) {
		t.Fatal("missing telemetry")
	}
}
