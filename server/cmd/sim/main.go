// Virtual-time simulation of the Go drift policy, not a device/video benchmark.
package main

import (
	"encoding/json"
	"math"
	"math/rand"
	"os"
	"together/poc/internal/core"
)

type delivery struct {
	at   float64
	room core.Room
}
type client struct {
	room                                     core.Room
	queue                                    []delivery
	position, speed, offset, ppm, decoderPPM float64
	playing, offline, buffering              bool
	seekUntil                                float64
	seeks                                    int
}

func main() {
	rng := rand.New(rand.NewSource(842619))
	r := core.Room{Version: 1, Timeline: core.Timeline{State: "paused", PlaybackRate: 1}, Before: core.Timeline{State: "paused", PlaybackRate: 1}}
	clients := []*client{{room: r, speed: 1, ppm: 80, decoderPPM: 800}, {room: r, speed: 1, ppm: -100, decoderPPM: -1000}}
	type event struct {
		at       float64
		kind     string
		position float64
	}
	events := []event{{1000, "PLAY", 0}}
	for i := 0; i < 10; i++ {
		at := float64(90000 + i*140000)
		events = append(events, event{at, "PAUSE", 0}, event{at + 5000, "PLAY", 0}, event{at + 45000, "SEEK", float64(300000 + i*110000)})
	}
	next := 0
	sum, maxNormal, maxAll := 0.0, 0.0, 0.0
	count, within := 0, 0
	lastCommand := -1e9
	recoveries := []float64{}
	seekingAt := -1.0
	seekStable := -1.0
	lastClock := -1e9
	finalErrors := []float64{}
	for t := 0.0; t <= 1800000; t += 20 {
		if next < len(events) && t >= events[next].at {
			e := events[next]
			r.Control(e.kind, e.position, t)
			lastCommand = r.ExecuteAt
			if e.kind == "SEEK" {
				seekingAt = r.ExecuteAt
				seekStable = -1
			}
			next++
			for _, c := range clients {
				c.queue = append(c.queue, delivery{t + 30 + rng.Float64()*90, r})
			}
		}
		if t-lastClock >= 15000 {
			lastClock = t
			for _, c := range clients {
				// best of 5 NTP exchanges: asymmetric 20..100ms paths, 2ms server handling.
				best := 1e9
				for i := 0; i < 5; i++ {
					up, down := 20+rng.Float64()*80, 20+rng.Float64()*80
					t1 := t * (1 + c.ppm/1e6)
					t2 := t + up
					t3 := t2 + 2
					t4 := (t + up + 2 + down) * (1 + c.ppm/1e6)
					rtt := (t4 - t1) - (t3 - t2)
					if rtt < best {
						best = rtt
						c.offset = ((t2 - t1) + (t3 - t4)) / 2
					}
				}
			}
		}
		for i, c := range clients {
			wasOffline := c.offline
			c.offline = i == 1 && t >= 950000 && t < 955000
			c.buffering = i == 1 && ((t >= 420000 && t < 424000) || (t >= 760000 && t < 764000) || (t >= 1180000 && t < 1184000))
			if wasOffline && !c.offline {
				c.room = r
				c.queue = nil
			}
			for len(c.queue) > 0 && c.queue[0].at <= t {
				d := c.queue[0]
				c.queue = c.queue[1:]
				if !c.offline && d.room.Version > c.room.Version {
					c.room = d.room
				}
			}
			if c.playing && !c.buffering && !c.offline && t >= c.seekUntil {
				c.position += 20 * c.speed * (1 + c.decoderPPM/1e6)
			}
			if int(t)%100 == 0 && !c.offline && !c.buffering && t >= c.seekUntil {
				p, state := c.room.At(t*(1+c.ppm/1e6) + c.offset)
				c.speed, _ = core.Correct(p-c.position, state == "playing")
				_, seek := core.Correct(p-c.position, state == "playing")
				if seek {
					c.position = p
					c.seekUntil = t + 80
					c.seeks++
				}
				c.playing = state == "playing"
			}
		}
		if int(t)%100 == 0 {
			delta := math.Abs(clients[0].position - clients[1].position)
			maxAll = math.Max(maxAll, delta)
			if seekingAt >= 0 && t >= seekingAt {
				if delta < 500 && t >= clients[0].seekUntil && t >= clients[1].seekUntil {
					if seekStable < 0 {
						seekStable = t
					}
					if t-seekStable >= 1000 {
						recoveries = append(recoveries, seekStable-seekingAt)
						seekingAt = -1
					}
				} else {
					seekStable = -1
				}
			}
			normal := t > 5000 && t-lastCommand > 2000 && !clients[1].offline && !clients[1].buffering && t > clients[0].seekUntil+2000 && t > clients[1].seekUntil+2000
			if normal {
				sum += delta
				count++
				maxNormal = math.Max(maxNormal, delta)
				if delta < 500 {
					within++
				}
			}
		}
	}
	for _, c := range clients {
		p, _ := r.At(1800000)
		finalErrors = append(finalErrors, c.position-p)
	}
	meanSeek, maxSeek := 0.0, 0.0
	for _, n := range recoveries {
		meanSeek += n
		maxSeek = math.Max(maxSeek, n)
	}
	if len(recoveries) > 0 {
		meanSeek /= float64(len(recoveries))
	}
	report := map[string]any{"kind": "virtual_time_model_not_device_test", "seed": 842619, "durationSeconds": 1800, "meanNormalPairErrorMs": sum / float64(count), "maxNormalPairErrorMs": maxNormal, "maxAllPairErrorMs": maxAll, "normalSamplesBelow500Percent": 100 * float64(within) / float64(count), "seekRecoveryMeanMs": meanSeek, "seekRecoveryMaxMs": maxSeek, "seekRecoveries": len(recoveries), "finalCanonicalErrorsMs": finalErrors, "finalPairErrorMs": math.Abs(clients[0].position - clients[1].position), "hardSeeks": []int{clients[0].seeks, clients[1].seeks}, "bufferSimulations": 3, "disconnectSimulations": 1, "websocketLatencyMs": nil, "note": "No real WebSocket, decoder or device. Recovery requires 1s continuously below 500ms. Normal excludes buffering, disconnect, and 2s after commands/seeks."}
	enc := json.NewEncoder(os.Stdout)
	enc.SetIndent("", "  ")
	enc.Encode(report)
	if maxNormal >= 500 || len(recoveries) != 10 {
		os.Exit(1)
	}
}
