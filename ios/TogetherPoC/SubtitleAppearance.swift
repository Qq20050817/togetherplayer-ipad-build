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
 static func lineSpacing(_ value:Double)->Double {value.isFinite ? min(20,max(0,value)) : 0}
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
  if let index=events.firstIndex(where:{abs($0.time-time)<0.001}) {events[index]=Event(time:time,text:text)}
  else {events.append(Event(time:time,text:text));events.sort {$0.time<$1.time}}
 }
 mutating func text(at time:Double)->String {
  guard time.isFinite,time>=0 else {return ""}
  // Preserve the final event before the history window and all upcoming events.
  if let keep=events.lastIndex(where:{$0.time<time-150}),keep>0 {events.removeFirst(keep)}
  return events.last(where:{$0.time<=time})?.text ?? ""
 }
}
