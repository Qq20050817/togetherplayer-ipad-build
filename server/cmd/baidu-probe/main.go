// Control-only deployed integration probe. It uses synthetic source identity,
// does not authorize Baidu or read any video, and closes its temporary room.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"github.com/gorilla/websocket"
	"net/http"
	"strings"
	"time"
)

func main() {
	base := flag.String("server", "http://127.0.0.1:18080", "control service")
	flag.Parse()
	must := func(err error) {
		if err != nil {
			panic("control probe failed")
		}
	}
	post := func(path, body string) map[string]any {
		req, err := http.NewRequest("POST", *base+path, strings.NewReader(body))
		must(err)
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("User-Agent", "Mozilla/5.0 TogetherPlayer/0.2.9")
		client := http.Client{Timeout: 10 * time.Second}
		response, err := client.Do(req)
		must(err)
		defer response.Body.Close()
		if response.StatusCode != 201 {
			panic(fmt.Sprintf("control REST status %d", response.StatusCode))
		}
		var result map[string]any
		must(json.NewDecoder(response.Body).Decode(&result))
		return result
	}
	reference := "baidu://" + strings.Repeat("1", 32) + "/" + strings.Repeat("a", 32) + "/5"
	body, _ := json.Marshal(map[string]string{"mediaUrl": reference, "title": "Baidu control integration probe"})
	host := post("/rooms", string(body))
	dial := func(auth map[string]any) *websocket.Conn {
		headers := http.Header{}
		headers.Set("Authorization", "Bearer "+auth["token"].(string))
		headers.Set("User-Agent", "Mozilla/5.0 TogetherPlayer/0.2.9")
		d := websocket.Dialer{HandshakeTimeout: 10 * time.Second, Proxy: http.ProxyFromEnvironment}
		connection, response, err := d.Dial(strings.Replace(*base, "http", "ws", 1)+"/ws", headers)
		if err != nil {
			if response != nil {
				panic(fmt.Sprintf("WebSocket handshake status %d", response.StatusCode))
			}
			panic(fmt.Sprintf("WebSocket handshake error type %T", err))
		}
		return connection
	}
	a := dial(host)
	defer a.Close()
	// Cleanup even if an assertion fails after the handshake.
	defer a.WriteJSON(map[string]string{"type": "ROOM_CLOSE"})
	read := func(c *websocket.Conn, kind string) map[string]any {
		must(c.SetReadDeadline(time.Now().Add(10 * time.Second)))
		for i := 0; i < 30; i++ {
			var result map[string]any
			must(c.ReadJSON(&result))
			if result["type"] == kind {
				return result
			}
		}
		panic("expected control event missing")
	}
	send := func(c *websocket.Conn, message any) { must(c.WriteJSON(message)) }
	welcome := read(a, "WELCOME")
	version := welcome["room"].(map[string]any)["version"]
	send(a, map[string]any{"type": "PLAY", "sequence": 1, "baseVersion": version})
	if read(a, "ERROR")["error"] != "SOURCE_NOT_READY" {
		panic("missing source gate")
	}
	status := map[string]any{"ready": true, "buffering": false, "position": 0, "duration": 120000, "sourceId": reference}
	send(a, map[string]any{"type": "PLAYER_STATUS", "data": status})
	send(a, map[string]any{"type": "SYNC"})
	read(a, "SYNC")
	send(a, map[string]any{"type": "PLAY", "sequence": 2, "baseVersion": version})
	solo := read(a, "STATE")["room"].(map[string]any)
	if solo["state"] != "playing" {
		panic("solo matched PLAY failed")
	}
	send(a, map[string]any{"type": "PAUSE", "sequence": 3, "baseVersion": solo["version"]})
	paused := read(a, "STATE")["room"].(map[string]any)
	if paused["state"] != "paused" {
		panic("solo PAUSE failed")
	}
	version = paused["version"]
	guest := post("/rooms/"+host["roomId"].(string)+"/join", "{}")
	b := dial(guest)
	defer b.Close()
	read(b, "WELCOME")
	send(a, map[string]any{"type": "PLAY", "sequence": 4, "baseVersion": version})
	if read(a, "ERROR")["error"] != "SOURCE_NOT_READY" {
		panic("unready joining guest bypassed source gate")
	}
	for _, c := range []*websocket.Conn{b, a} {
		send(c, map[string]any{"type": "PLAYER_STATUS", "data": status})
		send(c, map[string]any{"type": "SYNC"})
		read(c, "SYNC")
	}
	send(a, map[string]any{"type": "PLAY", "sequence": 5, "baseVersion": version})
	state := read(a, "STATE")["room"].(map[string]any)
	if state["state"] != "playing" || read(b, "STATE")["room"].(map[string]any)["mediaUrl"] != reference {
		panic("unified PLAY failed")
	}
	status["sourceId"] = "old-test-film"
	send(b, map[string]any{"type": "PLAYER_STATUS", "data": status})
	send(b, map[string]any{"type": "SYNC"})
	read(b, "SYNC")
	send(a, map[string]any{"type": "PLAY", "sequence": 6, "baseVersion": state["version"]})
	if read(a, "ERROR")["error"] != "SOURCE_NOT_READY" {
		panic("stale source accepted")
	}
	send(a, map[string]any{"type": "ROOM_CLOSE"})
	read(a, "ROOM_CLOSE")
	read(b, "ROOM_CLOSE")
	fmt.Println(`{"ok":true,"soloPlay":true,"soloPause":true,"unreadyJoiningGuestBlocked":true,"twoWebSockets":true,"missingSourceBlocked":true,"matchedPlay":true,"staleSourceBlocked":true,"temporaryRoomClosed":true,"videoDecoded":false,"realBaiduAuthorizationTested":false}`)
}
