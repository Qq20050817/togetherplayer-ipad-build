import Foundation

/// A recording lease must verify the shared session every time. Other players
/// may change AVAudioSession even while this voice feature remains enabled.
@MainActor final class VoiceRecordingSession {
 private var acquired=false
 private let isCurrent:()->Bool
 private let activate:() throws -> Void
 private let release:() throws -> Void
 init(isCurrent:@escaping ()->Bool,activate:@escaping () throws -> Void,release:@escaping () throws -> Void) {
  self.isCurrent=isCurrent;self.activate=activate;self.release=release
 }
 func prepare() throws {
  if acquired && isCurrent() {return}
  acquired=true
  try activate()
 }
 func restore() throws {guard acquired else {return};acquired=false;try release()}
}
