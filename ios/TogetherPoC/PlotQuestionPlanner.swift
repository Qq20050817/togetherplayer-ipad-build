import Foundation

// Preselect discussion REGIONS, not answers. A full subtitle document may be
// examined locally for timing only; future dialogue is never supplied to AI.
struct PlotQuestionCheckpoint:Equatable {
 let at:Double
 let score:Int
}

enum PlotQuestionPlanner {
 static func indexed(_ source:[SubtitleCue])->[PlotQuestionCheckpoint] {
  let cues=source.filter{$0.start.isFinite && $0.end.isFinite && $0.end>$0.start}.sorted{$0.start<$1.start}
  guard cues.count>=6,let duration=cues.last?.end,duration>=360 else{return []}
  let bucketSize=max(240,min(480,duration/7))
  let maximum=min(8,max(2,Int(duration/360)))
  var buckets:[Int:PlotQuestionCheckpoint]=[:]
  for index in cues.indices {
   let cue=cues[index]
   guard cue.end>=max(120,duration*0.04),cue.end<=duration-60,index>=3 else{continue}
   let following=index+1<cues.count ? cues[index+1].start : duration
   let pause=following-cue.end
   guard pause>=2.2 else{continue}
   let at=cue.end+min(3.5,max(2.1,pause/2))
   guard at<following else{continue}
   let earliest=max(0,index-14)
   let recent=Array(cues[earliest...index].filter{$0.end>=at-95})
   guard recent.count>=3 else{continue}
   let observed=recent.map{PlotEvidence.cue(start:$0.start,end:$0.end,text:$0.text,source:"external-subtitle")}
   let beat=PlotMomentGate.assess(observed,position:at)
   let richness=recent.suffix(5).reduce(0){$0+$1.text.count}
   guard beat.isCandidate || beat.importance>=15 || (richness>=75 && pause>=4) else{continue}
   let score=beat.importance+(beat.isCandidate ? 80 : 0)+min(16,richness/18)+min(16,Int(pause*2))
   let key=Int(at/bucketSize)
   if let earlier=buckets[key],earlier.score>=score {continue}
   buckets[key]=PlotQuestionCheckpoint(at:at,score:score)
  }
  // Prefer content-rich scenes, then return selected stops in story order.
  let ranked=buckets.values.sorted{$0.score == $1.score ? $0.at<$1.at : $0.score>$1.score}
  var chosen:[PlotQuestionCheckpoint]=[]
  for candidate in ranked {
   guard chosen.allSatisfy({abs($0.at-candidate.at)>=180}) else{continue}
   chosen.append(candidate)
   if chosen.count==maximum {break}
  }
  return chosen.sorted{$0.at<$1.at}
 }
 // Embedded subtitle tracks do not expose the entire transcript up front.
 // Duration landmarks are only opportunities for evidence-based evaluation.
 static func durationCheckpoints(_ duration:Double)->[PlotQuestionCheckpoint] {
  guard duration.isFinite,duration>=360 else{return []}
  let fractions:[Double]=[0.06,0.19,0.33,0.48,0.63,0.78,0.91]
  var result:[PlotQuestionCheckpoint]=[]
  for fraction in fractions {
   let at=duration*fraction
   guard at>=120,at<=duration-60,
    result.last.map({at-$0.at>=180}) ?? true else{continue}
   result.append(PlotQuestionCheckpoint(at:at,score:0))
  }
  return result
 }
 static func active(_ checkpoints:[PlotQuestionCheckpoint],at position:Double)->Double? {
  guard position.isFinite,position>=0 else{return nil}
  return checkpoints.first(where:{$0.at<=position && position-$0.at<=55})?.at
 }
 static func hasWatchedEvidence(_ evidence:[PlotEvidence],at position:Double)->Bool {
  guard position.isFinite,position>=0 else{return false}
  let recent=evidence.filter{
   $0.start.isFinite && $0.end.isFinite && $0.start>=0 &&
   $0.end<position && $0.end>=position-150
  }
  guard let last=recent.last,position-last.end<=105 else{return false}
  let subtitles=recent.filter{$0.source != "ondevice-vision"}
  let visuals=recent.filter{$0.source == "ondevice-vision"}
  // Multiple already played cues can support a question even when there is no
  // suspicious keyword. Visual-only prompts require real category changes.
  if subtitles.count>=3{return true}
  let differentScenes=Set(visuals.map(\.text)).count>=2
  return differentScenes && ((subtitles.count>=1 && visuals.count>=3) || visuals.count>=4)
 }
}
