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
 var available: Bool {document != nil}
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
 }
 deinit {if let observer=observer {player.removeTimeObserver(observer)}}
 func clear() {generation+=1;document=nil;name="";text="";status="";nativeTimeline.clear();enabled=false;delay=0}
 func resetAdjustments() {delay=0;fontSize=24;bottomFraction=0.07;fontFamily = .system;fontWeight = .regular;letterSpacing=0;lineSpacing=0}
 func attachNativeOutput(to item:AVPlayerItem) {
  if let old=legibleOutput,let attachedItem=attachedItem {attachedItem.remove(old)}
  nativeTimeline.clear();nativeEnabled=true;attachedItem=item
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
  guard output === legibleOutput else {return};nativeTimeline.clear();refresh()
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
  let time=player.currentTime().seconds-delay
  let next=enabled ? document?.text(at:time) ?? "" : (nativeEnabled ? nativeTimeline.text(at:time) : "")
  if next != text {text=next}
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
