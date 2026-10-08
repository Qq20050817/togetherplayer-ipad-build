import Foundation

/// Transport-independent confirmation gate shared by live speech and UI tests.
struct VoiceSendGate {
 enum Phase {case idle,recording,finishing,review}
 private(set) var phase=Phase.idle
 private(set) var room=""
 var text=""
 var limit=300
 mutating func begin(room:String) {self.room=room;text="";phase = .recording}
 mutating func finish() {if phase == .recording {phase = .finishing}}
 mutating func review(_ value:String) {guard phase == .finishing else {return};text=value.trimmingCharacters(in:.whitespacesAndNewlines);phase = .review}
 mutating func cancel() {phase = .idle;text="";room=""}
 mutating func confirm(room:String,send:(String)->Bool)->Bool {
  let value=text.trimmingCharacters(in:.whitespacesAndNewlines)
  guard phase == .review,!room.isEmpty,room==self.room,!value.isEmpty,value.unicodeScalars.count<=limit else {return false}
  guard send(value) else {return false}
  cancel();return true
 }
}
