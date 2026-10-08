import AVFoundation

@MainActor final class VoiceVolumeDucker {
 private weak var player:AVPlayer?
 private var original:Float?
 private(set) var userVolume:Float
 private var ramp:Task<Void,Never>?
 init(player:AVPlayer) {self.player=player;userVolume=player.volume}
 func begin() {
  guard let player=player else {return}
  if original==nil {original=player.volume;userVolume=player.volume}
  transition(to:(original ?? 0)*0.22)
 }
 func setUserVolume(_ value:Float) {
  let volume=max(0,min(1,value));userVolume=volume
  if original != nil {original=volume;transition(to:volume*0.22)} else {ramp?.cancel();player?.volume=volume}
 }
 func end() {guard let original=original else {return};self.original=nil;transition(to:original)}
 private func transition(to target:Float) {
  ramp?.cancel();guard let player=player else {return};let from=player.volume
  ramp=Task { [weak player] in
   for step in 1...15 {
    guard !Task.isCancelled,let player=player else {return}
    let t=Float(step)/15;let eased=t*t*(3-2*t)
    player.volume=from+(target-from)*eased
    try? await Task.sleep(nanoseconds:20_000_000)
   }
  }
 }
}
