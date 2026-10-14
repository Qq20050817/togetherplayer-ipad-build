import Foundation

struct VoiceNoiseGate {
 let threshold:Double
 private var openUntil=0.0
 init(threshold:Double) {self.threshold=threshold}
 mutating func accepts(rms:Double,now:Double)->Bool {
  if rms.isFinite && rms >= threshold {openUntil=now+0.2}
  return now<openUntil
 }
}

enum VoiceVocabulary {
 static let common=["弹幕","取消弹幕","伏笔","反转","线索","嫌疑人","不在场证明","时间线","动机","误导","剪辑","配音","字幕","音轨","简体中文","繁体中文","生化危机"]
 static func hints(_ custom:String)->[String] {
  var seen=Set<String>()
  let words=String(custom.prefix(4000)).components(separatedBy:CharacterSet(charactersIn:"\n,，;；"))+common
  return Array(words.compactMap {raw->String? in
   let word=raw.trimmingCharacters(in:.whitespacesAndNewlines)
   guard !word.isEmpty,word.count<=30,!word.unicodeScalars.contains(where:CharacterSet.controlCharacters.contains),seen.insert(word).inserted else {return nil}
   return word
  }.prefix(100))
 }
}

/// Speech callbacks may contain a single phrase or the whole request so far.
/// Merge by recognition request and audio range, not by blindly appending text.
/// Identical words spoken at a later audio range remain legitimate repetition.
struct VoiceRecognitionDraft {
 private struct Piece {
  var text:String
  let window:Int?
  let epoch:Int
  let start:TimeInterval?
  let end:TimeInterval?
 }
 private var committed:[Piece]=[]
 private var current=""
 private var recognitionWindow:Int?
 private var finalizedWindow:Int?
 private var currentStart:TimeInterval?
 private var currentEnd:TimeInterval?
 private var epoch=0
 var text:String {(committed.map(\.text)+[current]).filter {!$0.isEmpty}.joined(separator:" ")}
 private mutating func commitCurrent() {
  if !current.isEmpty {committed.append(Piece(text:current,window:recognitionWindow,epoch:epoch,start:currentStart,end:currentEnd))}
  current="";currentStart=nil;currentEnd=nil
 }
 private static func compact(_ text:String)->String {
  String(String.UnicodeScalarView(text.unicodeScalars.filter {!CharacterSet.whitespacesAndNewlines.contains($0) && !CharacterSet.punctuationCharacters.contains($0)}))
 }
 private static func resembles(_ lhs:String,_ rhs:String)->Bool {
  let a=compact(lhs),b=compact(rhs)
  guard !a.isEmpty,!b.isEmpty else {return false}
  if a.hasPrefix(b) || b.hasPrefix(a) {return true}
  let short=min(a.count,b.count)
  let aa=Array(a),bb=Array(b)
  if short>=4 {
   let tolerance=max(1,short/5)
   if aa.count==bb.count,zip(aa,bb).filter({$0.0 != $0.1}).count<=tolerance {return true}
   let small=aa.count<=bb.count ? aa : bb,large=aa.count<=bb.count ? bb : aa
   if large.count-small.count<=tolerance {
    var matched=0
    for character in large where matched<small.count {if character==small[matched] {matched+=1}}
    if matched==small.count {return true}
   }
  }
  let prefix=zip(a,b).prefix(while:{$0.0==$0.1}).count
  return short>=4 && Double(prefix)/Double(short)>=0.6
 }
 mutating func accept(_ value:String,final:Bool,start:TimeInterval?=nil,end:TimeInterval?=nil,window:Int?=nil) {
  if let window {
   if recognitionWindow != window {
    commitCurrent();recognitionWindow=window;epoch=0
   }
   if finalizedWindow == window {return}
  }
  let trimmed=value.trimmingCharacters(in:.whitespacesAndNewlines)
  if !trimmed.isEmpty {
   let rangeValid=start.map {$0.isFinite && $0>=0} == true && end.map {$0.isFinite && $0 >= (start ?? 0)} == true
   if rangeValid,let start,let end {
    // Some local recognizers restart their timestamp origin after silence
    // without sending a final callback. Preserve the previous phrase when
    // the audio time rolls back and the text is a genuinely new hypothesis.
    if let previousEnd=currentEnd,end<previousEnd-0.5,!Self.resembles(current,trimmed) {
     commitCurrent();epoch+=1
    } else if !current.isEmpty,let previousStart=currentStart,let previousEnd=currentEnd,
              start>=previousEnd,start>previousStart,!Self.resembles(current,trimmed) {
     commitCurrent()
    }
    // A later cumulative/final callback can cover already committed phrases
    // in this request. Replace those ranges once rather than duplicating them.
    let mergeWindow=recognitionWindow,mergeEpoch=epoch
    committed.removeAll {piece in
     guard piece.window==mergeWindow,piece.epoch==mergeEpoch,
           let oldStart=piece.start,let oldEnd=piece.end else {return false}
     return start<=oldStart+0.25 && end>=oldEnd-0.25
    }
    currentStart=start;currentEnd=end
   } else {
    // A final may omit segment times. Recognize a cumulative prefix only
    // inside this request/epoch; never delete repeats across new recordings.
    let mergeWindow=recognitionWindow,mergeEpoch=epoch
    let same=committed.filter {$0.window==mergeWindow && $0.epoch==mergeEpoch}
    let prefix=Self.compact(same.map(\.text).joined())
    if !prefix.isEmpty,Self.compact(trimmed).hasPrefix(prefix) {
     committed.removeAll {$0.window==mergeWindow && $0.epoch==mergeEpoch}
    }
   }
   current=trimmed
  }
  if final,!current.isEmpty {
   commitCurrent();finalizedWindow=window
   if window==nil {epoch+=1}
  }
 }
}
