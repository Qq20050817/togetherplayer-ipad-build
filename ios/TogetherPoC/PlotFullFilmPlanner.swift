import Foundation

/// Build a question context at a selected moment from a complete transcript.
/// Future dialogue never enters the model prompt or the current plot memory.
enum PlotFullFilmPlanner {
 static func context(_ document:SubtitleDocument,at cutoff:Double,source:String)->PlotContext {
  guard cutoff.isFinite,cutoff>=0 else{return PlotContext(cutoff:0,recent:[],earlier:[],predictions:[])}
  let lines=Array(document.cues.filter{
   $0.start.isFinite && $0.end.isFinite && $0.start>=0 &&
   $0.end>$0.start && $0.end<=cutoff && $0.end>=cutoff-240
  }.suffix(24))
  let evidence=lines.map {
   PlotEvidence.cue(start:$0.start,end:$0.end,text:$0.text,source:source)
  }
  return PlotContext(cutoff:cutoff,recent:evidence,earlier:[],predictions:[])
 }
}
