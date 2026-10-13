import Foundation

// A valid evidence ID only proves that a subtitle exists. Automatic questions
// must also contain a concrete quote from a recently played subtitle; this
// prevents generic questions from borrowing unrelated evidence IDs.
enum PlotGrounding {
 static func normalized(_ value:String)->String {
  value.lowercased().filter { $0.isLetter || $0.isNumber }
 }
 static func verified(_ question:PlotQuestion,context:PlotContext)->Bool {
  guard context.sufficient,
   let raw=question.anchorQuote,
   (4...40).contains(raw.count),
   !question.evidenceIDs.isEmpty else {return false}
  let quote=normalized(raw),written=normalized(question.text)
  guard quote.count>=4,written.contains(quote) else {return false}
  let emptyAnchors:Set<String>=["这个人","那个人","刚才的事","接下来","不知道","为什么","怎么回事","你觉得","你认为","某个人"]
  guard !emptyAnchors.contains(quote) else {return false}
  let identifiers=Set(question.evidenceIDs)
  let recent=Array(context.recent.filter {
   $0.source != "ondevice-vision" && $0.end<=context.cutoff &&
   context.cutoff-$0.end<=150
  }.suffix(12))
  guard !recent.isEmpty else{return false}
  return recent.contains {cue in
   identifiers.contains(cue.id) &&
   normalized(cue.text).contains(quote) &&
   // Never turn a very short caption into an automatic interruption.
   normalized(cue.text).count>=7
  }
 }
}
