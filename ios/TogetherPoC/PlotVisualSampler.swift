import Foundation
import Combine
import AVFoundation
import Vision
import CoreVideo
import QuartzCore

// Convert the current decoder host clock to item time. A historical time
// (such as playhead minus 250 ms) can be too old for the live output queue.
enum PlotVisualFrameClock {
 static func itemTime(host:CMTime,playhead:Double)->CMTime? {
  guard playhead.isFinite,playhead>=0 else{return nil}
  let hostSeconds=host.seconds
  let seconds=hostSeconds.isFinite && hostSeconds>=0 ? min(playhead,hostSeconds) : playhead
  return CMTime(seconds:seconds,preferredTimescale:600)
 }
}

// Conservative broad visual vocabulary. A Vision classification is only a
// hypothesis about pixels, never a claim about a character or movie plot.
enum PlotSceneTagger {
 static func category(_ identifier:String)->String? {
  let value=identifier.lowercased()
  let groups:[(String,[String])]=[
   ("实验或医疗环境",["laboratory","microscope","hospital","medical","surgical","clinic","test tube"]),
   ("室内环境",["indoor","interior","hallway","corridor","room","office","kitchen","bedroom"]),
   ("户外环境",["outdoor","landscape","forest","desert","mountain","sky","field","street"]),
   ("交通场景",["vehicle","car","truck","bus","road","highway","motorcycle","train"]),
   ("人物",["person","people","human","portrait","face","crowd"]),
   ("建筑",["building","architecture","house","factory","warehouse","industrial"]),
   ("屏幕或设备",["computer","monitor","screen","machine","equipment","electronics"]),
   ("动物",["animal","dog","cat","horse","bird"])
  ]
  return groups.first(where:{group in group.1.contains(where:value.contains)})?.0
 }
 static func candidateLabels(_ observations:[(String,Float)])->[(String,Float)] {
  var found=Set<String>()
  return observations.compactMap {name,score in
   guard score>=0.40,let label=category(name),found.insert(label).inserted else{return nil}
   return (label,score)
  }
 }
}

@MainActor final class PlotVisualSampler:ObservableObject {
 @Published var enabled:Bool {
  didSet {
   guard enabled != oldValue else{return}
   preferences.set(enabled,forKey:"plot-visual-ondevice-enabled")
   onEnabledChanged?(enabled)
   resetAttachment()
  }
 }
 @Published private(set) var status="画面理解试验未开启"
 @Published private(set) var analyzedFrames=0
 private let player:AVPlayer
 private let preferences:UserDefaults
 private weak var attachedItem:AVPlayerItem?
 private var output:AVPlayerItemVideoOutput?
 private var timer:Timer?
 private var generation=0
 private var filmKey=""
 private var foreground=true
 private var lastTick:Double?
 private var lastSample = -Double.infinity
 private var busy=false
 private var missingFrameCount=0
 private var outputRestartCount=0
 private var visual:[PlotEvidence]=[]
 var onNewEvidence:(()->Void)?
 var onEnabledChanged:((Bool)->Void)?
 init(player:AVPlayer,preferences:UserDefaults = .standard) {
  self.player=player
  self.preferences=preferences
  enabled=preferences.bool(forKey:"plot-visual-ondevice-enabled")
  if enabled {status="准备识别已播放画面（仅本机）"}
 }
 // Reloaded player items retain previously viewed clues for the *same* film.
 func beginFilm(_ key:String) {
  guard !key.isEmpty else{return}
  if filmKey != key {
   generation+=1;filmKey=key;visual=[];analyzedFrames=0
   missingFrameCount=0;outputRestartCount=0
   lastTick=nil;lastSample = -.infinity
  }
 }
 func evidence(cutoff:Double)->[PlotEvidence] {
  guard enabled,cutoff.isFinite,cutoff>=0 else{return []}
  return visual.filter{$0.end<=cutoff}
 }
 func attach(to item:AVPlayerItem) {
  if attachedItem !== item {detach();attachedItem=item;lastTick=nil;lastSample = -.infinity;missingFrameCount=0;outputRestartCount=0}
  resetAttachment()
 }
 func setForeground(_ value:Bool) {
  foreground=value
  if !value {timer?.invalidate();timer=nil;lastTick=nil;generation+=1;busy=false}
  else {resetAttachment()}
 }
 func clear() {
  detach();filmKey="";visual=[];analyzedFrames=0;missingFrameCount=0;outputRestartCount=0
  status=enabled ? "等待播放画面" : "画面理解试验未开启"
 }
 private func detach() {
  generation+=1
  timer?.invalidate();timer=nil
  if let output,let attachedItem {attachedItem.remove(output)}
  output=nil;attachedItem=nil;busy=false;lastTick=nil
 }
 private func resetAttachment() {
  timer?.invalidate();timer=nil
  if let output,let item=attachedItem {item.remove(output)}
  output=nil;generation+=1;busy=false;lastTick=nil
  guard enabled,foreground,let item=attachedItem else {
   status=enabled ? "等待影片开始播放" : "画面理解试验未开启"
   return
  }
  // Keep item decoding independent of the subtitle output, and fail closed
  // for protected/incompatible streams instead of affecting playback.
  let attributes:[String:Int]=[kCVPixelBufferPixelFormatTypeKey as String:Int(kCVPixelFormatType_32BGRA)]
  let next=AVPlayerItemVideoOutput(pixelBufferAttributes:attributes)
  item.add(next)
  output=next
  status="正在等待安全的已播放画面样本"
  let timer=Timer(timeInterval:3,repeats:true){[weak self] _ in
   Task {@MainActor in self?.tick()}
  }
  self.timer=timer;RunLoop.main.add(timer,forMode:.common)
 }
 private func tick() {
  guard enabled,foreground,!busy,let output,let item=attachedItem,
        player.currentItem === item,item.status == .readyToPlay,player.rate>0 else {
   lastTick=nil;return
  }
  let position=player.currentTime().seconds
  guard position.isFinite,position>=3 else{return}
  defer {lastTick=position}
  // Reject a seek, jump or a paused/stale frame. The viewer must have played
  // forward over two ticks before a frame becomes eligible for analysis.
  guard let previous=lastTick,position-previous>=0.2,position-previous<=6 else{return}
  guard position-lastSample>=18 else{return}
  // Apple recommends querying the decoder's current host-aligned item time.
  // The output only holds recent decoded frames, so a 250 ms old request
  // can report nil even while a movie is playing normally.
  guard let time=PlotVisualFrameClock.itemTime(host:output.itemTime(forHostTime:CACurrentMediaTime()),playhead:position) else{return}
  guard output.hasNewPixelBuffer(forItemTime:time),
        let pixel=output.copyPixelBuffer(forItemTime:time,itemTimeForDisplay:nil) else {
   missingFrameCount+=1
   if missingFrameCount>=4 && outputRestartCount==0 {
    outputRestartCount=1
    status="尚未收到画面帧，正在重新接入播放器画面输出"
    resetAttachment()
   } else if missingFrameCount<8 {
    status="等待已解码画面帧（已尝试\(missingFrameCount)次），电影继续播放"
   } else {
    status="画面输出持续不可用；可能是片源或解码兼容问题，字幕推理仍可使用"
   }
   return
  }
  missingFrameCount=0
  lastSample=position;busy=true
  let identity=filmKey
  let token=generation
  Task.detached(priority:.utility) {[weak self] in
   let labels:[(String,Float)]
   do {
    let request=VNClassifyImageRequest()
    let handler=VNImageRequestHandler(cvPixelBuffer:pixel,options:[:])
    try handler.perform([request])
    let observations=(request.results ?? []).prefix(16).map{($0.identifier,$0.confidence)}
    labels=PlotSceneTagger.candidateLabels(observations)
   } catch {
    await MainActor.run {
     guard let self,self.generation==token else{return}
     self.busy=false;self.status="当前画面无法识别；已跳过，不影响播放"
    }
    return
   }
   await MainActor.run {
    guard let self,self.enabled,self.generation==token,self.filmKey==identity,
     self.attachedItem === self.player.currentItem else{return}
    self.busy=false
    self.analyzedFrames+=1
    guard let top=labels.first,top.1>=0.40 else {
     self.status="已安全分析\(self.analyzedFrames)帧；该画面暂无线索"
     return
    }
    // A low-confidence classifier label may help a real AI ask a question;
    // it cannot identify Alice, infer a murder or see future movie content.
    let cutoff=max(0,position-0.25)
    var value=PlotEvidence.cue(start:max(0,cutoff-0.2),end:cutoff,
     text:"本地视觉模型推测：画面可能包含\(top.0)。仅为画面分类，不能证明情节。",
     source:"ondevice-vision")
    value.confidence=Double(top.1)
    self.visual.append(value)
    self.visual=Array(self.visual.suffix(60))
    self.status="已分析\(self.analyzedFrames)帧 · 可能是\(top.0)（仅本地）"
    self.onNewEvidence?()
   }
  }
 }
}
