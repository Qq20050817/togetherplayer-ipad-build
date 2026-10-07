import Foundation
import Combine
import AVFoundation

struct SavedMedia: Codable, Identifiable {
 let id: UUID
 var title: String
 let url: String
 var favorite: Bool
 var lastPlayed: Date?
}
@MainActor final class MediaLibrary: ObservableObject {
 @Published private(set) var items: [SavedMedia]=[]
 init() {if let data=UserDefaults.standard.data(forKey:"publicMediaLibrary"),let saved=try? JSONDecoder().decode([SavedMedia].self,from:data) {items=saved.filter {MediaSourceCatalog.canShare($0.url)}}}
 func add(title: String,url: String) -> Bool {
  guard MediaSourceCatalog.canShare(url),let resolved=MediaSourceCatalog.resolve(url) else {return false}
  if !items.contains(where:{$0.url==resolved.absoluteString}) {items.append(SavedMedia(id:UUID(),title:title.isEmpty ? "未命名影片" : String(title.prefix(160)),url:resolved.absoluteString,favorite:false,lastPlayed:nil));save()}
  return true
 }
 func played(_ url: String,title: String) {guard add(title:title,url:url),let index=items.firstIndex(where:{$0.url==url}) else {return};items[index].lastPlayed=Date();save()}
 func toggleFavorite(_ item: SavedMedia) {guard let i=items.firstIndex(where:{$0.id==item.id}) else {return};items[i].favorite.toggle();save()}
 func remove(_ item: SavedMedia) {items.removeAll {$0.id==item.id};save()}
 private func save() {if let data=try? JSONEncoder().encode(items) {UserDefaults.standard.set(data,forKey:"publicMediaLibrary")}}
}
@MainActor final class PlaybackMonitor: ObservableObject {
 @Published private(set) var position=0.0
 @Published private(set) var duration=0.0
 @Published private(set) var playing=false
 @Published private(set) var buffering=false
 private let player: AVPlayer
 private var timer: Timer?
 init(player: AVPlayer) {
  self.player=player
  timer=Timer.scheduledTimer(withTimeInterval:0.5,repeats:true) {[weak self] _ in Task {@MainActor in self?.update()}}
 }
 deinit {timer?.invalidate()}
 private func update() {
  let time=player.currentTime().seconds;let nextPosition=time.isFinite ? max(0,time) : 0;if position != nextPosition {position=nextPosition}
  let length=player.currentItem?.duration.seconds ?? 0;let nextDuration=length.isFinite ? max(0,length) : 0;if duration != nextDuration {duration=nextDuration}
  let nextPlaying=player.timeControlStatus == .playing;let nextBuffering=player.timeControlStatus == .waitingToPlayAtSpecifiedRate;if playing != nextPlaying {playing=nextPlaying};if buffering != nextBuffering {buffering=nextBuffering}
 }
 static func time(_ seconds: Double) -> String {
  guard seconds.isFinite,seconds>=0 else {return "00:00"}
  let value=Int(min(seconds,864000))
  return value>=3600 ? String(format:"%d:%02d:%02d",value/3600,(value/60)%60,value%60) : String(format:"%02d:%02d",value/60,value%60)
 }
}
