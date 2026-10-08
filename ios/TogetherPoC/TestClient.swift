import Foundation
import Combine
import AVFoundation
import CoreMedia

@MainActor final class TestClient: ObservableObject {
 @Published var server=UserDefaults.standard.string(forKey: "server") ?? "https://together.xiaokai123.de5.net"
 @Published var mediaURL="https://media.w3.org/2010/05/bunny/movie.mp4"
 @Published var roomID=""
 @Published var seekSeconds="20"
 @Published var movieTitle=""
 @Published var nickname=UserDefaults.standard.string(forKey:"nickname") ?? "我"
 @Published var offsetSeconds=UserDefaults.standard.string(forKey:"timelineOffset") ?? "0"
 @Published var localMediaURL=""
 @Published var localFileName=""
 let chatDraft=ChatDraftState()
 @Published var members: [RoomMember]=[]
 @Published var waitForPeer=true
 @Published var roomTitle="一起看电影"
 @Published var roomNotice=""
 @Published var isRoomHost=false
 @Published var isConnected=false
 let chat=ChatEngine()
 let library=MediaLibrary()
 @Published var videoBadges: [String]=[]
 var requestedPlaying: Bool {localVideoTest ? adapter.player.timeControlStatus != .paused : engine.room?.state == "playing"}
 var playbackTitle: String {usingLocalFile ? localFileName : usingBaiduSource ? baiduFileName : roomTitle}
 func isMyMessage(_ message: ChatMessage) -> Bool {message.userId == credentials?["userId"] as? String}
 var usingBaiduSource: Bool {baiduPlaybackURL != nil && activeLocalSource==baiduPlaybackURL?.absoluteString && localSourceRoomURL==engine.room?.mediaUrl && localSourceRoomID==engine.room?.roomId}
 var usingLocalFile: Bool {localFileURL != nil && localSourceRoomURL==engine.room?.mediaUrl && localSourceRoomID==engine.room?.roomId}
 var sourceNotice: String {
  if usingDifferentQuality {return variantNotice}
  if BaiduMediaReference(value:engine.room?.mediaUrl ?? "") != nil {
   if usingLocalFile && hasBaiduMatch {return "本地同一文件已匹配；影片直接从这台 iPad 读取，等待双方准备好后由房主播放。"}
   return hasBaiduMatch ? "百度同一文件已匹配；等待双方准备好后由房主播放。" : "等待选片：可选择本地同一文件，或授权百度网盘并选择好友转存的同一文件。"
  }
  if usingLocalFile {return "仅本机文件：影片直接从这台 iPad 读取，不会上传到服务器或发给好友。双方需确认同一剪辑版本。"}
  guard !activeLocalSource.isEmpty,localSourceRoomURL==engine.room?.mediaUrl,localSourceRoomID==engine.room?.roomId else {return ""}
  return "仅本机\(usingBaiduSource ? "百度" : "独立")片源：不会自动为好友换片。房间影片：\(roomTitle)。双方需确认同一影片版本。"
 }
 var sourceResetLabel: String {usingLocalFile ? "清除本地影片" : BaiduMediaReference(value:engine.room?.mediaUrl ?? "") != nil ? "清除本机百度片源" : "恢复房间片源"}
 var baiduRoomTitle: String {BaiduMediaReference(value:engine.room?.mediaUrl ?? "") != nil ? roomTitle : ""}
 private var baiduSourceID=""
 private var baiduSourceRoom=""
 private var baiduPlaybackURL: URL?
 private var baiduFileName=""
 private var localFileURL: URL?
 private var localFileSecurityScoped=false
 private var localSelectionGeneration=0
 private var localSelectionRoom=""
 private var localSelectionMedia=""
 private var localSelectionPublishes=true
 private var pendingLocalFile: URL?
 @Published var localQualityCandidate: LocalQualityCandidate?
 private var variantRoomID=""
 private var variantMediaURL=""
 private var variantReferenceDuration=0.0
 var usingDifferentQuality: Bool {hasBaiduMatch && variantRoomID==engine.room?.roomId && variantMediaURL==engine.room?.mediaUrl}
 var variantDurationCheck: MovieVariantPolicy.DurationCheck {
  guard usingDifferentQuality else {return .compatible}
  return MovieVariantPolicy.duration(localMs:adapter.duration,offsetMs:engine.timelineOffset,roomMs:variantReferenceDuration)
 }
 var variantNotice: String {
  guard usingDifferentQuality else {return ""}
  switch variantDurationCheck {
  case .waiting:return "已确认另一画质；等待读取双方时长，暂不进入同步。"
  case .compatible:return "已确认同一影片的另一画质，时长核对通过；若片头不同，可在房间设置校准时间偏移。"
  case .different:return "另一画质与房间时长相差超过5秒，已暂停同步。请确认相同剪辑，或校准片头时间偏移。"
  }
 }
 private let mkvRemux=MKVRemux()
 private var remuxAudioLabelsByDisplayName: [String:[String]] = [:]
 private var remuxAudioTrackSummary: [String] = []
 private var trackSelectionGeneration=0
 private let compatibilityPreparation: ((URL,[String:String]) async throws -> URL)?
 private var currentOriginalURL: URL?
 private var activeLocalSource=""
 private var localSourceRoomURL=""
 private var localSourceRoomID=""
 private var foreground=true
 private var lastTyping=0.0
 private var prerolling=false
 private var prerollGeneration=0
 private var prerollPrepared=false
 private var recoveryStartedAt: Double?
 private var lastPrerollAt = -Double.infinity
 private var queuedOperations: [[String:Any]]=[]
 private var inFlight: [String:Any]?
 private var inFlightSequence: Int64=0
 private var operationRetry=0
 private var inFlightStartedAt: Double?
 private var pendingRoomMedia: PendingRoomMedia?
 let mediaFeedback=ClientFeedback()
 @Published private(set) var isSettingRoomMedia=false
 private var outbox: [String:[String:Any]]=[:]
 private var outboxRoom=""
 let feedback=ClientFeedback()
 var status: String {get {feedback.status} set {if feedback.status != newValue {feedback.status=newValue}}}
 var requestStatus: String {get {feedback.requestStatus} set {if feedback.requestStatus != newValue {feedback.requestStatus=newValue}}}
 @Published var audioLabels: [String]=[]
 @Published var selectedAudioIndex = -1
 @Published var subtitleLabels: [String]=[]
 @Published var selectedSubtitleIndex = -1
 private var subtitleGroup: AVMediaSelectionGroup?
 @Published var mediaInfo=""
 @Published var streamInfo="等待读取播放轨道"
 @Published var atmosReferenceOverride=false
 private var inspectingFormats=false
 private var lastLoggedSpeed: Float=0
 private var lastLoggedResync=0
 private let appleReferenceURL="https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/main.m3u8"
 private let atmosServer=AtmosReferenceServer()
 private var mediaLoadGeneration=0
 private var audioGroup: AVMediaSelectionGroup?
 @Published var pending: [String:Any]?
 let adapter=AVPlayerAdapter()
 lazy var playback=PlaybackMonitor(player:adapter.player)
 lazy var externalSubtitles=ExternalSubtitles(player:adapter.player)
 let clock=ClockSync()
 lazy var engine=SyncEngine(adapter,clock)
 private var registering=false
 private var credentialServer=UserDefaults.standard.string(forKey:"server") ?? "https://together.xiaokai123.de5.net"
 private var credentials: [String:Any]?
 private var socket: URLSessionWebSocketTask?
 private var connectionStartedAt=0.0
 private var lastMessageAt=0.0
 let voice=VoiceDanmakuController()
 private var voiceDucker:VoiceVolumeDucker?
 private var disconnectCount=0
 private var lastDisconnectReason=""
 private var ignoredFrames=0
 private let messageSender: (([String:Any])->Void)?
 private var generation=0;private var attempt=0;private var sequence: Int64=0
 private var connected=false {didSet {if isConnected != connected {isConnected=connected}}};private var loadedURL="";private var ticks=0
 private var timer: Timer?
 private var isHost=false
 private var localVideoTest=false
 private var observers: [NSObjectProtocol]=[]
 private var playerObservation: NSKeyValueObservation?
 private var itemObservation: NSKeyValueObservation?
 init(compatibilityPreparation: ((URL,[String:String]) async throws -> URL)? = nil,automaticallyConnect: Bool=true,messageSender: (([String:Any])->Void)? = nil) {
  self.compatibilityPreparation=compatibilityPreparation
  self.messageSender=messageSender
  voiceDucker=VoiceVolumeDucker(player:adapter.player)
  voice.sendText={ [weak self] text in self?.sendVoiceDanmaku(text) ?? false }
  voice.roomKey={ [weak self] in self?.engine.room?.roomId ?? "" }
  voice.duck={ [weak self] lowered in if lowered {self?.voiceDucker?.begin()} else {self?.voiceDucker?.end()} }
  do {try AVAudioSession.sharedInstance().setCategory(.playback,mode:.moviePlayback);try AVAudioSession.sharedInstance().setSupportsMultichannelContent(true);try AVAudioSession.sharedInstance().setActive(true)} catch {requestStatus="音频会话设置失败"}
  for name in [Notification.Name.AVPlayerItemPlaybackStalled,Notification.Name.AVPlayerItemNewAccessLogEntry,Notification.Name.AVPlayerItemNewErrorLogEntry] {
   observers.append(NotificationCenter.default.addObserver(forName:name,object:nil,queue:.main) { [weak self] note in
    Task { @MainActor in
     guard let self=self,let item=note.object as? AVPlayerItem,item === self.adapter.player.currentItem else {return}
     self.diagnostic(name.rawValue)
    }
   })
  }
  playerObservation=adapter.player.observe(\.timeControlStatus,options:[.new]) { [weak self] _,_ in
   Task { @MainActor in self?.diagnostic("timeControlStatusChanged") }
  }
  if let data=UserDefaults.standard.data(forKey: "credentials"),let c=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any] {credentials=c;roomID=c["roomId"] as? String ?? ""}
  #if DEBUG
  if ProcessInfo.processInfo.environment["TOGETHER_ROOM_MEDIA_TEST"]=="1" {credentials=["roomId":"media-ui-test","userId":"media-ui-host","token":String(repeating:"a",count:64)];roomID="media-ui-test"}
  #endif
  timer=Timer.scheduledTimer(withTimeInterval: 0.1,repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
  if automaticallyConnect,credentials != nil {connect()}
 }
 deinit {for observer in observers {NotificationCenter.default.removeObserver(observer)}}
 private func diagnostic(_ event: String) {
  var data: [String:Any]=["diagnostic":true,"event":event,"clientVersion":"0.5.0","version":engine.room?.version ?? 0,"positionMs":adapter.position,"playbackRate":adapter.player.rate,"timeControlStatus":adapter.player.timeControlStatus.rawValue,"localVideoTest":localVideoTest,"localTimeMs":clock.localNow(),"serverTimeMs":clock.ready ? clock.serverNow() as Any : NSNull()]
  data["disconnectCount"]=disconnectCount;data["lastDisconnectReason"]=lastDisconnectReason;data["ignoredFrames"]=ignoredFrames
  if let log=adapter.player.currentItem?.accessLog()?.events.last {
   data["droppedVideoFrames"]=log.numberOfDroppedVideoFrames;data["stalls"]=log.numberOfStalls;data["observedBitrate"]=log.observedBitrate
   if let raw=log.uri,let u=URL(string:raw),u.host=="devstreaming-cdn.apple.com" {data["appleAccessLogPath"]=u.path}
  }
  if let log=adapter.player.currentItem?.errorLog()?.events.last {data["errorStatusCode"]=log.errorStatusCode}
  data["itemStatus"]=adapter.player.currentItem?.status.rawValue ?? -1
  data["durationMs"]=adapter.duration
  data["resyncCount"]=engine.resyncCount
  data["multichannelDeclared"]=AVAudioSession.sharedInstance().supportsMultichannelContent
  data["spatialAudioRouteEnabled"]=AVAudioSession.sharedInstance().currentRoute.outputs.map {$0.isSpatialAudioEnabled}
  data["streamInfo"]=streamInfo;data["atmosReferenceOverride"]=atmosReferenceOverride
  data["availableHDRModes"]=AVPlayer.availableHDRModes.rawValue
  data["audioSelection"]=selectedAudioIndex>=0 && selectedAudioIndex<audioLabels.count ? audioLabels[selectedAudioIndex] : "automatic"
  data["audioOutputTypes"]=AVAudioSession.sharedInstance().currentRoute.outputs.map {$0.portType.rawValue}
  send(["type":"TELEMETRY","data":data])
  if localVideoTest {status="本机播放诊断：\(event)"}
 }
 func useHighQualityTestSource() {
  mediaURL="https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/main.m3u8"
  requestStatus="已选择苹果测试源；点创建建立新房间，或仅测试本机播放。"
 }
 func toggleAtmosReference() {
  let source=localVideoTest ? mediaURL : engine.room?.mediaUrl ?? mediaURL
  guard source==appleReferenceURL,let url=URL(string:source) else {requestStatus="Atmos对照仅用于苹果测试片；请先选择测试源并创建房间。";return}
  atmosReferenceOverride.toggle();loadMedia(playbackSource(for:url))
  requestStatus=atmosReferenceOverride ? "iPad已切换到只含EC-3/JOC的对照清单；Android片源保持原样。输出仍需确认。" : "iPad恢复官方自适应清单。"
 }
 private func inspectFormats() {
  guard !inspectingFormats,let item=adapter.player.currentItem,item.status == .readyToPlay else {return}
  inspectingFormats=true
  Task {
   defer {inspectingFormats=false}
   var audio: [String]=[];var video: [String]=[];var badges: [String]=[]
   for itemTrack in item.tracks where itemTrack.isEnabled {
    guard let track=itemTrack.assetTrack,let formats=try? await track.load(.formatDescriptions) else {continue}
    let type=track.mediaType
    for format in formats {
     let codec=fourCC(CMFormatDescriptionGetMediaSubType(format))
     if type == .audio {
      let channels=CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee.mChannelsPerFrame
      audio.append(codec+(channels.map {" / \($0)声道"} ?? ""))
     } else if type == .video {
      video.append(codec)
      let size=CMVideoFormatDescriptionGetDimensions(format)
      if size.width>0 {badges.append(size.width>=3840 ? "4K" : "\(size.width)×\(size.height)")}
      badges.append(codec=="dvh1" || codec=="dvhe" ? "杜比视界轨道" : codec.uppercased())
     }
    }
   }
   guard adapter.player.currentItem === item else {return}
   let nextBadges=NSOrderedSet(array:badges).array as? [String] ?? badges;if videoBadges != nextBadges {videoBadges=nextBadges}
   let audioReport=remuxAudioTrackSummary.isEmpty ? (audio.isEmpty ? "未提供" : audio.joined(separator:", ")) : remuxAudioTrackSummary.joined(separator:"；")
   let nextStreamInfo="播放轨道报告：音频 \(audioReport)；视频 \(video.isEmpty ? "未提供" : video.joined(separator:", "))\n兼容音轨转换会明确标出；编码与声道不能单独证明Atmos输出。"
   if streamInfo != nextStreamInfo {streamInfo=nextStreamInfo;diagnostic("playbackFormats")}
  }
 }
 private func fourCC(_ value: UInt32) -> String {
  String(bytes:[UInt8((value>>24)&255),UInt8((value>>16)&255),UInt8((value>>8)&255),UInt8(value&255)],encoding:.ascii) ?? "unknown"
 }
 private func loadMedia(_ url: URL,forceRemux: Bool=false) {
  if let previous=currentOriginalURL,previous != url {externalSubtitles.clear()}
  currentOriginalURL=url
  mediaLoadGeneration += 1;let g=mediaLoadGeneration
  let useAtmos=atmosReferenceOverride && url.absoluteString==appleReferenceURL
  let needsRemux=forceRemux || MKVRemux.needed(url:url,fileName:url==baiduPlaybackURL ? baiduFileName : nil)
  adapter.pause();adapter.player.replaceCurrentItem(with:nil)
  mkvRemux.stop();remuxAudioLabelsByDisplayName=[:];remuxAudioTrackSummary=[]
  Task {
   guard g==mediaLoadGeneration else {return}
   do {
    let playbackURL: URL
    if useAtmos {playbackURL=try await atmosServer.prepareURL()}
    else if needsRemux {
     requestStatus="正在本机准备兼容播放；视频不经过Muse。"
     let headers=url==baiduPlaybackURL ? ["User-Agent":"pan.baidu.com"] : [:]
     if let prepare=compatibilityPreparation {playbackURL=try await prepare(url,headers)}
     else {
      playbackURL=try await mkvRemux.prepare(url,headers:headers)
      guard g==mediaLoadGeneration else {return}
      remuxAudioLabelsByDisplayName=mkvRemux.audioLabelsByDisplayName
      remuxAudioTrackSummary=mkvRemux.audioTrackSummary
     }
    } else {playbackURL=url}
    guard g==mediaLoadGeneration else {return}
    if needsRemux {requestStatus="兼容片源已准备，正在读取播放信息。"}
    installMedia(playbackURL,originalURL:url,allowRemuxRetry:!useAtmos && !needsRemux)
    if localVideoTest {adapter.player.play()}
   } catch {
    guard g==mediaLoadGeneration else {return}
    requestStatus=useAtmos ? "Atmos本机清单加载失败，可点恢复官方自适应音轨。" : ((error as? MKVRemux.Failure)?.errorDescription ?? MKVRemux.safeFailure(error).errorDescription ?? "本机片源准备失败")
   }
  }
 }
 private func installMedia(_ playbackURL: URL,originalURL: URL,allowRemuxRetry: Bool) {
  prerollGeneration += 1;prerollPrepared=false;prerolling=false;recoveryStartedAt=nil;adapter.player.cancelPendingPrerolls()
  let item: AVPlayerItem
  if playbackURL==baiduPlaybackURL {
   item=AVPlayerItem(asset:AVURLAsset(url:playbackURL,options:[AVURLAssetHTTPUserAgentKey:"pan.baidu.com"]))
  } else {item=AVPlayerItem(url:playbackURL)}
 item.preferredForwardBufferDuration=30;audioGroup=nil;audioLabels=[];selectedAudioIndex = -1
  subtitleGroup=nil;subtitleLabels=[];selectedSubtitleIndex = -1
  if externalSubtitles.enabled {selectedSubtitleIndex = -2}
  videoBadges=[]
  if MediaSourceCatalog.canShare(originalURL.absoluteString),originalURL != baiduPlaybackURL {library.played(originalURL.absoluteString,title:movieTitle)}
  streamInfo="等待读取播放轨道";adapter.pause();externalSubtitles.attachNativeOutput(to:item);adapter.player.replaceCurrentItem(with:item);updateMediaInfo()
  if allowRemuxRetry {
   let g=mediaLoadGeneration
   Task {
    try? await Task.sleep(nanoseconds:20_000_000_000)
    guard g==mediaLoadGeneration,adapter.player.currentItem === item,item.status == .unknown else {return}
    requestStatus="原生加载超时，尝试本机兼容封装。"
    loadMedia(originalURL,forceRemux:true)
   }
  }
  itemObservation=item.observe(\.status,options:[.new]) { [weak self] observed,_ in
   Task { @MainActor in
    guard let self=self,self.adapter.player.currentItem === observed else {return}
    if observed.status == .failed {
     self.diagnostic("itemFailed")
     if allowRemuxRetry {
      self.requestStatus="原生加载失败（\((observed.error as NSError?)?.code ?? 0)），尝试本机兼容封装。"
      self.loadMedia(originalURL,forceRemux:true)
     } else {self.requestStatus="兼容播放仍失败（\((observed.error as NSError?)?.code ?? 0)）；可能为取流或编码限制。"}
    }
    else if observed.status == .readyToPlay {
     if self.requestStatus=="兼容片源已准备，正在读取播放信息。" {self.requestStatus=""}
     self.loadTrackSelections(observed);self.inspectFormats()
    }
   }
  }
  loadTrackSelections(item)
 }
 // HLS groups can appear only after the item becomes ready. Each group is
 // independent so unavailable audio metadata never prevents subtitle discovery.
 private func loadTrackSelections(_ item: AVPlayerItem) {
  trackSelectionGeneration += 1;let generation=trackSelectionGeneration
  Task {
   let group=try? await item.asset.loadMediaSelectionGroup(for:.audible)
   var tracks:[AudioTrackDetail]=[]
   if let assetTracks=try? await item.asset.load(.tracks) {
    for track in assetTracks where track.mediaType == .audio {
     let formats=(try? await track.load(.formatDescriptions)) ?? []
     let extended=try? await track.load(.extendedLanguageTag)
     let code=try? await track.load(.languageCode)
     let language=extended ?? code
     let codecs=formats.map {fourCC(CMFormatDescriptionGetMediaSubType($0))}
     let channels=formats.first.flatMap {CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee.mChannelsPerFrame}
     tracks.append(AudioTrackDetail(language:language,codecs:codecs,channels:channels))
    }
   }
   guard generation==trackSelectionGeneration,adapter.player.currentItem === item else {return}
   audioGroup=group
   var remuxLabels=remuxAudioLabelsByDisplayName
   audioLabels=group?.options.enumerated().map {index,option in
    if var choices=remuxLabels[option.displayName],let first=choices.first {
     choices.removeFirst();remuxLabels[option.displayName]=choices;return first
    }
    return AudioTrackDetail.label(name:option.displayName,index:index,language:option.extendedLanguageTag ?? option.locale?.identifier,subtypes:option.mediaSubTypes.map {fourCC($0.uint32Value)},tracks:tracks,optionCount:group?.options.count ?? 0)
   } ?? []
   if let group=group,let current=item.currentMediaSelection.selectedMediaOption(in:group) {selectedAudioIndex=group.options.firstIndex(where:{$0 === current}) ?? -1}
   updateMediaInfo();diagnostic("audioOptionsLoaded")
  }
  Task {
   let group=try? await item.asset.loadMediaSelectionGroup(for:.legible)
   guard generation==trackSelectionGeneration,adapter.player.currentItem === item else {return}
   subtitleGroup=group
   subtitleLabels=group?.options.map {$0.displayName} ?? []
   if (externalSubtitles.enabled || selectedSubtitleIndex == -2),let group=group {item.select(nil,in:group)}
   else if let group=group,let current=item.currentMediaSelection.selectedMediaOption(in:group) {selectedSubtitleIndex=group.options.firstIndex(where:{$0 === current}) ?? -1}
   diagnostic("subtitleOptionsLoaded")
  }
 }
 func importSubtitle(_ url: URL) {
  Task {if await externalSubtitles.importFile(url) {enableExternalSubtitle()}}
 }
 func enableExternalSubtitle() {
  guard externalSubtitles.available else {return}
  if let item=adapter.player.currentItem,let group=subtitleGroup {item.select(nil,in:group)}
  selectedSubtitleIndex = -2;externalSubtitles.enabled=true
 }
 func chooseSubtitle(_ index: Int) {
  externalSubtitles.nativeSelectionChanged(enabled:index != -2);externalSubtitles.enabled=false;selectedSubtitleIndex=index
  guard let item=adapter.player.currentItem,let group=subtitleGroup else {return}
  if index == -1 {item.selectMediaOptionAutomatically(in:group)}
  else if index == -2 {item.select(nil,in:group)}
  else {guard group.options.indices.contains(index) else {return};item.select(group.options[index],in:group)}
  selectedSubtitleIndex=index
 }
 func chooseAudio(_ index: Int) {
  guard let item=adapter.player.currentItem,let group=audioGroup else {return}
  if index == -1 {item.selectMediaOptionAutomatically(in:group)}
  else {guard group.options.indices.contains(index) else {return};item.select(group.options[index],in:group)}
  selectedAudioIndex=index;diagnostic("audioSelected")
 }
 private func updateMediaInfo() {
  let modes=AVPlayer.availableHDRModes
  var capabilities: [String]=[]
  if modes.contains(.hdr10) {capabilities.append("HDR10")}
  if modes.contains(.dolbyVision) {capabilities.append("杜比视界")}
  let outputs=AVAudioSession.sharedInstance().currentRoute.outputs.map {$0.portType.rawValue}.joined(separator:", ")
  let nextInfo="显示可用能力：\(capabilities.isEmpty ? "未报告 HDR" : capabilities.joined(separator:" / "))\n音频输出：\(outputs)\n能力和音轨编码不代表已输出 HDR 或 Atmos。"
  if mediaInfo != nextInfo {mediaInfo=nextInfo}
 }
 func register(join: Bool) {
  guard !registering else {requestStatus="正在处理房间请求…";return}
  let base=server.trimmingCharacters(in:.whitespacesAndNewlines).trimmingCharacters(in:CharacterSet(charactersIn:"/"))
  let requestedRoom=roomID.trimmingCharacters(in:.whitespacesAndNewlines).lowercased()
  if join,requestedRoom == credentials?["roomId"] as? String,base == credentialServer {connect();return}
  guard let url=URL(string:join ? "\(base)/rooms/\(requestedRoom)/join" : "\(base)/rooms"),["http","https"].contains(url.scheme ?? ""),url.host != nil else {requestStatus="无效服务器 URL";return}
  var request=URLRequest(url:url);request.httpMethod="POST";request.setValue("application/json",forHTTPHeaderField:"Content-Type")
  request.timeoutInterval=15
  request.httpBody=try? JSONSerialization.data(withJSONObject:join ? [:] : ["mediaUrl":MediaSourceCatalog.resolve(mediaURL)?.absoluteString ?? mediaURL,"title":movieTitle])
  guard join || MediaSourceCatalog.canShare(mediaURL) else {requestStatus="房间片源不能包含账户凭据；请使用公开授权链接，或放入仅本机片源。";return}
  registering=true;requestStatus="正在处理房间请求…"
  Task {
   defer {registering=false}
   do {
    let (data,response)=try await URLSession.shared.data(for:request)
    guard let http=response as? HTTPURLResponse else {requestStatus="服务器没有返回有效响应，请稍后重试";return}
    guard http.statusCode == 201 else {
     if http.statusCode == 503 {requestStatus="同步服务器暂时离线，请稍后重试"}
     else {requestStatus="房间请求失败（HTTP \(http.statusCode)），请检查房间编号或服务器地址"}
     return
    }
    guard let next=try JSONSerialization.jsonObject(with:data) as? [String:Any],let nextRoom=next["roomId"] as? String,!nextRoom.isEmpty,
     let user=next["userId"] as? String,!user.isEmpty,let token=next["token"] as? String,!token.isEmpty else {requestStatus="服务器返回了无效房间凭证";return}
    credentials=next;credentialServer=base;roomID=nextRoom
    UserDefaults.standard.set(data,forKey:"credentials");UserDefaults.standard.set(base,forKey:"server");connect()
   } catch {requestStatus="房间请求失败：\(error.localizedDescription)"}
  }
 }
 func connect() {
  localVideoTest=false;queuedOperations=[];inFlight=nil;inFlightStartedAt=nil;operationRetry=0;mediaLoadGeneration += 1;if adapter.player.currentItem==nil {loadedURL=""}
  guard foreground,let token=credentials?["token"] as? String else {return}
  generation += 1;let g=generation;socket?.cancel(with:.goingAway,reason:nil);connected=false;engine.resetSession();pending=nil;requestStatus=""
  guard var components=URLComponents(string:credentialServer) else {status="无效 URL";return}
  components.scheme=components.scheme == "https" ? "wss" : "ws";components.path="/ws";components.query=nil
  guard let url=components.url else {return}
  var request=URLRequest(url:url);request.setValue("Bearer \(token)",forHTTPHeaderField:"Authorization")
  let ws=URLSession.shared.webSocketTask(with:request);socket=ws;ws.resume()
  connectionStartedAt=clock.localNow();lastMessageAt=connectionStartedAt;status="正在连接房间…"
  Task {
   do {
    while g == generation {
     let message=try await ws.receive();let t4=clock.localNow()
     let data: Data
     switch message {case .string(let s):data=Data(s.utf8);case .data(let d):data=d;@unknown default:continue}
     guard g==generation else {return}
     receiveFrame(data,t4:t4)
    }
   } catch {if g==generation {if let http=ws.response as? HTTPURLResponse,http.statusCode==401 {clearRoom();requestStatus="房间已过期，请重新创建或加入"} else {reconnect(g)}}}
  }
 }
 private func reconnect(_ g: Int,reason: String="receive") {
  guard g==generation,foreground,credentials != nil else {return}
  voice.cancel(message:"连接中断，当前录音已取消，未发送")
  // Invalidate both send and receive callbacks before scheduling one retry.
  generation += 1;let next=generation;socket?.cancel(with:.goingAway,reason:nil);socket=nil
  connected=false;engine.resetSession();attempt += 1
  disconnectCount += 1;lastDisconnectReason=reason
  inFlight=nil;inFlightStartedAt=nil;queuedOperations=[]
  status="连接中断，自动重连"
  if pendingRoomMedia != nil {mediaFeedback.requestStatus="连接中断，换片请求已保留；重连后继续确认…"}
  let delay=min(15.0,pow(2.0,Double(min(attempt,5)))*0.5)
  Task {try? await Task.sleep(nanoseconds:UInt64(delay*1e9));if next==generation {connect()} }
 }
 private func send(_ value: [String:Any]) {
  if connected,let messageSender=messageSender {messageSender(value);return}
  guard connected,let data=try? JSONSerialization.data(withJSONObject:value),let text=String(data:data,encoding:.utf8),let ws=socket else {return}
  let g=generation
  Task {do {try await ws.send(.string(text))}catch {reconnect(g,reason:"send")}}
 }
 func receiveFrame(_ data: Data,t4: Double) {
  // Empty control/proxy frames and malformed payloads are not transport failures.
  guard let obj=RoomEnvelope.decode(data) else {ignoredFrames += 1;return}
  receive(obj,t4:t4)
 }
 private func pingBurst() {
  let g=generation
  Task {for _ in 0..<5 {guard g==generation else {return};send(["type":"PING","t1":clock.localNow()]);try? await Task.sleep(nanoseconds:200_000_000)} }
 }
 func receive(_ obj: [String:Any],t4: Double) {
  lastMessageAt=clock.localNow()
  let type=obj["type"] as? String ?? ""
  if type=="PONG",let t1=obj["t1"] as? Double,let t2=obj["t2"] as? Double,let t3=obj["t3"] as? Double {clock.add(t1,t2,t3,t4);return}
  if type=="WELCOME" {connected=true;attempt=0;sequence=(obj["lastSequence"] as? NSNumber)?.int64Value ?? 0;pingBurst()}
  if let raw=obj["room"] as? [String:Any],let data=try? JSONSerialization.data(withJSONObject:raw),let room=try? JSONDecoder().decode(Room.self,from:data) {
   if outboxRoom != room.roomId {outbox=[:];outboxRoom=room.roomId}
   engine.receive(room);isHost=room.hostId == (credentials?["userId"] as? String);if isRoomHost != isHost {isRoomHost=isHost}
   if usingDifferentQuality,variantReferenceDuration<=0,let duration=room.duration,duration>0 {variantReferenceDuration=duration}
   chat.reset(room.roomId);let nextTitle=room.title?.isEmpty == false ? room.title! : "一起看电影";if roomTitle != nextTitle {roomTitle=nextTitle};let nextWait=room.waitForPeer ?? false;if waitForPeer != nextWait {waitForPeer=nextWait}
   let reasons=["buffering":"等待对方缓冲","disconnected":"等待对方重新连接","ended":"播放完毕，点播放可重播","source":"等待双方授权并匹配同一百度影片","server_restart":"同步服务器已恢复，影片保持暂停；点播放继续"]
   let nextNotice=reasons[room.pauseReason ?? ""] ?? "";if roomNotice != nextNotice {roomNotice=nextNotice}
   if let rawMembers=obj["members"],let data=try? JSONSerialization.data(withJSONObject:rawMembers),let roster=try? JSONDecoder().decode([RoomMember].self,from:data) {applyMembers(roster)}
   if BaiduMediaReference(value:room.mediaUrl) != nil {
    // A nil player item is expected during asynchronous remux preparation.
    // Periodic STATE snapshots must not cancel/restart the same media attempt.
    if room.mediaUrl != loadedURL {
     loadedURL=room.mediaUrl;movieTitle=room.title ?? "";atmosReferenceOverride=false
     if hasBaiduMatch,let source=localFileURL ?? baiduPlaybackURL {loadMedia(source)}
     else {stopUnmatchedMedia();requestStatus="房间已切换到文件匹配模式；请选择本地同一文件，或授权百度网盘并选择转存的同一文件。"}
    }
   } else if room.mediaUrl != loadedURL,let url=HTTPSource().resolve(room.mediaUrl) {
    if !baiduSourceID.isEmpty {baiduSourceID="";baiduSourceRoom="";baiduPlaybackURL=nil;baiduFileName="";activeLocalSource="";localMediaURL=""}
    loadedURL=room.mediaUrl;mediaURL=room.mediaUrl;movieTitle=room.title ?? "";if room.mediaUrl != appleReferenceURL {atmosReferenceOverride=false};loadMedia(playbackSource(for:url))
   }
  }
  if type=="CONTROL_REQUEST" {pending=obj["data"] as? [String:Any]}
  if type=="PRESENCE",let raw=obj["members"],let data=try? JSONSerialization.data(withJSONObject:raw),let roster=try? JSONDecoder().decode([RoomMember].self,from:data) {applyMembers(roster)}
  if type=="WELCOME" {
   restorePendingRoomMedia()
   if let list=obj["messages"] as? [[String:Any]] {for message in list {acceptChat(message)}}
   send(["type":"PROFILE_UPDATE","data":["name":nickname,"timelineOffset":Double(offsetSeconds).map {$0*1000} ?? 0]])
   for message in outbox.values {send(message)}
   if let file=pendingLocalFile {pendingLocalFile=nil;useLocalFile(file)}
  }
  if type=="CHAT_MESSAGE",let message=obj["message"] as? [String:Any] {acceptChat(message,live:true)}
  if type=="REACTION",let emoji=obj["emoji"] as? String {chat.reaction(emoji,now:clock.localNow())}
  if type=="CHAT_TYPING",obj["userId"] as? String != credentials?["userId"] as? String {chat.typing(obj["name"] as? String ?? "好友",now:clock.localNow())}
  if type=="ROOM_CLOSE" || type=="ROOM_LEAVE" {clearRoom();return}
  if obj["ackUserId"] as? String == credentials?["userId"] as? String,(obj["ackSequence"] as? NSNumber)?.int64Value == inFlightSequence,inFlight != nil {
   if inFlight?["type"] as? String=="ROOM_MEDIA",let change=pendingRoomMedia,let room=engine.room,change.matches(room) {finishRoomMedia("房间影片已设置；双方正在加载新影片。")}
   inFlight=nil;inFlightStartedAt=nil;operationRetry=0;flushOperations()
  }
  if type=="ERROR" {
   let code=obj["error"] as? String ?? "ERROR"
   if code=="EXPIRED" {clearRoom();requestStatus="房间已过期";return}
   if code=="STALE_VERSION",let operation=inFlight,operationRetry<1 {operationRetry += 1;inFlight=nil;inFlightStartedAt=nil;queuedOperations.insert(operation,at:0);flushOperations()}
   else {inFlight=nil;inFlightStartedAt=nil;queuedOperations=[];requestStatus=errorText(code);if pendingRoomMedia != nil {finishRoomMedia(errorText(code))}}
  }
 }
 func retryCompatibility() {
  guard let url=currentOriginalURL else {requestStatus="请先选择并加载影片";return}
  loadMedia(url,forceRemux:true)
 }
 func checkLocalVideo() {
  generation += 1;socket?.cancel(with:.goingAway,reason:nil);connected=false;clock.reset();localVideoTest=true
  guard let url=HTTPSource().resolve(mediaURL) else {status="无效测试视频 URL";return}
  adapter.setPlaybackSpeed(1);loadedURL=mediaURL;loadMedia(url)
  status="本机视频验证：可测试 PLAY / PAUSE / SEEK；尚未加入同步房间"
 }
 func control(_ type: String,position: Double=0) {
  if localVideoTest {
   switch type {case "PLAY":adapter.play();case "PAUSE":adapter.pause();case "SEEK":adapter.seekTo(position);default:break};return
  }
  guard connected && clock.ready else {requestStatus="尚未连接或正在校准时钟";return}
  var operation: [String:Any]=["type":type,"position":max(0,position)]
  if isHost {guard queuedOperations.count<8 else {requestStatus="请等待前面的操作完成";return};queuedOperations.append(operation);flushOperations()}
  else {sequence += 1;operation["sequence"]=sequence;send(["type":"CONTROL_REQUEST","sequence":sequence,"data":operation]);requestStatus="已向房主发送请求"}

 }
 func approve() {guard let p=pending else {return};control(p["type"] as? String ?? "",position:p["position"] as? Double ?? 0);pending=nil}
 func disconnectForTest() {
  generation += 1;socket?.cancel(with:.goingAway,reason:nil);connected=false;adapter.pause();let g=generation
  Task {try? await Task.sleep(nanoseconds:3_000_000_000);if g==generation {connect()} }
 }
 private func tick() {
  if localVideoTest {ticks += 1;if ticks%50 == 0 {inspectFormats();updateMediaInfo()};return}
  chat.tick(clock.localNow())
  if socket != nil {
   if let reason=RoomConnectionHealth.timeout(now:clock.localNow(),connected:connected,startedAt:connectionStartedAt,lastMessageAt:lastMessageAt,inFlightAt:inFlightStartedAt) {reconnect(generation,reason:reason);return}
  }
  guard connected else {return}
  let error: Double?
  if variantDurationCheck == .compatible {error=engine.tick()} else {adapter.pause();error=nil}
  ticks += 1
  if clock.ready {flushOperations()}
  if adapter.player.rate != lastLoggedSpeed {lastLoggedSpeed=adapter.player.rate;diagnostic("speedChanged")}
  if engine.resyncCount != lastLoggedResync {lastLoggedResync=engine.resyncCount;diagnostic("automaticResync")}
  if ticks%10 == 0 {
   send(["type":"SYNC"])
   let item=adapter.player.currentItem
   let sourceValid=BaiduMediaReference(value:engine.room?.mediaUrl ?? "")==nil || hasBaiduMatch
   let recovering=engine.room?.autoResume == true
   if recovering {if recoveryStartedAt==nil {recoveryStartedAt=clock.localNow()}} else {recoveryStartedAt=nil}
   let fallback=recovering && prerollPrepared && item?.isPlaybackLikelyToKeepUp == true && clock.localNow()-(recoveryStartedAt ?? clock.localNow())>=10000
   let readiness=PlaybackReadinessPolicy.evaluate(prepared:adapter.ready,waiting:adapter.buffering,playing:adapter.player.timeControlStatus == .playing,bufferEmpty:item?.isPlaybackBufferEmpty ?? true,bufferedMs:adapter.bufferedAheadMs,positionMs:adapter.position,durationMs:adapter.duration,recovering:recovering && !usingLocalFile,preparedFallback:fallback)
   let bufferReady=sourceValid && variantDurationCheck == .compatible && readiness.ready
   // A host's alternate encode must not redefine the canonical room duration,
   // otherwise a mismatched cut could pass its own check on the next snapshot.
   let reportedDuration=usingDifferentQuality && isHost ? (variantReferenceDuration>0 ? variantReferenceDuration+engine.timelineOffset : 0) : adapter.duration
   send(["type":"PLAYER_STATUS","data":["sourceId":hasBaiduMatch ? baiduSourceID : "","ready":bufferReady,"buffering":readiness.buffering,"position":max(0,adapter.position-engine.timelineOffset),"duration":reportedDuration]])
   if recovering && !bufferReady && adapter.ready && !prerolling && clock.localNow()-lastPrerollAt>=3000 {
    prerolling=true;lastPrerollAt=clock.localNow();prerollGeneration += 1;let pg=prerollGeneration
    adapter.player.preroll(atRate:1) { [weak self] ready in Task { @MainActor in
     guard let self=self,self.prerollGeneration==pg,self.adapter.player.currentItem === item else {return}
     self.prerolling=false;self.prerollPrepared=ready;self.diagnostic("recoveryPrerollFinished")
    }}
    Task { [weak self] in
     try? await Task.sleep(nanoseconds:5_000_000_000)
     guard let self=self,self.prerollGeneration==pg,self.prerolling else {return}
     self.prerollGeneration += 1;self.adapter.player.cancelPendingPrerolls();self.prerolling=false;self.diagnostic("recoveryPrerollTimedOut")
    }
   }
   let target=engine.target();let position=adapter.position
   let expected: Any=target.map {$0.0 as Any} ?? NSNull()
   let measuredError: Any=(error != nil ? target.map {($0.0-position) as Any} : nil) ?? NSNull()
   let telemetry: [String:Any]=["clientVersion":"0.5.0","timelineOffsetMs":engine.timelineOffset,"executeAtMs":engine.room?.executeAt ?? 0,"playbackRate":adapter.player.rate,"resyncCount":engine.resyncCount,"bufferedAheadMs":adapter.bufferedAheadMs,"recoveryReserveMs":12000,"positionMs":position,"expectedMs":expected,"errorMs":measuredError,"rttMs":clock.rtt,"version":engine.room?.version ?? 0,"ready":bufferReady,"itemReady":adapter.ready,"bufferEmpty":item?.isPlaybackBufferEmpty ?? true,"likelyToKeepUp":item?.isPlaybackLikelyToKeepUp ?? false,"prerollPrepared":prerollPrepared,"autoResume":recovering,"buffering":readiness.buffering,"waiting":adapter.buffering,"playing":adapter.player.timeControlStatus == .playing,"serverTimeMs":clock.ready ? clock.serverNow() as Any : NSNull()]
   var connectionTelemetry=telemetry;connectionTelemetry["disconnectCount"]=disconnectCount;connectionTelemetry["lastDisconnectReason"]=lastDisconnectReason;connectionTelemetry["ignoredFrames"]=ignoredFrames
   send(["type":"TELEMETRY","data":connectionTelemetry])
   status="0.4.8 \(isHost ? "HOST" : "GUEST") room=\(credentials?["roomId"] as? String ?? "") v=\(engine.room?.version ?? 0)\n位置 \(Int(adapter.position/1000))s 误差 \(error.map {String(Int($0))} ?? "n/a")ms RTT \(Int(clock.rtt))ms \(adapter.buffering ? "BUFFERING" : "")\n已缓存 \(Int(adapter.bufferedAheadMs/1000))s"
  }
  if ticks%50 == 0 {inspectFormats();updateMediaInfo()}
  if ticks%150 == 0 {pingBurst()}
 }
}

extension TestClient {
 private func applyMembers(_ value: [RoomMember]) {
  let next=value.sorted {$0.userId<$1.userId};if members != next {members=next}
  if let me=value.first(where:{$0.userId == credentials?["userId"] as? String}) {engine.timelineOffset=me.timelineOffset}
 }
 private func acceptChat(_ raw: [String:Any],live: Bool=false) {
  guard let data=try? JSONSerialization.data(withJSONObject:raw),let message=try? JSONDecoder().decode(ChatMessage.self,from:data) else {return}
  outbox.removeValue(forKey:message.clientMessageId)
  chat.accept(message,mine:message.userId == credentials?["userId"] as? String,live:live,now:clock.localNow())
 }
 private var hasBaiduMatch: Bool {(baiduPlaybackURL != nil || localFileURL != nil) && baiduSourceID==engine.room?.mediaUrl && baiduSourceRoom==engine.room?.roomId}
 private func playbackSource(for roomURL: URL) -> URL {
  if localSourceRoomID==engine.room?.roomId,localSourceRoomURL==roomURL.absoluteString {
   if let localFileURL=localFileURL {return localFileURL}
   if let value=MediaSourceCatalog.resolve(activeLocalSource),!activeLocalSource.isEmpty {return value}
  }
  return roomURL
 }
 private func releaseLocalFileAccess() {
  if localFileSecurityScoped,let url=localFileURL {url.stopAccessingSecurityScopedResource()}
  localFileSecurityScoped=false;localFileURL=nil;localFileName=""
 }
 private func errorText(_ code: String) -> String {
  let messages=["STALE_VERSION":"房间状态刚发生变化，请再试一次","HOST_REQUIRED":"只有房主可以执行此操作","HOST_OFFLINE":"房主已离线","SEEK_AFTER_END":"跳转位置超出影片时长","ROOM_FULL":"房间已满","INVALID_SOURCE":"片源链接无效或包含账户凭据","SOURCE_NOT_READY":"等待两端匹配同一百度影片并准备好后再播放","RATE_LIMIT":"操作过于频繁，请稍后再试","EXPIRED":"房间已过期","INVALID_MESSAGE":"消息为空或过长"]
  return messages[code] ?? code
 }
 private func flushOperations() {
  guard isHost,connected,engine.room != nil,inFlight==nil,let first=queuedOperations.first else {return}
  // Changing metadata uses the room snapshot/version, not a playback clock.
  guard clock.ready || ["ROOM_MEDIA","ROOM_SETTINGS"].contains(first["type"] as? String ?? "") else {return}
  let operation=queuedOperations.removeFirst();sequence += 1;inFlightSequence=sequence;inFlight=operation
  inFlightStartedAt=clock.localNow()
  var command=operation;command["sequence"]=sequence;command["baseVersion"]=engine.room?.version ?? 0
  send(command)
 }
 func playLibraryItem(_ item: SavedMedia) {
  guard isRoomHost,isConnected else {requestStatus="房主连接房间后才能切换播放列表影片";return}
  mediaURL=item.url;movieTitle=item.title;setRoomMedia()
 }
 func neighboringMedia(_ direction: Int) {
  guard let url=engine.room?.mediaUrl,let i=library.items.firstIndex(where:{$0.url==url}),library.items.indices.contains(i+direction) else {return}
  playLibraryItem(library.items[i+direction])
 }
 func canMoveMedia(_ direction: Int) -> Bool {
  guard isRoomHost,isConnected,let url=engine.room?.mediaUrl,let i=library.items.firstIndex(where:{$0.url==url}) else {return false}
  return library.items.indices.contains(i+direction)
 }
 func setRoomMedia() {
  guard !isSettingRoomMedia else {return}
  guard isHost,let room=credentials?["roomId"] as? String else {mediaFeedback.requestStatus="只有房主可以设置房间影片，请先创建或加入房间。";return}
  guard let url=MediaSourceCatalog.resolve(mediaURL),MediaSourceCatalog.canShare(mediaURL) else {mediaFeedback.requestStatus="片源链接无效或包含账户凭据，请检查 HTTP / HLS / WebDAV 文件链接。";return}
  let title=movieTitle.trimmingCharacters(in:.whitespacesAndNewlines)
  guard title.unicodeScalars.count<=160 else {mediaFeedback.requestStatus="影片标题过长（最多160字）。";return}
  guard queuedOperations.count<8 else {mediaFeedback.requestStatus="请等待前面的操作完成。";return}
  let change=PendingRoomMedia(roomID:room,url:url.absoluteString,title:title)
  pendingRoomMedia=change;isSettingRoomMedia=true
  mediaFeedback.requestStatus=connected ? "正在设置房间影片，等待服务器确认…" : "换片请求已保留，等待房间重连…"
  if connected {queuedOperations.append(change.operation);flushOperations()}
 }
 private func finishRoomMedia(_ text: String) {
  pendingRoomMedia=nil;isSettingRoomMedia=false;mediaFeedback.requestStatus=text
 }
 private func restorePendingRoomMedia() {
  guard let change=pendingRoomMedia,let room=engine.room else {return}
  guard change.roomID==room.roomId,isHost else {finishRoomMedia("房间或房主已改变，请重新设置影片。");return}
  if change.matches(room) {finishRoomMedia("房间影片已设置；重连后已确认。")}
  else {mediaFeedback.requestStatus="连接已恢复，正在设置房间影片…";queuedOperations.append(change.operation);flushOperations()}
 }
 func applyLocalSource() {
  guard let roomURL=engine.room?.mediaUrl,let room=URL(string:roomURL) else {requestStatus="请先加入房间";return}
  guard BaiduMediaReference(value:roomURL)==nil else {requestStatus="当前房间使用文件匹配，请点“选择本地影片”或使用自己的百度授权选片。";return}
  if !localMediaURL.isEmpty && MediaSourceCatalog.resolve(localMediaURL)==nil {requestStatus="本机片源需要 HTTP、HLS 或 WebDAV 文件直链";return}
  releaseLocalFileAccess();activeLocalSource=localMediaURL;localSourceRoomURL=roomURL;localSourceRoomID=engine.room?.roomId ?? "";loadMedia(playbackSource(for:room))
  requestStatus=localMediaURL.isEmpty ? "恢复房间片源" : "本机片源已应用；链接未传给服务器或对方，请确认同一剪辑版本"
 }
 func beginLocalFileSelection(publishRoom: Bool=true) {
  localQualityCandidate=nil
  requestStatus="请选择已下载的本地影片。"
  localSelectionGeneration += 1;pendingLocalFile=nil
  localSelectionRoom=engine.room?.roomId ?? (credentials?["roomId"] as? String ?? "")
  localSelectionMedia=engine.room?.mediaUrl ?? "";localSelectionPublishes=publishRoom
 }
 func cancelLocalFileSelection() {requestStatus="已取消选择本地影片。"}
 func useLocalFile(_ url: URL,confirmedVariant: LocalQualityCandidate? = nil) {
  requestStatus="已选中 \(url.lastPathComponent)，正在读取本地影片…"
  guard connected,let room=engine.room else {
   if confirmedVariant != nil {releaseLocalFileAccess();requestStatus="连接已改变，请重连后重新选择另一画质。";return}
   if !localSelectionRoom.isEmpty {pendingLocalFile=url;requestStatus="本地影片已选择，正在恢复房间连接…"}
   else {requestStatus="请先创建或加入房间，再选择本地影片"}
   return
  }
  if let candidate=confirmedVariant,room.roomId != candidate.roomID || room.mediaUrl != candidate.mediaURL {releaseLocalFileAccess();requestStatus="房间或影片已改变，请重新选择另一画质。";return}
  if !localSelectionRoom.isEmpty && (room.roomId != localSelectionRoom || (!localSelectionMedia.isEmpty && room.mediaUrl != localSelectionMedia)) {requestStatus="房间或影片已改变，请重新选择本地影片";return}
  localSelectionGeneration += 1;let selection=localSelectionGeneration
  releaseLocalFileAccess()
  let scoped=url.startAccessingSecurityScopedResource()
  guard scoped || FileManager.default.isReadableFile(atPath:url.path) else {requestStatus="无法读取这个本地文件，请确认影片已完整下载到 iPad 的“文件”App";return}
  localFileURL=url;localFileSecurityScoped=scoped;localFileName=url.lastPathComponent
  Task {
  do {
   let existing=BaiduMediaReference(value:room.mediaUrl)
   var reference=existing
   if existing != nil || (isHost && localSelectionPublishes) {
    requestStatus="正在核对本地文件，只读取少量首/中/尾数据。"
    let identity=try await Task.detached(priority:.userInitiated) {try BaiduFileIdentity.localFile(url)}.value
    guard selection==localSelectionGeneration,engine.room?.roomId==room.roomId,engine.room?.mediaUrl==room.mediaUrl else {return}
    if let target=existing {
     if !target.matches(fingerprint:identity.fingerprint,size:identity.size),confirmedVariant==nil {
      localQualityCandidate=LocalQualityCandidate(url:url,roomID:room.roomId,mediaURL:room.mediaUrl,roomTitle:roomTitle)
      requestStatus="文件指纹不同；如果这是同一影片的另一画质，请核对剪辑后确认。";return
     }
    } else if isHost {
     reference=BaiduMediaReference.create(fingerprint:identity.fingerprint,size:identity.size)
     guard reference != nil else {releaseLocalFileAccess();requestStatus="本地文件身份生成失败，请重新选择。";return}
    }
   }
   baiduPlaybackURL=nil;baiduFileName="";activeLocalSource="";localMediaURL="";localSourceRoomID=room.roomId
   variantRoomID=confirmedVariant == nil ? "" : room.roomId
   variantMediaURL=confirmedVariant == nil ? "" : room.mediaUrl
   variantReferenceDuration=confirmedVariant == nil ? 0 : room.duration ?? 0
   if let reference=reference {
    guard !isHost || queuedOperations.count<8 else {releaseLocalFileAccess();requestStatus="请等待前面的操作完成";return}
    baiduSourceID=reference.value;baiduSourceRoom=room.roomId;localSourceRoomURL=reference.value
    if isHost && existing==nil {
     queuedOperations.append(["type":"ROOM_MEDIA","data":["mediaUrl":reference.value,"title":String(url.lastPathComponent.prefix(160))]]);flushOperations()
     requestStatus="本地影片已设为房间文件；好友选择本地或百度网盘里的同一文件即可同步。"
    } else {
     loadMedia(url);requestStatus=confirmedVariant == nil ? "本地同一文件已匹配；影片只从这台 iPad 读取，不会上传或共享。" : "已使用本地另一画质，等待双方时长核对。"
    }
   } else {
    baiduSourceID="";baiduSourceRoom="";localSourceRoomURL=room.mediaUrl
    loadMedia(url);requestStatus="本地影片已应用；文件只从这台 iPad 读取，不会上传或共享。"
   }
  } catch {
   guard selection==localSelectionGeneration else {return}
   releaseLocalFileAccess();requestStatus="读取本地影片失败，请确认文件已完整下载并可在“文件”App中打开。"
  }
  }
 }
 func confirmLocalQuality(_ selected: LocalQualityCandidate? = nil) {
  // SwiftUI can dismiss the alert binding before invoking its button action.
  // The button passes the actual reviewed selection, independent of that order.
  guard let candidate=selected ?? localQualityCandidate else {return}
  localQualityCandidate=nil;useLocalFile(candidate.url,confirmedVariant:candidate)
 }
 func cancelLocalQuality() {
  guard localQualityCandidate != nil else {return}
  localQualityCandidate=nil;releaseLocalFileAccess();requestStatus="已取消使用另一画质。"
 }
 func clearLocalFileSource() {
  localQualityCandidate=nil;variantRoomID="";variantMediaURL=""
  localSelectionGeneration += 1;pendingLocalFile=nil
  guard let room=engine.room else {releaseLocalFileAccess();requestStatus="本地影片已清除";return}
  let wasMatched=BaiduMediaReference(value:room.mediaUrl) != nil
  releaseLocalFileAccess();activeLocalSource="";localMediaURL="";localSourceRoomURL="";localSourceRoomID=""
  if wasMatched {
   baiduSourceID="";baiduSourceRoom="";stopUnmatchedMedia()
   requestStatus="本地影片已清除；当前房间仍需重新选择同一文件。"
  } else if let url=HTTPSource().resolve(room.mediaUrl) {
   loadMedia(url);requestStatus="本地影片已清除，已恢复房间片源。"
  }
 }
 private func stopUnmatchedMedia() {
  mediaLoadGeneration += 1;mkvRemux.stop();adapter.pause();adapter.player.replaceCurrentItem(with:nil);externalSubtitles.clear();currentOriginalURL=nil
 }
 func useBaiduSource(_ url: URL,file: BaiduFile,confirmedRoomID: String? = nil,confirmedMediaURL: String? = nil) -> Bool {
  guard connected,let room=engine.room else {requestStatus="请先创建或加入房间，再选择百度影片";return false}
  guard BaiduSourceAdapter.allowedURL(url),let identity=BaiduMediaReference.create(fingerprint:file.fingerprint,size:file.size) else {requestStatus="百度未提供可核对的文件指纹/大小，无法匹配；请重新读取文件。";return false}
  let reference: String
  let variant=confirmedRoomID != nil && confirmedMediaURL != nil
  if variant,room.roomId != confirmedRoomID || room.mediaUrl != confirmedMediaURL {requestStatus="房间或影片已改变，请重新核对另一画质。";return false}
  if isHost && !variant {reference=identity.value}
  else {
   guard let target=BaiduMediaReference(value:room.mediaUrl) else {requestStatus="请等待房主先选择百度影片";return false}
   guard variant || target.matches(fingerprint:file.fingerprint,size:file.size) else {requestStatus="所选文件指纹不同；可以转存同一文件，或核对后选择同一影片的另一画质。";return false}
   reference=target.value
  }
  guard !isHost || variant || queuedOperations.count<8 else {requestStatus="请等待前面的操作完成";return false}
  releaseLocalFileAccess();baiduSourceID=reference;baiduSourceRoom=room.roomId;baiduPlaybackURL=url;baiduFileName=file.name
  activeLocalSource=url.absoluteString;localSourceRoomURL=reference;localSourceRoomID=room.roomId;localMediaURL=""
  variantRoomID=variant ? room.roomId : "";variantMediaURL=variant ? room.mediaUrl : ""
  variantReferenceDuration=variant ? room.duration ?? 0 : 0
  if isHost && !variant {
   queuedOperations.append(["type":"ROOM_MEDIA","data":["mediaUrl":reference,"title":String(file.name.prefix(160))]]);flushOperations()
   requestStatus="正在设置房间百度影片；好友需在自己的网盘选择同一文件。"
  } else {loadMedia(url);requestStatus=variant ? "已使用百度另一画质，等待双方时长核对。" : "同一百度文件已匹配；等待双方准备好后由房主播放。"}
  return true
 }
 func restoreRoomSource() {
  guard engine.room != nil else {requestStatus="请先加入房间";return}
  if usingLocalFile {clearLocalFileSource();return}
  if BaiduMediaReference(value:engine.room?.mediaUrl ?? "") != nil {clearBaiduSource();return}
  baiduPlaybackURL=nil;baiduFileName="";localMediaURL="";applyLocalSource()
  requestStatus="已恢复房间片源；这是房间当前影片，不会把百度影片传给好友。"
 }
 func clearBaiduSource() {
  variantRoomID="";variantMediaURL=""
  guard let url=baiduPlaybackURL else {return}
  baiduPlaybackURL=nil;baiduFileName="";baiduSourceID="";baiduSourceRoom=""
  if activeLocalSource==url.absoluteString {
   activeLocalSource="";localMediaURL="";localSourceRoomURL="";localSourceRoomID=""
   mediaLoadGeneration += 1;mkvRemux.stop();adapter.pause();adapter.player.replaceCurrentItem(with:nil);loadedURL=""
   requestStatus="百度本机片源已清除；恢复房间片源请点应用本机片源"
  }
 }
 func saveProfile() {
  guard let offset=Double(offsetSeconds),offset.isFinite,abs(offset)<=600,nickname.count<=32 else {requestStatus="昵称最多32字，偏移范围为正负600秒";return}
  UserDefaults.standard.set(nickname,forKey:"nickname");UserDefaults.standard.set(offsetSeconds,forKey:"timelineOffset")
  send(["type":"PROFILE_UPDATE","data":["name":nickname,"timelineOffset":offset*1000]])
 }
 func setWaiting(_ enabled: Bool) {
  guard isHost,connected else {return};queuedOperations.append(["type":"ROOM_SETTINGS","data":["waitForPeer":enabled]]);flushOperations()
 }
 func sendChat() {
  let text=chatDraft.text.trimmingCharacters(in:.whitespacesAndNewlines)
  guard connected else {requestStatus="连接恢复后再发送消息";return}
  guard !text.isEmpty,text.unicodeScalars.count<=1000,text.utf8.count<=6000,outbox.count<20 else {requestStatus="消息为空或超过1000字";return}
  let id=UUID().uuidString;let message: [String:Any]=["type":"CHAT_MESSAGE","data":["text":text,"clientMessageId":id]];outbox[id]=message;send(message);chatDraft.text=""
 }
 func sendVoiceDanmaku(_ text:String)->Bool {
  guard connected,!text.isEmpty,text.unicodeScalars.count<=500,outbox.count<20 else {return false}
  let id="voice:"+UUID().uuidString
  let message:[String:Any]=["type":"CHAT_MESSAGE","data":["text":text,"clientMessageId":id,"source":"voice"]]
  outbox[id]=message;send(message);return true
 }
 func sendTyping() {
  let now=clock.localNow();guard connected,now-lastTyping>1000 else {return};lastTyping=now;send(["type":"CHAT_TYPING"])
 }
 func react(_ emoji: String) {send(["type":"REACTION","data":["emoji":emoji]])}
 func leaveRoom() {voice.disable();guard connected else {clearRoom();return};send(["type":"ROOM_LEAVE"])}
 private func clearRoom() {
  voice.disable()
  localQualityCandidate=nil;variantRoomID="";variantMediaURL=""
  if pendingRoomMedia != nil {finishRoomMedia("已离开房间，换片请求已取消。")}
  localSelectionGeneration += 1;pendingLocalFile=nil;localSelectionRoom="";localSelectionMedia=""
  externalSubtitles.clear()
  releaseLocalFileAccess();mkvRemux.stop();baiduSourceID="";baiduSourceRoom="";baiduPlaybackURL=nil;baiduFileName="";activeLocalSource="";localMediaURL="";localSourceRoomURL="";localSourceRoomID=""
  mediaLoadGeneration += 1;generation += 1;connected=false;socket?.cancel(with:.goingAway,reason:nil);socket=nil;credentials=nil;UserDefaults.standard.removeObject(forKey:"credentials")
  outbox=[:];outboxRoom="";queuedOperations=[];inFlight=nil;inFlightStartedAt=nil;isHost=false;isRoomHost=false;engine.resetSession();adapter.player.replaceCurrentItem(with:nil);loadedURL="";roomID="";members=[];chat.reset("");roomNotice="";roomTitle="一起看电影";status="已离开房间";requestStatus=""
 }
 func handleBackground() {voice.disable();mkvRemux.stop();mediaLoadGeneration += 1;loadedURL="";adapter.player.cancelPendingPrerolls();prerolling=false;foreground=false;chat.visible=false;generation += 1;connected=false;socket?.cancel(with:.goingAway,reason:nil);socket=nil;queuedOperations=[];inFlight=nil;inFlightStartedAt=nil;engine.resetSession();adapter.player.replaceCurrentItem(with:nil);status="后台暂停，返回后自动同步";if pendingRoomMedia != nil {mediaFeedback.requestStatus="换片请求已保留，返回房间后继续确认…"}}
 func handleForeground() {guard !foreground else {return};foreground=true;chat.visible=true;if credentials != nil {connect()}}
 var durationWarning: String {
  let durations=members.filter {$0.duration>0}.map {$0.duration-$0.timelineOffset}
  guard durations.count==2,abs(durations[0]-durations[1])>5000 else {return ""}
  return "双方影片时长不同，请确认剪辑一致；时间偏移只能校准片头差异。"
 }
}
