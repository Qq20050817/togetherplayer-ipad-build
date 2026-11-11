import Foundation

struct MovieMindCoverage {
  struct Interval: Codable, Equatable {
    let start: Int64
    let end: Int64
  }
  struct Batch {
    let intervals: [Interval]
    let elapsedMs: Int64
    let rate: Double
  }
  private struct Sample {
    let position: Int64
    let now: Int64
    let playing: Bool
    let rate: Double
  }
  private var previous: Sample?
  private var intervals = [Interval]()
  private var elapsed: Int64 = 0
  private var batchRate = 1.0
  mutating func discontinuity() { previous = nil }
  mutating func sample(position: Int64, now: Int64, playing: Bool, rate: Double) {
    guard position >= 0, rate.isFinite, (0.25...4).contains(rate) else {
      previous = nil
      return
    }
    let old = previous
    previous = Sample(position: position, now: now, playing: playing, rate: rate)
    guard let old, playing, old.playing else { return }
    let dt = now - old.now
    let delta = position - old.position
    let maximumRate = max(old.rate, rate)
    let expected = Double(dt) * (old.rate + rate) / 2
    guard dt > 0, dt <= 2000, delta > 0,
      abs(Double(delta) - expected) <= max(80, Double(dt) * maximumRate * 0.15)
    else { return }
    // A conservative validation bound only; coverage always uses actual ranges.
    batchRate = intervals.isEmpty ? maximumRate : max(batchRate, maximumRate)
    elapsed += dt
    if let last = intervals.last, last.end == old.position {
      intervals[intervals.count - 1] = Interval(start: last.start, end: position)
    } else {
      intervals.append(Interval(start: old.position, end: position))
    }
  }
  mutating func drain() -> Batch? {
    guard !intervals.isEmpty else { return nil }
    let batch = Batch(intervals: intervals, elapsedMs: elapsed, rate: batchRate)
    intervals = []
    elapsed = 0
    return batch
  }
}
