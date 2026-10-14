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
 struct Event {let time:Double;let text:String;var end:Double?=nil}
 private(set) var events:[Event]=[]
 mutating func clear() {events=[]}
 mutating func receive(text:String,time:Double,end:Double?=nil) {
  guard time.isFinite else {return}
  let validEnd=end.flatMap{$0.isFinite && $0>time ? $0 : nil}
  if let index=events.firstIndex(where:{abs($0.time-time)<0.001}) {
   // HLS can deliver a cue-end (empty) and a new cue-start at the same
   // presentation time in either callback order. The nonempty cue wins.
   if text.isEmpty && !events[index].text.isEmpty {return}
   events[index]=Event(time:time,text:text,end:validEnd ?? events[index].end)
  } else {events.append(Event(time:time,text:text,end:validEnd));events.sort {$0.time<$1.time}}
 }
 // Only completed text intervals can enter plot prompts; ahead-of-playback
 // legible callbacks and an open-ended final cue must never leak future text.
 func completedIntervals(before cutoff:Double)->[(start:Double,end:Double,text:String)] {
  guard cutoff.isFinite,cutoff>=0 else{return []}
  return events.indices.compactMap {index in
   let event=events[index]
   guard !event.text.isEmpty else{return nil}
   let next=index+1<events.count ? events[index+1].time : nil
   let end:Double?
   if let known=event.end {end=next.map{min(known,$0)} ?? known} else {end=next}
   guard let end,end>event.time,end<=cutoff else{return nil}
   return (event.time,end,event.text)
  }
 }
 func completedText(before cutoff:Double,limit:Int=22)->[String] {
  Array(completedIntervals(before:cutoff).map(\.text).suffix(max(0,limit)))
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
  guard lower>0 else{return ""}
  let event=events[lower-1]
  if let end=event.end,time>=end {return ""}
  return event.text
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
