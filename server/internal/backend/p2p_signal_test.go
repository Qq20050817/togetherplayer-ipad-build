package backend

import (
 "encoding/json"
 "net/http/httptest"
 "path/filepath"
 "testing"
)

func p2pWire(target,kind string,payload any) Command {
 data,_:=json.Marshal(map[string]any{
  "targetUserId":target,
  "kind":kind,
  "payload":payload,
 })
 return Command{Type:"P2P_SIGNAL",Data:data}
}

func TestP2PAuthorizedRelayDoesNotMutateMovieRoom(t *testing.T) {
 s,err:=New(filepath.Join(t.TempDir(),"db"),nil)
 if err!=nil {t.Fatal(err)}
 defer s.Close()
 ts:=httptest.NewServer(s.Handler())
 defer ts.Close()
 host:=post(t,ts.URL+"/rooms",`{"mediaUrl":"https://example.org/movie.mp4"}`,201)
 guest:=post(t,ts.URL+"/rooms/"+host.RoomID+"/join",`{}`,201)
 h,g:=dial(t,ts.URL,host),dial(t,ts.URL,guest)
 defer h.Close()
 defer g.Close()
 before:=read(t,h)["room"].(map[string]any)["version"]
 read(t,g)
 offer:=p2pWire(guest.UserID,"offer",map[string]any{"sdp":"v=0\r\na=example"})
 write(t,h,offer)
 msg:=read(t,g)
 if msg["type"]!="P2P_SIGNAL" || msg["fromUserId"]!=host.UserID {
  t.Fatalf("message not tagged with authenticated sender: %v",msg)
 }
 data,ok:=msg["data"].(map[string]any)
 if !ok || data["kind"]!="offer" {t.Fatalf("missing p2p offer: %v",msg)}
 write(t,g,p2pWire(host.UserID,"answer",map[string]any{"sdp":"v=0\r\na=reply"}))
 response:=read(t,h)
 if response["fromUserId"]!=guest.UserID {t.Fatalf("wrong sender: %v",response)}
 write(t,h,Command{Type:"SYNC"})
 after:=read(t,h)["room"].(map[string]any)["version"]
 if before!=after {t.Fatalf("P2P modified authoritative room version: %v -> %v",before,after)}
}

func TestP2PRejectsInvalidKindTargetPayloadAndRateLimit(t *testing.T) {
 s,err:=New(filepath.Join(t.TempDir(),"db"),nil)
 if err!=nil {t.Fatal(err)}
 defer s.Close()
 ts:=httptest.NewServer(s.Handler())
 defer ts.Close()
 host:=post(t,ts.URL+"/rooms",`{"mediaUrl":"https://example.org/movie.mp4"}`,201)
 guest:=post(t,ts.URL+"/rooms/"+host.RoomID+"/join",`{}`,201)
 other:=post(t,ts.URL+"/rooms",`{"mediaUrl":"https://example.org/other.mp4"}`,201)
 h,g:=dial(t,ts.URL,host),dial(t,ts.URL,guest)
 defer h.Close()
 defer g.Close()
 read(t,h);read(t,g)
 cases:=[]struct{command Command; errorCode string}{
  {p2pWire(host.UserID,"offer",map[string]any{"sdp":"v=0"}),"P2P_BAD_PEER"},
  {p2pWire(other.UserID,"offer",map[string]any{"sdp":"v=0"}),"P2P_BAD_PEER"},
  {p2pWire(guest.UserID,"not-allowed",map[string]any{"sdp":"v=0"}),"P2P_BAD_KIND"},
  {p2pWire(guest.UserID,"offer",map[string]any{"sdp":""}),"P2P_BAD_PAYLOAD"},
  {p2pWire(guest.UserID,"candidate",map[string]any{"candidate":""}),"P2P_BAD_PAYLOAD"},
 }
 for _,tc:=range cases {
  write(t,h,tc.command)
  actual:=read(t,h)
  if actual["error"]!=tc.errorCode {t.Fatalf("got %v, want %s",actual,tc.errorCode)}
 }
 s.mu.Lock()
 s.peers[host.UserID].p2pWindowStarted=now()
 s.peers[host.UserID].p2pWindowCount=80
 s.mu.Unlock()
 write(t,h,p2pWire(guest.UserID,"offer",map[string]any{"sdp":"v=0"}))
 if response:=read(t,h);response["error"]!="P2P_RATE_LIMIT" {t.Fatalf("missing limit: %v",response)}
}
