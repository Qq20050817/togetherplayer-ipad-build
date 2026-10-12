package backend

import (
	"regexp"
	"strconv"
	"strings"
	"together/poc/internal/core"
)

// A room carries a source identity, never an account URL/token. The nonce makes
// selecting even the same movie again a fresh playback session.
var baiduReferencePattern = regexp.MustCompile(`^baidu://[a-f0-9]{32}/[a-f0-9]{32}/[1-9][0-9]{0,15}$`)

func validBaiduReference(value string) bool {
	if !baiduReferencePattern.MatchString(value) {
		return false
	}
	size, err := strconv.ParseInt(value[strings.LastIndex(value, "/")+1:], 10, 64)
	return err == nil && size <= 9007199254740991
}
func (s *Server) baiduReady(r *core.Room, t float64) bool {
	count := 0
	for _, m := range s.members {
		if m.RoomID != r.ID {
			continue
		}
		count++
		p := s.profile(m)
		if s.peers[m.ID] == nil || p.SourceID != r.MediaURL || !p.Ready || p.Buffering || p.Duration <= 0 || p.LastSeen <= 0 || t-p.LastSeen >= 5000 {
			return false
		}
	}
	// Require every registered member, not two members unconditionally. An
	// offline guest still participates in this gate; a genuinely solo room can
	// play once its own current source is ready.
	return count > 0
}
