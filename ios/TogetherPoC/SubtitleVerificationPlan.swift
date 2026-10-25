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
 /// Audio-only sampling is deliberately independent of any subtitle track.
 /// The legacy subtitleStartSeconds field transports the audio time coordinate;
 /// it must never be interpreted as an independently verified caption timestamp.
 static func audioOnlySamples(duration:Double)->[SubtitleVerificationSample] {
  guard duration.isFinite,duration>=90 else {return []}
  var result:[SubtitleVerificationSample]=[]
  for third in 0..<3 {
   let lower=duration*Double(third)/3
   let upper=duration*Double(third+1)/3
   for slot in 0..<3 {
    let centre=lower+(upper-lower)*Double(slot+1)/4
    let start=min(max(lower,centre-5),upper-10)
    result.append(.init(index:result.count+1,startSeconds:start,
                        durationSeconds:10,subtitleStartSeconds:start))
   }
  }
  return result
 }

 /// Retry in the same film third when the initial window is quiet.
 /// Only these short windows are decoded. No full-film scanning or caching.
 static func audioOnlyCandidateStarts(for sample:SubtitleVerificationSample,
                                      duration:Double)->[Double] {
  guard duration.isFinite,duration>=90,(1...9).contains(sample.index) else {return []}
  let third=(sample.index-1)/3
  let lower=duration*Double(third)/3
  let upper=duration*Double(third+1)/3
  var positions:[Double]=[]
  for shift in [0.0,20.0,-20.0,55.0,-55.0] {
   let next=min(max(lower,sample.startSeconds+shift),upper-sample.durationSeconds)
   if next.isFinite && !positions.contains(where:{abs($0-next)<1.0}) {
    positions.append(next)
   }
  }
  return Array(positions.prefix(3))
 }

}

 
/// Conservative, local PCM activity estimate used to avoid uploading silence.
/// Energy, zero crossings and amplitude modulation can suggest speech but
/// cannot prove human dialogue; this does not perform ASR or subtitle matching.
enum FilmAudioSpeechActivity {
 static func score(pcm16le:Data)->Double {
  let samplesPerFrame=320 // 20ms at 16 kHz
  let bytesPerFrame=samplesPerFrame*2
  let frames=pcm16le.count/bytesPerFrame
  guard frames>=400 else{return 0}
  return pcm16le.withUnsafeBytes {raw in
   var levels:[Double]=[]
   levels.reserveCapacity(frames)
   for frame in 0..<frames {
    let first=frame*bytesPerFrame
    var magnitude=0
    var crossings=0
    var last=0
    for sample in 0..<samplesPerFrame {
     let offset=first+sample*2
     let bits=UInt16(raw[offset]) | (UInt16(raw[offset+1]) << 8)
     let value=Int(Int16(bitPattern:bits))
     magnitude += abs(value)
     if sample>0 && ((value<0) != (last<0)) {crossings += 1}
     last=value
    }
    let mean=Double(magnitude)/Double(samplesPerFrame)
    if mean>=90 && (3...115).contains(crossings) {levels.append(mean)}
   }
   guard levels.count>=25 else{return 0}
   let mean=levels.reduce(0,+)/Double(levels.count)
   let variance=levels.reduce(0) {$0+($1-mean)*($1-mean)}/Double(levels.count)
   let modulation=sqrt(variance)/max(1,mean)
   return Double(levels.count)/Double(frames)*min(1,modulation*1.6+0.08)
  }
 }
}
