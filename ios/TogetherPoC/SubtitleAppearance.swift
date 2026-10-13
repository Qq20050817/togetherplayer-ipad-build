import Foundation

enum SubtitleFontFamily:String,CaseIterable,Identifiable {
 case system,rounded,serif
 var id:String {rawValue}
 var label:String {switch self {case .system:return "系统";case .rounded:return "圆体";case .serif:return "衬线"}}
}
enum SubtitleFontWeight:String,CaseIterable,Identifiable {
 case light,regular,semibold,bold
 var id:String {rawValue}
 var label:String {switch self {case .light:return "细体";case .regular:return "常规";case .semibold:return "半粗";case .bold:return "粗体"}}
}

struct SubtitleAppearance: Equatable {
 var fontSize: Double=24
 var bottomFraction: Double=0.07
 static func font(_ value:Double)->Double {value.isFinite ? min(64,max(16,value)) : 24}
 static func letterSpacing(_ value:Double)->Double {value.isFinite ? min(6,max(-2,value)) : 0}
 static func lineSpacing(_ value:Double)->Double {value.isFinite ? min(20,max(-8,value)) : 0}
 static func position(_ value:Double)->Double {value.isFinite ? min(0.85,max(0.02,value)) : 0.07}
}

// Legible output supplies both text and empty end events on the player's clock.
// Keeping upcoming events permits earlier as well as later presentation.
struct NativeSubtitleTimeline {
 struct Event {let time:Double;let text:String}
 private(set) var events:[Event]=[]
 mutating func clear() {events=[]}
 mutating func receive(text:String,time:Double) {
  guard time.isFinite else {return}
  if let index=events.firstIndex(where:{abs($0.time-time)<0.001}) {
   // HLS can deliver a cue-end (empty) and a new cue-start at the same
   // presentation time in either callback order. The nonempty cue wins.
   if text.isEmpty && !events[index].text.isEmpty {return}
   events[index]=Event(time:time,text:text)
  } else {
   // Most native callbacks are monotonic, including callbacks delivered ahead
   // of playback. Avoid sorting the full two-hour history on every subtitle.
   if events.last.map({$0.time<=time}) ?? true {events.append(Event(time:time,text:text))}
   else {
    var low=0,high=events.count
    while low<high {
     let middle=(low+high)/2
     if events[middle].time<time {low=middle+1} else {high=middle}
    }
    events.insert(Event(time:time,text:text),at:low)
   }
   // Bound long-running sessions without discarding recent subtitle context.
   if events.count>24_000 {events.removeFirst(events.count-20_000)}
  }
 }
 // Only completed text intervals can enter plot prompts; ahead-of-playback
 // legible callbacks and an open-ended final cue must never leak future text.
 func completedText(before cutoff:Double,limit:Int=22)->[String] {
  guard cutoff.isFinite,cutoff>=0,events.count>1 else {return []}
  return Array(zip(events,events.dropFirst()).filter{!$0.0.text.isEmpty && $0.1.time<=cutoff}.map{$0.0.text}.suffix(max(0,limit)))
 }
 mutating func text(at time:Double)->String {
  guard time.isFinite,time>=0 else {return ""}
  // Keep this item's history: AVFoundation may not replay already delivered
  // cues after a backward seek. Item and track changes clear it separately.
  var lower=0,upper=events.count
  while lower<upper {
   let middle=(lower+upper)/2
   if events[middle].time<=time {lower=middle+1} else {upper=middle}
  }
  return lower>0 ? events[lower-1].text : ""
 }
}

// The subtitle's percentage is relative to the visible movie, excluding letterbox bars.
enum SubtitlePictureLayout {
 static func picture(container:CGSize,presentation:CGSize)->CGSize {
  let ratio=presentation.width>0 && presentation.height>0 ? presentation.width/presentation.height : 16.0/9.0
  let width=min(container.width,container.height*ratio)
  return CGSize(width:width,height:width/ratio)
 }
 static func bottom(container:CGSize,picture:CGSize,fraction:Double,textHeight:CGFloat,inset:Double)->CGFloat {
  let inside=min(max(16,picture.height*CGFloat(SubtitleAppearance.position(fraction)))+CGFloat(inset),max(16,picture.height-textHeight-16))
  return max(0,(container.height-picture.height)/2)+inside
 }
}
