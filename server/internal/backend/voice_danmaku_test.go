package backend

import (
	"encoding/json"
	"fmt"
	"testing"
)

// Reuse the authenticated chat protocol; no room schema or production migration.
func TestVoiceDanmakuTwentyEachDirectionAndRetryDedup(t *testing.T) {
	s, h, g, r, a, b := featureRoom(t)
	s.mu.Lock()
	defer s.mu.Unlock()
	seen := map[float64]bool{}
	clock := now()
	for direction := 0; direction < 2; direction++ {
		sender, connection := h, a
		if direction == 1 {
			sender, connection = g, b
		}
		for n := 0; n < 20; n++ {
			id := fmt.Sprintf("voice:test-%d-%d", direction, n)
			raw, _ := json.Marshal(map[string]any{"text": fmt.Sprintf("语音 %d", n), "clientMessageId": id, "source": "voice", "userId": "spoof", "roomId": "spoof"})
			c := Command{Type: "CHAT_MESSAGE", Data: raw}
			clock += 600
			s.handleFeature(sender, connection, c, clock)
			left := featureEvent(t, a)["message"].(map[string]any)
			right := featureEvent(t, b)["message"].(map[string]any)
			if left["userId"] != sender.ID || right["clientMessageId"] != id || left["id"] != right["id"] {
				t.Fatal("identity/transport mismatch")
			}
			messageID := left["id"].(float64)
			if seen[messageID] {
				t.Fatal("duplicate new message")
			}
			seen[messageID] = true
			clock += 600
			s.handleFeature(sender, connection, c, clock)
			if featureEvent(t, a)["message"].(map[string]any)["id"] != messageID || featureEvent(t, b)["message"].(map[string]any)["id"] != messageID {
				t.Fatal("retry changed message ID")
			}
		}
	}
	if len(s.history(r.ID)) != 40 || len(seen) != 40 {
		t.Fatal("missing or duplicate persisted messages")
	}
}
