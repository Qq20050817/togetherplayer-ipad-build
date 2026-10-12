// Uses actual loopback WebSocket I/O; this is not a video playback benchmark.
package main

import (
	"encoding/json"
	"fmt"
	"github.com/gorilla/websocket"
	"math"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"time"
	"together/poc/internal/backend"
)

func must(err error) {
	if err != nil {
		panic(err)
	}
}
func main() {
	dir, e := os.MkdirTemp("", "together-probe-")
	must(e)
	defer os.RemoveAll(dir)
	s, e := backend.New(filepath.Join(dir, "test.db"), nil)
	must(e)
	defer s.Close()
	srv := httptest.NewServer(s.Handler())
	defer srv.Close()
	post := func(path, body string) map[string]any {
		res, e := http.Post(srv.URL+path, "application/json", strings.NewReader(body))
		must(e)
		defer res.Body.Close()
		if res.StatusCode != 201 {
			panic(res.Status)
		}
		var v map[string]any
		must(json.NewDecoder(res.Body).Decode(&v))
		return v
	}
	host := post("/rooms", `{"mediaUrl":"https://example.org/licensed-test.mp4"}`)
	guest := post("/rooms/"+host["roomId"].(string)+"/join", `{}`)
	dial := func(auth map[string]any) *websocket.Conn {
		h := http.Header{}
		h.Set("Authorization", "Bearer "+auth["token"].(string))
		c, _, e := websocket.DefaultDialer.Dial(strings.Replace(srv.URL, "http", "ws", 1)+"/ws", h)
		must(e)
		return c
	}
	read := func(c *websocket.Conn) map[string]any {
		c.SetReadDeadline(time.Now().Add(5 * time.Second))
		var v map[string]any
		must(c.ReadJSON(&v))
		return v
	}
	h, g := dial(host), dial(guest)
	defer h.Close()
	defer g.Close()
	read(h)
	read(g)
	sum, maxRTT := 0.0, 0.0
	for i := 0; i < 100; i++ {
		start := time.Now()
		must(h.WriteJSON(map[string]any{"type": "PING", "t1": float64(start.UnixNano()) / 1e6}))
		v := read(h)
		if v["type"] != "PONG" {
			panic(v)
		}
		rtt := float64(time.Since(start).Nanoseconds()) / 1e6
		sum += rtt
		maxRTT = math.Max(maxRTT, rtt)
	}
	version := int64(1)
	broadcastTotal, broadcastMax := 0.0, 0.0
	for i := 1; i <= 30; i++ {
		kind := []string{"PLAY", "PAUSE", "SEEK"}[(i-1)%3]
		start := time.Now()
		must(h.WriteJSON(map[string]any{"type": kind, "sequence": i, "baseVersion": version, "position": 120000}))
		read(h)
		v := read(g)
		if v["type"] != "STATE" {
			panic(v)
		}
		version = int64(v["room"].(map[string]any)["version"].(float64))
		elapsed := float64(time.Since(start).Nanoseconds()) / 1e6
		broadcastTotal += elapsed
		broadcastMax = math.Max(broadcastMax, elapsed)
	}
	g.Close()
	g = dial(guest)
	defer g.Close()
	v := read(g)
	restored := v["room"].(map[string]any)["version"] == float64(version)
	enc := json.NewEncoder(os.Stdout)
	enc.SetIndent("", "  ")
	must(enc.Encode(map[string]any{"kind": "actual_loopback_websocket_protocol_test", "pingSamples": 100, "meanRttMs": sum / 100, "maxRttMs": maxRTT, "operations": 30, "meanBroadcastMs": broadcastTotal / 30, "maxBroadcastMs": broadcastMax, "reconnectRestored": restored, "videoDecoded": false, "note": "Loopback only; does not measure Muse or mobile network latency."}))
	if !restored {
		panic(fmt.Sprint(v))
	}
}
