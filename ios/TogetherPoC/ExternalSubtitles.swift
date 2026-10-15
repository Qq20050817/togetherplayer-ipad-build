import Foundation
import Combine
import AVFoundation
import CoreMedia
import CoreFoundation

@MainActor final class ExternalSubtitles: ObservableObject {
 private(set) var importedFileURL:URL?
 @Published private(set) var name=""
 @Published private(set) var text=""
 @Published private(set) var status=""
 @Published var enabled=false {didSet {refresh()}}
 // Controls an additional AI-only OCR index. Never selects a subtitle track.
 @Published var convertPGSForAI:Bool {didSet {
  preferences.set(convertPGSForAI,forKey:"plot-pgs-ai-srt-enabled")
  onAIOnlyPGSChanged?()
 }}
 // The raw bitmap decoder is an unverified 4K/HDR experiment. Default OFF
 // after a field-reported room PLAY crash; the AI OCR index remains independent.
 @Published var originalPGSBitmapEnabled:Bool {didSet {
  preferences.set(originalPGSBitmapEnabled,forKey:"plot-original-pgs-experimental-enabled")
  onOriginalPGSBitmapChanged?()
 }}
 @Published var delay=0.0 {didSet {refresh()}}
 @Published var fontSize:Double {didSet {preferences.set(SubtitleAppearance.font(fontSize),forKey:"subtitle-font-size")}}
 @Published var bottomFraction:Double {didSet {preferences.set(SubtitleAppearance.position(bottomFraction),forKey:"subtitle-bottom-fraction")}}
 @Published var fontFamily:SubtitleFontFamily {didSet {preferences.set(fontFamily.rawValue,forKey:"subtitle-font-family")}}
 @Published var fontWeight:SubtitleFontWeight {didSet {preferences.set(fontWeight.rawValue,forKey:"subtitle-font-weight")}}
 @Published var letterSpacing:Double {didSet {preferences.set(SubtitleAppearance.letterSpacing(letterSpacing),forKey:"subtitle-letter-spacing")}}
 @Published var lineSpacing:Double {didSet {preferences.set(SubtitleAppearance.lineSpacing(lineSpacing),forKey:"subtitle-line-spacing")}}
 private let preferences:UserDefaults
 private var nativeTimeline=NativeSubtitleTimeline()
 // Original decoded bitmap PGS events, never OCR or AI SRT.
 private var originalPGSTimeline=PGSBitmapTimeline()
 private var originalPGSTrack:Int?
 private var originalPGSEventTime = -Double.infinity
 @Published private(set) var originalPGSFrame:PGSBitmapFrame?
 private var legibleOutput:AVPlayerItemLegibleOutput?
 private var legibleDelegate:SubtitleLegibleDelegate?
 private weak var attachedItem:AVPlayerItem?
 private var nativeEnabled=true
 private var document: SubtitleDocument?
 private var plannedQuestions:[PlotQuestionCheckpoint]=[]
 private var nativeIndexedDocument:SubtitleDocument?
 private var nativeIndexedQuestions:[PlotQuestionCheckpoint]=[]
 private(set) var nativeIndexedTrack:Int?
 // Bitmap OCR projection is for AI only. It never becomes the displayed caption.
 private var nativeIndexStreaming=false
 private(set) var nativeIndexAIOnly=false
 private(set) var nativeAISRT:String?
 @Published private(set) var nativeIndexStatus=""
 private let player: AVPlayer
 private var observer: Any?
 private var generation=0
 private var plotLastTime:Double?
 private var plotLastWasPlaying=false
 private var plotJumpObserver:NSObjectProtocol?
 var plotDidSeek:(()->Void)?
 private(set) var plotCaptionSequence=0
 var plotCaptionBoundaryChanged:(()->Void)?
 var plotCaptionChanged:((String)->Void)?
 var plotFullSubtitleIndexed:((SubtitleDocument,String,[PlotQuestionCheckpoint])->Void)?
 var plotFullFilmReset:(()->Void)?
 var onAIOnlyPGSChanged:(()->Void)?
 var onOriginalPGSBitmapChanged:(()->Void)?
 private var plotWatched:[ClosedRange<Double>]=[]
 private var plotFilmKey=""
 private var lastNativeSelectionAuditAt=0.0
 private var lastNativeCallbackAt=Date().timeIntervalSince1970
 private var lastNativeRecoveryAt=0.0
 private var nativeOutputRecoveryCount=0
 // Called on the player's existing clock: no extra polling timer or decoder.
 var nativeSelectionHealthCheck:(()->Void)?
 func isCurrentPlotFilm(_ key:String)->Bool {!key.isEmpty && plotFilmKey==key}
 // Reconnecting can replace AVPlayerItem without changing the film.
 // Keep watched intervals for that film; never transfer them to another film.
 func beginPlotFilm(_ key:String) {
  guard !key.isEmpty,plotFilmKey != key else {return}
  if !plotFilmKey.isEmpty {plotFullFilmReset?();clear()}
  plotFilmKey=key;plotLastTime=nil;plotLastWasPlaying=false
  clearOriginalPGS()
  nativeOutputRecoveryCount=0;lastNativeRecoveryAt=0
 }
 var available: Bool {document != nil}
 var plannedQuestionCount:Int {enabled ? plannedQuestions.count : nativeIndexedQuestions.count}
 var nativeIndexedCueCount:Int {nativeIndexedDocument?.cues.count ?? 0}
 func installNativeIndex(_ document:SubtitleDocument,track:Int,forAIOnly:Bool=false) {
  guard track>=0,!document.cues.isEmpty else{return}
  nativeIndexedDocument=document
  nativeIndexedQuestions=PlotQuestionPlanner.indexed(document.cues)
  nativeIndexedTrack=track
  nativeIndexAIOnly=forAIOnly
  nativeAISRT=forAIOnly ? SubtitleSRTEncoder.encode(document) : nil
  nativeIndexStatus=forAIOnly ? "PGS OCR 已生成仅供 AI 使用的 SRT（\(document.cues.count)条），播放字幕轨道未切换" :
   "内置字幕已索引\(document.cues.count)条 · 预选\(nativeIndexedQuestions.count)处剧情"
  plotFullSubtitleIndexed?(document,"embedded-subtitle",nativeIndexedQuestions)
  refresh()
 }
 func nativeIndexStreamingStarted() {
  nativeIndexStreaming=true
  updateStreamingIndexStatus()
 }
 private func updateStreamingIndexStatus() {
  guard nativeIndexStreaming else{return}
  let count=nativeTimeline.events.filter{!$0.text.isEmpty}.count
  let value="按播放进度采集内置字幕（已收到\(count)条）；剧情分析不等待完整索引"
  if nativeIndexStatus != value {nativeIndexStatus=value}
 }
 func nativeIndexStarted() {if nativeIndexedDocument == nil {nativeIndexStatus="正在读取内置字幕的 AI 文字索引…"}}
 func nativeIndexDisabledForAI() {nativeIndexStatus="已关闭 PGS 转文字供 AI 使用；观看字幕未改变"}
 func clearAIOnlyOCRIndex() {
  guard nativeIndexAIOnly else{return}
  plotFullFilmReset?()
  clearNativeIndex()
  refresh()
 }
 func nativeIndexUnavailable() {
  if nativeIndexedDocument == nil {nativeIndexStatus="此内置字幕轨道暂不支持全片索引，继续使用实时字幕"}
 }
 private func clearNativeIndex() {
  nativeIndexedDocument=nil;nativeIndexedQuestions=[];nativeIndexedTrack=nil
  nativeIndexStreaming=false;nativeIndexAIOnly=false;nativeAISRT=nil;nativeIndexStatus=""
 }
 func plannedQuestionCheckpoint(at position:Double,duration:Double)->Double? {
  // A complete imported subtitle can be indexed without sending the future
  // transcript to Apple AI or ChatGPT. Native cues are streamed and use
  // duration landmarks, verified against already watched evidence at runtime.
  let stops=enabled && !plannedQuestions.isEmpty ? plannedQuestions :
   (!enabled && nativeEnabled && !nativeIndexedQuestions.isEmpty ? nativeIndexedQuestions :
    PlotQuestionPlanner.durationCheckpoints(duration))
  return PlotQuestionPlanner.active(stops,at:position)
 }
 // Only subtitles strictly at/before the current player time may enter a
 // generative question prompt; never pass the whole movie's subtitle file.
 func observedPlotExcerpt() -> String {
  let cutoff=min(player.currentTime().seconds,player.currentTime().seconds-delay)
  guard cutoff.isFinite && cutoff>=0 else {return ""}
  let past:[String]
  if enabled {past=document?.cues.filter{$0.start<=cutoff && $0.end<=cutoff}.suffix(22).map{$0.text} ?? []}
  else if nativeEnabled {
   if let nativeIndexedDocument {
    past=Array(nativeIndexedDocument.cues.filter {cue in
     cue.end<=cutoff && cue.start<=cutoff &&
      plotWatched.contains{$0.lowerBound<=cue.start+0.2 && $0.upperBound>=cue.end}
    }.suffix(22).map(\.text))
   } else {past=nativeTimeline.completedText(before:cutoff)}
  } else {past=[]}
  return past.joined(separator:"\n")
 }
 func observedPlotEvidence()->[PlotEvidence] {
  let cutoff=min(player.currentTime().seconds,player.currentTime().seconds-delay)
  guard cutoff.isFinite,cutoff>=0 else {return []}
  func watched(_ start:Double,_ end:Double)->Bool {plotWatched.contains{$0.lowerBound<=start+0.2 && $0.upperBound>=end}}
  if enabled,let document {
   return document.cues.prefix(while:{$0.start<=cutoff}).filter{$0.end<=cutoff && watched($0.start,$0.end)}.map{PlotEvidence.cue(start:$0.start,end:$0.end,text:$0.text,source:"external-subtitle")}
  }
  guard nativeEnabled else{return []}
  // A remuxed subtitle track can be indexed before playback. Only cues
  // really watched on this device are eligible as AI evidence.
  if let nativeIndexedDocument {
   return nativeIndexedDocument.cues.prefix(while:{$0.start<=cutoff})
    .filter{$0.end<=cutoff && watched($0.start,$0.end)}
    .map{PlotEvidence.cue(start:$0.start,end:$0.end,text:$0.text,source:"embedded-subtitle")}
  }
  return nativeTimeline.completedIntervals(before:cutoff)
   .filter{watched($0.start,$0.end)}
   .map{PlotEvidence.cue(start:$0.start,end:$0.end,text:$0.text,source:"embedded-subtitle")}
 }

 init(player: AVPlayer,preferences:UserDefaults = .standard) {
  self.player=player;self.preferences=preferences
  convertPGSForAI=preferences.object(forKey:"plot-pgs-ai-srt-enabled") as? Bool ?? true
  originalPGSBitmapEnabled=preferences.object(forKey:"plot-original-pgs-experimental-enabled") as? Bool ?? false
  fontSize=SubtitleAppearance.font(preferences.object(forKey:"subtitle-font-size") as? Double ?? 24)
  bottomFraction=SubtitleAppearance.position(preferences.object(forKey:"subtitle-bottom-fraction") as? Double ?? 0.07)
  fontFamily=SubtitleFontFamily(rawValue:preferences.string(forKey:"subtitle-font-family") ?? "") ?? .system
  fontWeight=SubtitleFontWeight(rawValue:preferences.string(forKey:"subtitle-font-weight") ?? "") ?? .regular
  letterSpacing=SubtitleAppearance.letterSpacing(preferences.double(forKey:"subtitle-letter-spacing"))
  lineSpacing=SubtitleAppearance.lineSpacing(preferences.double(forKey:"subtitle-line-spacing"))
  let pulse=MainActorPulse()
  observer=player.addPeriodicTimeObserver(forInterval:CMTime(seconds:0.15,preferredTimescale:600),queue:.main) {[weak self] _ in
   pulse.request {[weak self] in self?.refresh()}
  }
  plotJumpObserver=NotificationCenter.default.addObserver(forName:.AVPlayerItemTimeJumped,object:nil,queue:.main){[weak self] note in
   Task{@MainActor in
    guard let self,let item=note.object as? AVPlayerItem,item === self.player.currentItem else {return}
    self.plotLastTime=nil;self.plotLastWasPlaying=false;self.plotDidSeek?()
   }
  }
 }
 deinit {if let observer=observer {player.removeTimeObserver(observer)};if let plotJumpObserver {NotificationCenter.default.removeObserver(plotJumpObserver)}}
 func clear() {importedFileURL=nil;generation+=1;clearNativeIndex();document=nil;plannedQuestions=[];name="";text="";status="";nativeTimeline.clear();plotWatched=[];plotFilmKey="";plotLastTime=nil;plotLastWasPlaying=false;nativeOutputRecoveryCount=0;lastNativeRecoveryAt=0;clearOriginalPGS();enabled=false;delay=0}
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
  let output=AVPlayerItemLegibleOutput()
  // The delegate queues future events; they are never drawn before their
  // shifted timestamp. 120 seconds matches the adjustment panel's bounds.
  output.advanceIntervalForDelegateInvocation=120
  output.suppressesPlayerRendering=true
  let delegate=SubtitleLegibleDelegate(owner:self)
  legibleOutput=output;legibleDelegate=delegate
  output.setDelegate(delegate,queue:.main);item.add(output);refresh()
 }
 func nativeSelectionChanged(enabled:Bool=true) {plotFullFilmReset?();nativeEnabled=enabled;nativeTimeline.clear();clearNativeIndex();clearOriginalPGS();refresh()}

 /// Decoder injection seam: ONLY original PGS bitmap events may enter here.
 /// Track changes and new films clear it; OCR stays in nativeAISRT.
 func installOriginalPGS(_ events:[PGSBitmapEvent],track:Int) {
  guard originalPGSBitmapEnabled,track>=0 else{return}
  originalPGSTrack=track
  originalPGSTimeline.replace(with:events)
  originalPGSEventTime = -.infinity
  updateOriginalPGS(at:player.currentTime().seconds)
 }
 func clearOriginalPGS() {
  originalPGSTrack=nil;originalPGSTimeline.clear()
  originalPGSEventTime = -.infinity;originalPGSFrame=nil
 }
 private func updateOriginalPGS(at time:Double) {
  guard originalPGSBitmapEnabled,nativeEnabled,!enabled,originalPGSTrack != nil,
        time.isFinite,time>=0 else {
   if originalPGSFrame != nil {originalPGSFrame=nil;noteCaptionBoundary()}
   originalPGSEventTime = -.infinity;return
  }
  let events=originalPGSTimeline.events
  var low=0,high=events.count
  while low<high {
   let middle=low+(high-low)/2
   if events[middle].time<=time {low=middle+1} else {high=middle}
  }
  let eventTime=low>0 ? events[low-1].time : -.infinity
  guard eventTime != originalPGSEventTime else{return}
  originalPGSEventTime=eventTime
  originalPGSFrame=low>0 ? events[low-1].frame : nil
  noteCaptionBoundary()
 }
 private func noteCaptionBoundary() {
  plotCaptionSequence+=1
  plotCaptionBoundaryChanged?()
 }
 fileprivate func receiveNative(_ output:AVPlayerItemLegibleOutput,text:String,time:Double,end:Double?=nil) {
  guard output === legibleOutput else {return}
  lastNativeCallbackAt=Date().timeIntervalSince1970
  nativeTimeline.receive(text:text,time:time,end:end);updateStreamingIndexStatus();refresh()
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
   plotFullFilmReset?()
   document=result;importedFileURL=url
   plannedQuestions=PlotQuestionPlanner.indexed(result.cues)
   name=url.lastPathComponent;delay=0;enabled=true
   status=(ext=="ass" || ext=="ssa") ? "已加载\(result.cues.count)条字幕；ASS/SSA按文本显示" : "已加载\(result.cues.count)条字幕"
   plotFullSubtitleIndexed?(result,"external-subtitle",plannedQuestions)
   refresh();return true
  } catch {
   guard current==generation else {return false}
   status=(error as? SubtitleParseError) == .size ? "字幕不能超过5MB" : "字幕读取失败，请检查文件格式和文字编码"
   return false
  }
 }
 private func refresh() {
  let actual=player.currentTime().seconds
  if actual.isFinite,actual>=0 {
   if player.rate>0,plotLastWasPlaying,let last=plotLastTime,actual>last,actual-last<=2.5 {
    PlotWatchedIntervals.record(&plotWatched,from:last,to:actual)
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
   if now-lastNativeCallbackAt>=90,now-lastNativeRecoveryAt>=90,
    nativeOutputRecoveryCount<2 {
    lastNativeRecoveryAt=now;nativeOutputRecoveryCount+=1
    attachNativeOutput(to:item)
   }
  }
  updateOriginalPGS(at:player.currentTime().seconds)
  let time=player.currentTime().seconds-delay
  let live=nativeEnabled ? nativeTimeline.text(at:time) : ""
  let next=enabled ? document?.text(at:time) ?? "" :
   (nativeEnabled ? (nativeIndexAIOnly ? live : (nativeIndexedDocument?.text(at:time) ?? live)) : "")
  // When a genuine PGS composition is visible, never draw OCR/WebVTT on top.
  // Missing original frame falls back to the selected native track rather than
  // dropping captions during partial extraction or at a later movie position.
  let visibleText=originalPGSFrame != nil ? "" : next
  if visibleText != text {text=visibleText;noteCaptionBoundary();plotCaptionChanged?(visibleText)}
 }
}

// UIKit delivers this delegate on the main queue. Bridge explicitly to the
// main actor and discard callbacks from obsolete output instances.
final class SubtitleLegibleDelegate:NSObject,AVPlayerItemLegibleOutputPushDelegate {
 private weak var owner:ExternalSubtitles?
 init(owner:ExternalSubtitles) {self.owner=owner}
 func legibleOutput(_ output:AVPlayerItemLegibleOutput,didOutputAttributedStrings strings:[NSAttributedString],nativeSampleBuffers:[Any],forItemTime itemTime:CMTime) {
  let text=strings.map(\.string).joined(separator:"\n")
  // When AVFoundation supplies real legible-sample durations, a caption can
  // end accurately even if the track omits an explicit empty callback. Never
  // invent a fixed duration or infer that speech ended merely from a timeout.
  let end=Self.nativeDuration(nativeSampleBuffers).map{itemTime.seconds+$0}
  MainActor.assumeIsolated {owner?.receiveNative(output,text:text,time:itemTime.seconds,end:end)}
 }
 static func nativeDuration(_ buffers:[Any])->Double? {
  buffers.compactMap {value -> Double? in
   let reference=value as CFTypeRef
   guard CFGetTypeID(reference)==CMSampleBufferGetTypeID() else{return nil}
   let sample=reference as! CMSampleBuffer
   let duration=CMSampleBufferGetOutputDuration(sample).seconds
   return duration.isFinite && duration>0 ? duration : nil
  }.max()
 }
 func outputSequenceWasFlushed(_ output:AVPlayerItemOutput) {
  guard let output=output as? AVPlayerItemLegibleOutput else {return}
  MainActor.assumeIsolated {owner?.flushNative(output)}
 }
}
