import Foundation
import Combine
import AVFoundation

@MainActor final class ExternalSubtitles: ObservableObject {
 @Published private(set) var name=""
 @Published private(set) var text=""
 @Published private(set) var status=""
 @Published var enabled=false {didSet {refresh()}}
 @Published var delay=0.0 {didSet {refresh()}}
 private var document: SubtitleDocument?
 private let player: AVPlayer
 private var observer: Any?
 private var generation=0
 var available: Bool {document != nil}
 init(player: AVPlayer) {
  self.player=player
  observer=player.addPeriodicTimeObserver(forInterval:CMTime(seconds:0.15,preferredTimescale:600),queue:.main) {[weak self] _ in
   Task {@MainActor in self?.refresh()}
  }
 }
 deinit {if let observer=observer {player.removeTimeObserver(observer)}}
 func clear() {generation+=1;document=nil;name="";text="";status="";enabled=false;delay=0}
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
  let next=enabled ? document?.text(at:player.currentTime().seconds-delay) ?? "" : ""
  if next != text {text=next}
 }
}
