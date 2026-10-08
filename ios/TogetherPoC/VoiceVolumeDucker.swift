import AVFoundation
import UIKit

@MainActor final class VoiceVolumeDucker {
 private weak var player:AVPlayer?
 private var original:Float?
 private(set) var userVolume:Float
 private var displayLink:CADisplayLink?
 private var from:Float=0
 private var target:Float=0
 private var started=0.0
 private var recordingGain:Float=0
 private lazy var ticker=VolumeTicker(owner:self)
 init(player:AVPlayer) {self.player=player;userVolume=player.volume}
 deinit {displayLink?.invalidate()}
 func begin() {
  guard let player=player else {return}
  if original==nil {original=player.volume;userVolume=player.volume}
  let headphones:Set<AVAudioSession.Port>=[.headphones,.bluetoothA2DP,.bluetoothLE,.bluetoothHFP]
  recordingGain=AVAudioSession.sharedInstance().currentRoute.outputs.contains {headphones.contains($0.portType)} ? 0.22 : 0
  transition(to:(original ?? 0)*recordingGain)
 }
 func setUserVolume(_ value:Float) {
  let volume=max(0,min(1,value));userVolume=volume
  if original != nil {original=volume;transition(to:volume*recordingGain)} else {displayLink?.invalidate();displayLink=nil;player?.volume=volume}
 }
 func end() {guard let original=original else {return};self.original=nil;transition(to:original)}
 private func transition(to value:Float) {
  displayLink?.invalidate();guard let player=player else {return}
  from=player.volume;target=value;started=CACurrentMediaTime()
  let link=CADisplayLink(target:ticker,selector:#selector(VolumeTicker.tick))
  displayLink=link;link.add(to:.main,forMode:.common)
 }
 fileprivate func advance() {
  guard let player=player else {displayLink?.invalidate();displayLink=nil;return}
  let t=Float(min(1,max(0,(CACurrentMediaTime()-started)/0.48)))
  // Zero slope and acceleration at both ends, updated with the screen cadence.
  let eased=t*t*t*(t*(6*t-15)+10)
  player.volume=from+(target-from)*eased
  if t>=1 {player.volume=target;displayLink?.invalidate();displayLink=nil}
 }
}
@MainActor private final class VolumeTicker:NSObject {
 weak var owner:VoiceVolumeDucker?
 init(owner:VoiceVolumeDucker) {self.owner=owner}
 @objc func tick() {owner?.advance()}
}
