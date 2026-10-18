package backend

import (
 "encoding/json"
 "strings"
)

// p2pSignal is a strictly bounded, authenticated signaling envelope.
// Membership comes from the already-authorized Muse WebSocket, not from
// client-supplied source IDs. Never forward room tokens or movie data.
type p2pSignal struct {
 TargetUserID string          `json:"targetUserId"`
 Kind         string          `json:"kind"`
 Payload      json.RawMessage `json:"payload"`
}

// handleP2PSignal is called with the existing Server.mu held.
// It never changes authoritative room state, sequence, media or player ACK.
func (s *Server) handleP2PSignal(m *Member, p *peer, c Command, timestamp float64) {
 fail := func(code string) {
  s.send(p, map[string]any{"type":"ERROR","error":code})
 }
 if len(c.Data) < 10 || len(c.Data) > 6000 {
  fail("P2P_BAD_SIGNAL")
  return
 }
 var signal p2pSignal
 if json.Unmarshal(c.Data,&signal) != nil {
  fail("P2P_BAD_SIGNAL")
  return
 }
 switch signal.Kind {
 case "offer","answer","candidate","reset":
 default:
  fail("P2P_BAD_KIND")
  return
 }
 if signal.TargetUserID == "" || signal.TargetUserID == m.ID || len(signal.TargetUserID) > 160 || strings.TrimSpace(signal.TargetUserID) != signal.TargetUserID {
  fail("P2P_BAD_PEER")
  return
 }
 var payload map[string]json.RawMessage
 if len(signal.Payload) < 2 || len(signal.Payload)>5500 || json.Unmarshal(signal.Payload,&payload) != nil || payload == nil {
  fail("P2P_BAD_PAYLOAD")
  return
 }
 switch signal.Kind {
 case "offer","answer":
  var sdp string
  if json.Unmarshal(payload["sdp"],&sdp) != nil || len(sdp)==0 || len(sdp)>5000 {
   fail("P2P_BAD_PAYLOAD")
   return
  }
 case "candidate":
  var candidate string
  if json.Unmarshal(payload["candidate"],&candidate) != nil || len(candidate)==0 || len(candidate)>1500 {
   fail("P2P_BAD_PAYLOAD")
   return
  }
 }
 target:=s.members[signal.TargetUserID]
 if target==nil || target.RoomID!=m.RoomID {
  fail("P2P_BAD_PEER")
  return
 }
 recipient:=s.peers[target.ID]
 if recipient==nil {
  fail("P2P_PEER_OFFLINE")
  return
 }
 if timestamp-p.p2pWindowStarted>30_000 {
  p.p2pWindowStarted=timestamp
  p.p2pWindowCount=0
 }
 p.p2pWindowCount++
 if p.p2pWindowCount>80 {
  fail("P2P_RATE_LIMIT")
  return
 }
 s.send(recipient,map[string]any{
  "type":"P2P_SIGNAL",
  "fromUserId":m.ID,
  "data":map[string]any{
   "kind":signal.Kind,
   "payload":signal.Payload,
  },
 })
}
