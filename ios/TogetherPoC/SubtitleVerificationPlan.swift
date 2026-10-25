import Foundation

/// Nine dialogue-anchored samples for an ordinary subtitle synchronisation check.
/// This plan never edits the selected playback subtitles or requests the full film.
struct SubtitleVerificationSample: Equatable, Codable {
 let index: Int
 let startSeconds: Double
 let durationSeconds: Double
 let subtitleStartSeconds: Double
}

enum SubtitleVerificationPlan {
 static func samples(document: SubtitleDocument, duration: Double) -> [SubtitleVerificationSample] {
  guard duration.isFinite, duration >= 90 else { return [] }
  let dialogue = document.cues.filter {
   $0.start.isFinite && $0.end.isFinite && $0.start >= 0 && $0.end > $0.start &&
   $0.start < duration - 6 && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
  var result: [SubtitleVerificationSample] = []
  for third in 0..<3 {
   let lower = duration * Double(third) / 3
   let upper = duration * Double(third + 1) / 3
   let candidates = dialogue.filter { $0.start >= lower && $0.start < upper }
   guard candidates.count >= 3 else { return [] }
   var used = Set<Int>()
   for slot in 0..<3 {
    let target = lower + (upper-lower) * Double(slot+1) / 4
    let nearest = candidates.indices.filter { !used.contains($0) }.min {
     abs(candidates[$0].start-target) < abs(candidates[$1].start-target)
    }
    guard let nearest else { return [] }
    used.insert(nearest)
    let cue = candidates[nearest]
    let start = min(max(0,cue.start-1.5),duration-10)
    result.append(.init(index:result.count+1,startSeconds:start,
                        durationSeconds:10,subtitleStartSeconds:cue.start))
   }
  }
  return result
 }
}
