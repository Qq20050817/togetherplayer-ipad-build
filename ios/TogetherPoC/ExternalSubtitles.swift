import Foundation
import Combine
import AVFoundation

@MainActor final class ExternalSubtitles: ObservableObject {
 @Published private(set) var name=""
 @Published private(set) var text=""
 @Published private(set) var status=""
 @Published private(set) var fullFilmAnalysisStatus=""
 @Published private(set) var nativeCaptureStatus=""
 @Published var enabled=false {didSet {refresh()}}
 @Published var delay=0.0 {didSet {refresh()}}
 @Published var fontSize:Double {didSet {preferences.set(SubtitleAppearance.font(fontSize),forKey:"subtitle-font-size")}}
 @Published var bottomFraction:Double {didSet {preferences.set(SubtitleAppearance.position(bottomFraction),forKey:"subtitle-bottom-fraction")}}
 @Published var fontFamily:SubtitleFontFamily {didSet {preferences.set(fontFamily.rawValue,forKey:"subtitle-font-family")}}
 @Published var fontWeight:SubtitleFontWeight {didSet {preferences.set(fontWeight.rawValue,forKey:"subtitle-font-weight")}}
 @Published var letterSpacing:Double {didSet {preferences.set(SubtitleAppearance.letterSpacing(letterSpacing),forKey:"subtitle-letter-spacing")}}
 @Published var lineSpacing:Double {didSet {preferences.set(SubtitleAppearance.lineSpacing(lineSpacing),forKey:"subtitle-line-spacing")}}
 private let preferences:UserDefaults
 private var nativeTimeline=NativeSubtitleTimeline()
 private var legibleOutput:AVPlayerItemLegibleOutput?
 private var legibleDelegate:SubtitleLegibleDelegate?
 private weak var attachedItem:AVPlayerItem?
 private var nativeEnabled=true
 private var document: SubtitleDocument?
 private var plannedQuestions:[PlotQuestionCheckpoint]=[]
 private var fullFilmBeats:[PlotClue]=[]
 private var fullFilmBeatStarts:[String:Double]=[:]
 private var fullFilmTask:Task<Void,Never>?
 private let player: AVPlayer
 private var observer: Any?
 private var generation=0
 private var plotLastTime:Double?
 private var plotLastWasPlaying=false
 private var plotJumpObserver:NSObjectProtocol?
 var plotDidSeek:(()->Void)?
 var plotCaptionChanged:((String)->Void)?
 private var plotWatched:[ClosedRange<Double>]=[]
 private var plotFilmKey=""
 private var lastNativeSelectionAuditAt=0.0
 private var lastNativeCallbackAt=Date().timeIntervalSince1970
 private var lastNativeRecoveryAt=0.0
 private var nativeOutputRecoveryCount=0
 private var nativeCueCount=0
 private var nativeFirstCueAt:Double?
 // Called on the player's existing clock: no extra polling timer or decoder.
 var nativeSelectionHealthCheck:(()->Void)?
 func isCurrentPlotFilm(_ key:String)->Bool {!key.isEmpty && plotFilmKey==key}
 // Reconnecting can replace AVPlayerItem without changing the film.
 // Keep watched intervals for that film; never transfer them to another film.
 func beginPlotFilm(_ key:String) {
  guard !key.isEmpty,plotFilmKey != key else {return}
  if !plotFilmKey.isEmpty {clear()}
  plotFilmKey=key;plotLastTime=nil;plotLastWasPlaying=false
  nativeOutputRecoveryCount=0;lastNativeRecoveryAt=0
  nativeCueCount=0;nativeFirstCueAt=nil;nativeCaptureStatus=""
 }
 var available: Bool {document != nil}
 var plannedQuestionCount:Int {enabled ? plannedQuestions.count : 0}
 var fullFilmBeatCount:Int {enabled ? fullFilmBeats.count : 0}
 // A locally indexed future scene remains sealed until the whole window
 // has really been watched, including after seek, reconnect and rewind.
 func watchedStoryBeats(at cutoff:Double,observed:[PlotEvidence])->[PlotClue] {
  guard enabled,cutoff.isFinite else{return []}
  let ids=Set(observed.map(\.id))
  func fraction(_ beat:PlotClue)->Double {
   let end=beat.end
   let windowStart=fullFilmBeatStarts[beat.id] ?? max(0,end-720)
   guard end>windowStart else{return 0}
   var covered=0.0,cursor=windowStart
   for range in plotWatched where range.upperBound>windowStart && range.lowerBound<end {
    let lower=max(windowStart,range.lowerBound),upper=min(end,range.upperBound)
    if upper>max(cursor,lower) {covered += upper-max(cursor,lower)}
    cursor=max(cursor,upper)
   }
   return covered/(end-windowStart)
  }
  return Array(fullFilmBeats.filter{
   PlotFullFilmIndex.visible($0,at:cutoff,evidenceIDs:ids,watchedFraction:fraction($0))
  }.suffix(8))
 }
 func plannedQuestionCheckpoint(at position:Double,duration:Double)->Double? {
  // A complete imported subtitle can be indexed without sending the future
  // transcript to Apple AI or ChatGPT. Native cues are streamed and use
  // duration landmarks, verified against already watched evidence at runtime.
  let stops=enabled && !plannedQuestions.isEmpty
   ? plannedQuestions : PlotQuestionPlanner.durationCheckpoints(duration)
  return PlotQuestionPlanner.active(stops,at:position)
 }
 // Only subtitles strictly at/before the current player time may enter a
 // generative question prompt; never pass the whole movie's subtitle file.
 func observedPlotExcerpt() -> String {
  let cutoff=min(player.currentTime().seconds,player.currentTime().seconds-delay)
  guard cutoff.isFinite && cutoff>=0 else {return ""}
  let past:[String]
  if enabled {past=document?.cues.filter{$0.start<=cutoff && $0.end<=cutoff}.suffix(22).map{$0.text} ?? []}
  else {past=nativeEnabled ? nativeTimeline.completedText(before:cutoff) : []}
  return past.joined(separator:"\n")
 }
 func observedPlotEvidence()->[PlotEvidence] {
  let cutoff=min(player.currentTime().seconds,player.currentTime().seconds-delay)
  guard cutoff.isFinite,cutoff>=0 else {return []}
  func watched(_ start:Double,_ end:Double)->Bool {plotWatched.contains{$0.lowerBound<=start+0.2 && $0.upperBound>=end}}
  if enabled,let document {
   return document.cues.prefix(while:{$0.start<=cutoff}).filter{$0.end<=cutoff && watched($0.start,$0.end)}.map{PlotEvidence.cue(start:$0.start,end:$0.end,text:$0.text,source:"external-subtitle")}
  }
  guard nativeEnabled,nativeTimeline.events.count>1 else {return []}
  return zip(nativeTimeline.events,nativeTimeline.events.dropFirst()).filter{!$0.0.text.isEmpty && $0.1.time<=cutoff && watched($0.0.time,$0.1.time)}.map{PlotEvidence.cue(start:$0.0.time,end:$0.1.time,text:$0.0.text,source:"embedded-subtitle")}
 }

 init(player: AVPlayer,preferences:UserDefaults = .standard) {
  self.player=player;self.preferences=preferences
  fontSize=SubtitleAppearance.font(preferences.object(forKey:"subtitle-font-size") as? Double ?? 24)
  bottomFraction=SubtitleAppearance.position(preferences.object(forKey:"subtitle-bottom-fraction") as? Double ?? 0.07)
  fontFamily=SubtitleFontFamily(rawValue:preferences.string(forKey:"subtitle-font-family") ?? "") ?? .system
  fontWeight=SubtitleFontWeight(rawValue:preferences.string(forKey:"subtitle-font-weight") ?? "") ?? .regular
  letterSpacing=SubtitleAppearance.letterSpacing(preferences.double(forKey:"subtitle-letter-spacing"))
  lineSpacing=SubtitleAppearance.lineSpacing(preferences.double(forKey:"subtitle-line-spacing"))
  observer=player.addPeriodicTimeObserver(forInterval:CMTime(seconds:0.15,preferredTimescale:600),queue:.main) {[weak self] _ in
   Task {@MainActor in self?.refresh()}
  }
  plotJumpObserver=NotificationCenter.default.addObserver(forName:.AVPlayerItemTimeJumped,object:nil,queue:.main){[weak self] note in
   Task{@MainActor in
    guard let self,let item=note.object as? AVPlayerItem,item === self.player.currentItem else {return}
    self.plotLastTime=nil;self.plotLastWasPlaying=false;self.plotDidSeek?()
   }
  }
 }
 deinit {if let observer=observer {player.removeTimeObserver(observer)};if let plotJumpObserver {NotificationCenter.default.removeObserver(plotJumpObserver)}}
 func clear() {generation+=1;fullFilmTask?.cancel();fullFilmTask=nil;fullFilmBeats=[];fullFilmBeatStarts=[:];fullFilmAnalysisStatus="";document=nil;plannedQuestions=[];name="";text="";status="";nativeTimeline.clear();plotWatched=[];plotFilmKey="";plotLastTime=nil;plotLastWasPlaying=false;nativeOutputRecoveryCount=0;lastNativeRecoveryAt=0;nativeCueCount=0;nativeFirstCueAt=nil;nativeCaptureStatus="";enabled=false;delay=0}
 func resetAdjustments() {delay=0;fontSize=24;bottomFraction=0.07;fontFamily = .system;fontWeight = .regular;letterSpacing=0;lineSpacing=0}
 func attachNativeOutput(to item:AVPlayerItem) {
  if attachedItem !== item {plotLastTime=nil;plotLastWasPlaying=false}
  if let old=legibleOutput,let attachedItem=attachedItem {attachedItem.remove(old)}
  // When a reconnect installs another AVPlayerItem for the SAME film,
  // the new legible output may not replay already delivered cues immediately.
  // beginPlotFilm()/explicit track selection already clear old-film/track data.
  // Preserve the timeline across same-film item replacements.
  if plotFilmKey.isEmpty {nativeTimeline.clear()}
  nativeEnabled=true;attachedItem=item
  lastNativeCallbackAt=Date().timeIntervalSince1970
  if nativeCueCount==0 {nativeCaptureStatus="等待内置字幕文字回调，图形字幕可能需要其他识别方式"}
  let output=AVPlayerItemLegibleOutput()
  // The delegate queues future events; they are never drawn before their
  // shifted timestamp. 120 seconds matches the adjustment panel's bounds.
  output.advanceIntervalForDelegateInvocation=120
  output.suppressesPlayerRendering=true
  let delegate=SubtitleLegibleDelegate(owner:self)
  legibleOutput=output;legibleDelegate=delegate
  output.setDelegate(delegate,queue:.main);item.add(output);refresh()
 }
 func nativeSelectionChanged(enabled:Bool=true) {
  nativeEnabled=enabled;nativeTimeline.clear();nativeCueCount=0;nativeFirstCueAt=nil
  nativeOutputRecoveryCount=0;nativeCaptureStatus=enabled ? "等待所选内置字幕文字" : ""
  refresh()
 }
 fileprivate func receiveNative(_ output:AVPlayerItemLegibleOutput,text:String,time:Double) {
  guard output === legibleOutput else {return}
  lastNativeCallbackAt=Date().timeIntervalSince1970
  if !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {
   nativeCueCount+=1
   if nativeFirstCueAt==nil {nativeFirstCueAt=time}
   if nativeCueCount==1 || nativeCueCount%20==0 {
    nativeCaptureStatus="已读取内置字幕文字 \(nativeCueCount) 条，可用于已观看剧情分析"
   }
  }
  nativeTimeline.receive(text:text,time:time);refresh()
 }
 fileprivate func flushNative(_ output:AVPlayerItemLegibleOutput) {
  guard output === legibleOutput else {return}
  // Seeking can flush output while paused without supplying replacement cues.
  // Cached events use the same item clock; selection/item changes clear them separately.
  refresh()
 }
 func beginSelection() {status="请选择字幕文件"}
 func cancelImport() {status="已取消选择字幕"}
 func importFile(_ url: URL) async -> Bool {
  generation+=1;let current=generation;status="正在读取字幕…"
  let ext=url.pathExtension.lowercased()
  guard ["srt","vtt","ass","ssa"].contains(ext) else {status="请选择SRT、VTT、ASS或SSA字幕";return false}
  do {
   let result=try await Task.detached(priority:.userInitiated) {
    let scoped=url.startAccessingSecurityScopedResource();defer {if scoped {url.stopAccessingSecurityScopedResource()}}
    let file=try FileHandle(forReadingFrom:url);defer {try? file.close()}
    let data=try file.read(upToCount:SubtitleParser.maxBytes+1) ?? Data()
    return try SubtitleParser.parse(data,extension:ext)
   }.value
   guard current==generation else {return false}
   document=result
   plannedQuestions=PlotQuestionPlanner.indexed(result.cues)
   fullFilmTask?.cancel();fullFilmBeats=[];fullFilmBeatStarts=[:]
   let windows=PlotFullFilmIndex.windows(result.cues)
   fullFilmAnalysisStatus=windows.isEmpty ? "字幕量不足，继续边看边分析" : "全片字幕已建立时间索引，正在设备端逐段理解"
   name=url.lastPathComponent;delay=0;enabled=true
   if !windows.isEmpty {startFullFilmAnalysis(windows,generation:current)}
   status=(ext=="ass" || ext=="ssa") ? "已加载\(result.cues.count)条字幕；ASS/SSA按文本显示" : "已加载\(result.cues.count)条字幕"
   refresh();return true
  } catch {
   guard current==generation else {return false}
   status=(error as? SubtitleParseError) == .size ? "字幕不能超过5MB" : "字幕读取失败，请检查文件格式和文字编码"
   return false
  }
 }
 private func startFullFilmAnalysis(_ windows:[PlotFilmWindow],generation current:Int) {
  fullFilmTask=Task(priority:.utility) {[weak self] in
   guard let self else{return}
   guard PlotLocalAI.available else {
    self.fullFilmAnalysisStatus="全片字幕时间索引已完成，设备端 AI 暂不可用；播放中仍会按真实字幕出题"
    return
   }
   for (index,window) in windows.enumerated() {
    guard !Task.isCancelled,self.generation==current else{return}
    if let beat=await PlotFullFilmAnalyzer.interpret(window) {
     guard !Task.isCancelled,self.generation==current else{return}
     self.fullFilmBeats.append(beat)
     self.fullFilmBeatStarts[beat.id]=window.start
    }
    self.fullFilmAnalysisStatus="全片本地剧情理解：\(index+1)/\(windows.count) 段；已确认线索 \(self.fullFilmBeats.count) 段"
    await Task.yield()
   }
   self.fullFilmAnalysisStatus="全片本地剧情索引完成：\(self.fullFilmBeats.count) 段；未来剧情仅在播到后解锁"
  }
 }
 private func refresh() {
  let actual=player.currentTime().seconds
  if actual.isFinite,actual>=0 {
   if player.rate>0,plotLastWasPlaying,let last=plotLastTime,actual>last,actual-last<=2.5 {
    if let range=plotWatched.last,last-range.upperBound<=0.2 {plotWatched[plotWatched.count-1]=range.lowerBound...actual}
    else {plotWatched.append(last...actual);plotWatched=Array(plotWatched.suffix(500))}
   }
   plotLastTime=actual
   plotLastWasPlaying=player.rate>0
  }
  // AVFoundation can silently reset the selected legible option when HLS
  // variants or decoder state change. Verify the requested native track
  // without clearing on-screen cues or touching external subtitle documents.
  let now=Date().timeIntervalSince1970
  if !enabled,nativeEnabled,player.rate>0,let item=attachedItem,
   player.currentItem === item,item.status == .readyToPlay,
   now-lastNativeSelectionAuditAt>=4 {
   lastNativeSelectionAuditAt=now
   nativeSelectionHealthCheck?()
   // If even empty/end cue callbacks stop arriving for a long period, the
   // legible output can be detached by a stream switch. Reattach at most twice
   // per film while retaining already observed cues; normal gaps do not clear
   // the selected track or interrupt playback.
   if now-lastNativeCallbackAt>=32,now-lastNativeRecoveryAt>=32,
    nativeOutputRecoveryCount<2 {
    lastNativeRecoveryAt=now;nativeOutputRecoveryCount+=1
    nativeCaptureStatus="内置字幕输出中断，正在重新接入（\(nativeOutputRecoveryCount)/2）"
    attachNativeOutput(to:item)
   } else if now-lastNativeCallbackAt>=70 && nativeOutputRecoveryCount>=2 {
    if legibleOutput?.suppressesPlayerRendering == true {
     legibleOutput?.suppressesPlayerRendering=false
     nativeCaptureStatus="内置文字回调不可用，已尝试系统字幕回退；AI 暂无法读取此轨道"
    }
   }
  }
  let time=player.currentTime().seconds-delay
  let next=enabled ? document?.text(at:time) ?? "" : (nativeEnabled ? nativeTimeline.text(at:time) : "")
  if next != text {text=next;plotCaptionChanged?(next)}
 }
}

// UIKit delivers this delegate on the main queue. Bridge explicitly to the
// main actor and discard callbacks from obsolete output instances.
final class SubtitleLegibleDelegate:NSObject,AVPlayerItemLegibleOutputPushDelegate {
 private weak var owner:ExternalSubtitles?
 init(owner:ExternalSubtitles) {self.owner=owner}
 func legibleOutput(_ output:AVPlayerItemLegibleOutput,didOutputAttributedStrings strings:[NSAttributedString],nativeSampleBuffers:[Any],forItemTime itemTime:CMTime) {
  let text=strings.map(\.string).joined(separator:"\n")
  MainActor.assumeIsolated {owner?.receiveNative(output,text:text,time:itemTime.seconds)}
 }
 func outputSequenceWasFlushed(_ output:AVPlayerItemOutput) {
  guard let output=output as? AVPlayerItemLegibleOutput else {return}
  MainActor.assumeIsolated {owner?.flushNative(output)}
 }
}
