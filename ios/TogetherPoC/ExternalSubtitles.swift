import Foundation
import Combine
import AVFoundation

@MainActor final class ExternalSubtitles: ObservableObject {
 @Published private(set) var name=""
 @Published private(set) var text=""
 @Published private(set) var status=""
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
 // Called on the player's existing clock: no extra polling timer or decoder.
 var nativeSelectionHealthCheck:(()->Void)?
 func isCurrentPlotFilm(_ key:String)->Bool {!key.isEmpty && plotFilmKey==key}
 // Reconnecting can replace AVPlayerItem without changing the film.
 // Keep watched intervals for that film; never transfer them to another film.
 func beginPlotFilm(_ key:String) {
  guard !key.isEmpty,plotFilmKey != key else {return}
  if !plotFilmKey.isEmpty {clear()}
  plotFilmKey=key;plotLastTime=nil;plotLastWasPlaying=false
 }
 var available: Bool {document != nil}
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
 func clear() {generation+=1;document=nil;name="";text="";status="";nativeTimeline.clear();plotWatched=[];plotFilmKey="";plotLastTime=nil;plotLastWasPlaying=false;enabled=false;delay=0}
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
  let output=AVPlayerItemLegibleOutput()
  // The delegate queues future events; they are never drawn before their
  // shifted timestamp. 120 seconds matches the adjustment panel's bounds.
  output.advanceIntervalForDelegateInvocation=120
  output.suppressesPlayerRendering=true
  let delegate=SubtitleLegibleDelegate(owner:self)
  legibleOutput=output;legibleDelegate=delegate
  output.setDelegate(delegate,queue:.main);item.add(output);refresh()
 }
 func nativeSelectionChanged(enabled:Bool=true) {nativeEnabled=enabled;nativeTimeline.clear();refresh()}
 fileprivate func receiveNative(_ output:AVPlayerItemLegibleOutput,text:String,time:Double) {
  guard output === legibleOutput else {return}
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
   document=result;name=url.lastPathComponent;delay=0;enabled=true
   status=(ext=="ass" || ext=="ssa") ? "已加载\(result.cues.count)条字幕；ASS/SSA按文本显示" : "已加载\(result.cues.count)条字幕"
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
