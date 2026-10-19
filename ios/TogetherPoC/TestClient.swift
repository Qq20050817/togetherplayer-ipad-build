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
 let roster=RoomRosterState()
 var members:[RoomMember] {
  get {roster.members}
  set {
   if !RoomRosterState.samePresentation(roster.members,newValue) {objectWillChange.send()}
   roster.update(newValue)
  }
 }
 @Published var waitForPeer=true
 @Published var roomTitle="一起看电影"
 @Published var roomNotice=""
 @Published var isRoomHost=false
 @Published var isConnected=false
 let chat=ChatEngine()
 @Published var plotPoll:[String:Any]?
 @Published var supportsBlockingPolls=false
 var plotPollWaiting:Bool {plotPoll?["waitingForAnswers"] as? Bool == true}
 let plotIntelligence=PlotIntelligence(requireCompleteFilm:true)
 let filmMaterials=FilmMaterialExportSession()
 let questionBankRuntime=FilmQuestionBankRuntime()
 private var lastBankPollDispatch = -Double.infinity
 private var bankNativePlaybackEnded=false
 var bankMovieURL:URL? {currentOriginalURL}
 var bankMovieKey:String? {plotDisplayPosition()?.key}
 // Material-only imported subtitles win. Playback-side external subtitles are
 // used only when enabled, so stale imports cannot override embedded tracks.
 var bankSubtitle:SubtitleDocument? {
  if let ai=aiOnlySubtitle,ai.film==plotDisplayPosition()?.key {return ai.document}
  return externalSubtitles.enabled ? externalSubtitles.completeExternalForAI : nil
 }
 var hasMaterialOnlySubtitle:Bool {aiOnlySubtitle?.film==plotDisplayPosition()?.key}
 var bankSubtitleSourceLabel:String {
  if let ai=aiOnlySubtitle,ai.film==plotDisplayPosition()?.key,!ai.document.cues.isEmpty {return aiOnlySubtitleOrigin}
  if externalSubtitles.enabled && externalSubtitles.completeExternalForAI != nil {return "当前播放的外挂字幕"}
  return "原片内置字幕（未选备用字幕）"
 }
 var bankCanPublish:Bool {
  isConnected && isRoomHost && clock.ready && supportsBlockingPolls && clock.localNow()-lastBankPollDispatch>=15_000 &&
   variantDurationCheck == .compatible && adapter.player.rate>0 &&
   !adapter.isSeeking && engine.room?.state=="playing" &&
   (plotPoll == nil || plotPoll?["revealed"] as? Bool == true)
 }
 var bankPlaybackPositionMs:Double {max(0,adapter.position)}
 var bankCanFinish:Bool {
  isConnected && isRoomHost && clock.ready && supportsBlockingPolls &&
  variantDurationCheck == .compatible && adapter.player.rate>0 &&
  !adapter.isSeeking && engine.room?.state == "playing" && !plotPollWaiting
 }
 var bankSafeRevealPositionMs:Double {
  guard clock.ready,let room=engine.room else{return 0}
  let peers=members.filter{$0.online && $0.userId != credentials?["userId"] as? String}.map{max(0,$0.position-$0.timelineOffset)}
  return FilmBankTimeline.safeReveal(playerMs:bankPlaybackPositionMs,roomMs:room.target(clock.serverNow()).0,hostOffset:engine.timelineOffset,peers:peers)
 }
 private func tickFilmBank() {
  guard questionBankRuntime.active != nil else{return}
questionBankRuntime.tick(filmKey:bankMovieKey,positionMs:bankPlaybackPositionMs,durationMs:adapter.duration,canPublish:bankCanPublish,
    canReveal:isRoomHost && isConnected,revealPositionMs:bankSafeRevealPositionMs,
    naturalEnd:bankNativePlaybackEnded && adapter.duration>0 && bankPlaybackPositionMs>=adapter.duration-2500,
    canFinish:bankCanFinish,
    pauseAtStoryEnd:{[weak self] in
     guard let self,self.isRoomHost,self.isConnected else{return}
     self.control("PAUSE")
    },
    participantNames:Dictionary(uniqueKeysWithValues:members.map{($0.userId,$0.name)}),
    subtitleShown:plotIntelligence.isSubtitleCurrentlyShown?() ?? true,
    captionSequence:externalSubtitles.plotCaptionSequence,
    publish:{[weak self] question in guard let self,self.bankCanPublish else{return};self.lastBankPollDispatch=self.clock.localNow();self.publishPlotPoll(question)},
    reveal:{[weak self] message in
     guard let self,self.isRoomHost,self.isConnected else{return}
     let payload:[String:Any]=["type":"CHAT_MESSAGE","data":["text":message.text,"clientMessageId":message.id]]
     self.outbox[message.id]=payload;self.send(payload)
    })
 }
 func recoverFilmBankFinale() {
  questionBankRuntime.finishAlreadyViewed(filmKey:bankMovieKey,positionMs:bankPlaybackPositionMs,
   durationMs:adapter.duration,participantNames:Dictionary(uniqueKeysWithValues:members.map{($0.userId,$0.name)}))
 }
 func beginFilmMaterialsExport() {
  let title=playbackTitle.isEmpty ? bankMovieURL?.deletingPathExtension().lastPathComponent ?? "电影" : playbackTitle
  let chosen=requestedSubtitleIndex ?? -1
  let option=subtitleGroup?.options.indices.contains(chosen)==true ? subtitleGroup?.options[chosen] : nil
  let stream=mkvRemux.aiSubtitleStreamIndices.indices.contains(chosen) ? mkvRemux.aiSubtitleStreamIndices[chosen] : nil
  filmMaterials.begin(url:bankMovieURL,title:title,external:bankSubtitle,allowOCR:true,preferredTitle:subtitleLabels.indices.contains(chosen) ? subtitleLabels[chosen] : nil,preferredLanguage:option?.extendedLanguageTag,preferredStreamIndex:stream,preferredDurationSeconds:adapter.duration/1000)
 }
 let library=MediaLibrary()
 var plotPollSubmitted:Bool {
  guard let myID=credentials?["userId"] as? String else {return false}
  return (plotPoll?["submitted"] as? [String] ?? []).contains(myID)
 }
 var plotPollAnswers:[String:String] {plotPoll?["answers"] as? [String:String] ?? [:]}
 var plotMyUserID:String {credentials?["userId"] as? String ?? ""}

 @Published var videoBadges: [String]=[]
 var requestedPlaying: Bool {localVideoTest ? adapter.player.timeControlStatus != .paused : (playbackNeedsRecovery ? false : (optimisticPlaying ?? (engine.room?.state == "playing")))}
 // Show the selected playback source, not a stale room title. Keep the
 // canonical room title untouched when a guest chooses another quality.
 var playbackTitle: String {
  if usingLocalFile {return FilmSourceTitle.fromFileName(localFileName) ?? localFileName}
  if usingBaiduSource {return FilmSourceTitle.fromFileName(baiduFileName) ?? baiduFileName}
  if !activeLocalSource.isEmpty,
     localSourceRoomURL==engine.room?.mediaUrl,
     localSourceRoomID==engine.room?.roomId,
     currentOriginalURL?.absoluteString==activeLocalSource,
     let name=FilmSourceTitle.fromMediaURL(activeLocalSource) {return name}
  if roomTitle=="一起看电影",
     let name=FilmSourceTitle.fromMediaURL(engine.room?.mediaUrl ?? "") {return name}
  return roomTitle
 }
 // Called only by the user-editable media URL field. Programmatic incoming
 // room snapshots must not overwrite a custom title.
 func updateRoomMediaDraft(_ raw:String) {
  mediaURL=raw
  if let name=FilmSourceTitle.fromMediaURL(raw) {movieTitle=name}
 }
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
 private let movieSelectionStore:RoomMovieSelectionStore
 private var rememberedMovie:RoomMovieSelection?
 private var restoreMovieTask:Task<RoomMovieSelection.Resolved,Error>?
 private var saveMovieTask:Task<RoomMovieSelection,Error>?
 @Published private(set) var localMoviePersistenceStatus=""
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
 private var nativeIndexRequestKey=""
 private var nativeWindowRecoveryTask:Task<Void,Never>?
 private var nativeWindowRecoverySerial=0
 private var nativeIndexTask:Task<Void,Never>?
 private var originalPGSDecodeTask:Task<Void,Never>?
 private let compatibilityPreparation: ((URL,[String:String]) async throws -> URL)?
 private var currentOriginalURL: URL?
 private var aiOnlySubtitle:(film:String,document:SubtitleDocument)?
 private var aiOnlySubtitleOrigin="素材专用备用字幕"
 @Published private(set) var aiOnlySubtitleImportStatus=""
 private var activeLocalSource=""
 private var localSourceRoomURL=""
 private var localSourceRoomID=""
 private var speedHoldID:String?
 private var speedHoldTimer:Timer?
 @Published private var optimisticPlaying:Bool?
 private var optimisticUntil=0.0
 private var controlSettleUntil=0.0
 private(set) var supportsInstantControls=false
 var holdingLocalPause:Bool {
  guard optimisticPlaying == false,optimisticRoomID == engine.room?.roomId,
        clock.localNow()<optimisticUntil else {return false}
  return inFlight != nil || !queuedOperations.isEmpty || engine.target()?.1 == "playing"
 }
 private var optimisticRoomID=""
 private var lastStepTarget:Double?
 private var lastStepTime=0.0
 private var speedHoldReleaseUntil=0.0
 private var foreground=true
 private var lastTyping=0.0
 private var prerolling=false
 private var prerollGeneration=0
 private var prerollPrepared=false
 private var recoveryStartedAt: Double?
 private var lastPrerollAt = -Double.infinity
 private var playbackRecovery=PlaybackRecovery()
 private var localPlayIntent=false
 @Published private(set) var playbackNeedsRecovery=false
 private var recoveryResumePosition:Double?
 private var recoveryRebuilds=0
 private var pendingPlotPredictionReview:PlotPendingReview?
 private var reviewedPlotPollIDs=Set<String>()
 private var plotPredictionReviewTask:Task<Void,Never>?
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
 // Remember an explicit embedded-track choice until its asynchronous media group is available.
 // The choice survives reloading the same film but must not be applied to another movie.
 private var requestedSubtitleIndex: Int?
 private var requestedSubtitleFilmKey=""
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
 lazy var visualSampler=PlotVisualSampler(player:adapter.player)
 let clock=ClockSync()
 lazy var engine=SyncEngine(adapter,clock)
 private var registering=false
 private var credentialServer=UserDefaults.standard.string(forKey:"server") ?? "https://together.xiaokai123.de5.net"
 private var credentials: [String:Any]?
 private var socket: URLSessionWebSocketTask?
 @Published private(set) var p2pStatus="Muse 房间同步"
 private var p2pSupported=false
 private var p2pPeerID=""
 private var p2pRoomID=""
 private var p2pEstablished=false
 private var p2pLastOfferAt=0.0
 private var p2pFastUntil=0.0
 private var p2pFastVersion: Int64=0
 private var p2pGate=P2PFastPathGate()
 lazy var p2pTransport: P2PWebRTCTransport = {
  let transport=P2PWebRTCTransport()
  transport.onSignal={ [weak self] kind,payload in
   guard let self,self.connected,self.p2pSupported,!self.p2pPeerID.isEmpty else{return}
   self.send(["type":"P2P_SIGNAL","data":["targetUserId":self.p2pPeerID,"kind":kind,"payload":payload]])
  }
  transport.onState={ [weak self] state in
   guard let self else{return}
   self.p2pEstablished=state == "open"
   self.p2pGate.setChannelAlive(self.p2pEstablished)
   self.p2pGate.verifyPeer(fromAuthoritativeRoster:self.p2pEstablished && self.p2pKnownPeerOnline())
   self.p2pStatus=state == "open" ? "P2P 直连" : "Muse 备用（P2P \(state)）"
  }
  transport.onControl={ [weak self] frame in self?.receiveP2PControl(frame) }
  return transport
 }()
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
 private let tickPulse=MainActorPulse()
 private var isHost=false
 private var localVideoTest=false
 private var observers: [NSObjectProtocol]=[]
 private var playerObservation: NSKeyValueObservation?
 private var itemObservation: NSKeyValueObservation?
 init(compatibilityPreparation: ((URL,[String:String]) async throws -> URL)? = nil,automaticallyConnect: Bool=true,messageSender: (([String:Any])->Void)? = nil,movieSelectionStore:RoomMovieSelectionStore? = nil) {
  self.compatibilityPreparation=compatibilityPreparation
  self.messageSender=messageSender
  self.movieSelectionStore=movieSelectionStore ?? RoomMovieSelectionStore.applicationDefault()
  do {self.rememberedMovie=try self.movieSelectionStore.load()} catch {localMoviePersistenceStatus="保存的本机影片记录暂不可读取，请重新选择一次。"}
  plotIntelligence.displayPosition={ [weak self] in self?.plotDisplayPosition() }
  plotIntelligence.frame={ [weak self] in
   // Offline local analysis should not require a live room transport.
   guard let self,let display=self.plotDisplayPosition() else{return nil}
   let position=display.position,key=display.key
   var prediction:PlotPrediction?
   if let poll=self.plotPoll,poll["revealed"] as? Bool==true,let id=poll["id"] as? String,let question=poll["question"] as? String,let end=poll["revealPositionMs"] as? Double {
    prediction=PlotPrediction(id:id,end:max(0,(end+self.engine.timelineOffset)/1000),question:question,answers:self.plotPollAnswers)
   }
   let observed=self.externalSubtitles.observedPlotEvidence()
   let visuals=self.visualSampler.evidence(cutoff:position)
   let duration=self.adapter.player.currentItem?.duration.seconds ?? .nan
   let checkpoint=self.plotIntelligence.wholeFilm.checkpoint(at:position,film:key) ?? self.externalSubtitles.plannedQuestionCheckpoint(at:position,duration:duration)
   return PlotFrame(key:key,position:position,evidence:observed+visuals,
    prediction:prediction,plannedCheckpoint:checkpoint)
  }
  // V2 automation is owned solely by the imported bank. Legacy AI remains
  // available for an explicit manual request, never a background cloud call.
  plotIntelligence.mayPublishAutomatically={false}
  plotIntelligence.automaticAvailabilityReason={ [weak self] in
   guard let self else{return "房间控制器不可用"}
   guard self.isConnected else{return "房间尚未连接；题库自动提问需要 iPad 房主在线，素材可在本机制作"}
   return self.questionBankRuntime.active == nil ? "请先制作并导入电影题库；正常播放不会请求 AI" : "已导入题库负责时间节点提问，不再实时生成"
  }
  plotIntelligence.isSubtitleCurrentlyShown={ [weak self] in
   guard let self else{return true}
   return self.externalSubtitles.originalPGSFrame != nil ||
     !self.externalSubtitles.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty
  }
  plotIntelligence.currentCaptionSequence={ [weak self] in self?.externalSubtitles.plotCaptionSequence ?? 0 }
  externalSubtitles.plotCaptionBoundaryChanged={ [weak self] in
   _ = self?.plotIntelligence.publishPendingAutomaticQuestion()
   self?.tickFilmBank()
  }
  plotIntelligence.publishAutomatically={ [weak self] question in
   guard let self,self.isConnected,self.isRoomHost,self.supportsBlockingPolls,question.blocking else{return}
   self.publishPlotPoll(question)
  }
  questionBankRuntime.onBankReady={ [weak self] in
   guard let self else{return}
   self.plotIntelligence.cancel();self.plotIntelligence.wholeFilm.cancel()
   self.pendingPlotPredictionReview=nil;self.plotPredictionReviewTask?.cancel()
   self.questionBankRuntime.observePoll(self.plotPoll)
  }
  plotIntelligence.backgroundCollectionAllowed={ [weak self] in
   guard let self else{return false}
   return self.foreground && self.questionBankRuntime.active == nil
  }
  plotIntelligence.start()
  plotIntelligence.visualEvidenceEnabled=visualSampler.enabled
  visualSampler.onEnabledChanged={ [weak self] enabled in
   self?.plotIntelligence.visualEvidenceEnabled=enabled
   self?.plotIntelligence.playbackJumped()
  }
  visualSampler.onNewEvidence={ [weak self] in self?.plotIntelligence.visualChanged() }
  externalSubtitles.plotDidSeek={ [weak self] in self?.plotIntelligence.playbackJumped();self?.questionBankRuntime.playbackJumped();self?.bankNativePlaybackEnded=false }
  externalSubtitles.plotCaptionChanged={ [weak self] text in self?.plotIntelligence.subtitleChanged(text) }
  externalSubtitles.plotFullFilmReset={ [weak self] in self?.plotIntelligence.resetFullFilmPreparation() }
  externalSubtitles.onAIOnlyPGSChanged={ [weak self] in
   guard let self,self.mkvRemux.pgsOCRRendition else{return}
   if !self.externalSubtitles.convertPGSForAI {
    self.nativeIndexTask?.cancel();self.nativeIndexTask=nil;self.nativeIndexRequestKey=""
    self.externalSubtitles.clearAIOnlyOCRIndex()
    self.externalSubtitles.nativeIndexDisabledForAI()
   } else if self.selectedSubtitleIndex>=0,let item=self.adapter.player.currentItem {
    self.prepareNativeSubtitleIndex(item:item,track:self.selectedSubtitleIndex)
   }
  }
  externalSubtitles.onOriginalPGSBitmapChanged={ [weak self] in
   guard let self else{return}
   if !self.externalSubtitles.originalPGSBitmapEnabled {
    self.originalPGSDecodeTask?.cancel();self.originalPGSDecodeTask=nil
    self.externalSubtitles.clearOriginalPGS()
   } else if self.selectedSubtitleIndex>=0,let item=self.adapter.player.currentItem {
    self.prepareOriginalPGSBitmap(item:item,track:self.selectedSubtitleIndex)
   }
  }
  plotIntelligence.wholeFilm.onEmbeddedTranscript={ [weak self] document in self?.externalSubtitles.installCompleteEmbeddedForAI(document) }
  externalSubtitles.plotFullSubtitleIndexed={ [weak self] document,source,checkpoints in
   guard let self,let key=self.plotIntelligence.frame?()?.key else{return}
   self.plotIntelligence.prepareFullFilm(document,source:source,key:key,checkpoints:checkpoints)
   if source=="external-subtitle" {self.prepareCompleteFilmForAI()}
  }
  externalSubtitles.nativeWindowRecovery={ [weak self] item,position in self?.recoverCurrentNativeSubtitleWindow(item:item,position:position) }
  externalSubtitles.nativeSelectionHealthCheck={ [weak self] in self?.restoreSelectedNativeSubtitleIfNeeded() }
  voiceDucker=VoiceVolumeDucker(player:adapter.player)
  voice.sendText={ [weak self] text in self?.sendVoiceDanmaku(text) ?? false }
  voice.roomKey={ [weak self] in self?.engine.room?.roomId ?? "" }
  voice.duck={ [weak self] lowered in if lowered {self?.voiceDucker?.begin()} else {self?.voiceDucker?.end()} }
  do {try AVAudioSession.sharedInstance().setCategory(.playback,mode:.moviePlayback);try AVAudioSession.sharedInstance().setSupportsMultichannelContent(true);try AVAudioSession.sharedInstance().setActive(true)} catch {requestStatus="音频会话设置失败"}
  observers.append(NotificationCenter.default.addObserver(forName:.AVPlayerItemDidPlayToEndTime,object:nil,queue:.main) { [weak self] note in
   Task { @MainActor in
    guard let self,let item=note.object as? AVPlayerItem,item === self.adapter.player.currentItem else{return}
    self.bankNativePlaybackEnded=true
    self.tickFilmBank()
   }
  })
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
  let pulse=tickPulse
  let timer=Timer(timeInterval:0.1,repeats:true) {[weak self] _ in
   pulse.request {[weak self] in self?.tick()}
  }
  self.timer=timer;RunLoop.main.add(timer,forMode:.common)
  if automaticallyConnect,credentials != nil {connect()}
 }
 deinit {timer?.invalidate();restoreMovieTask?.cancel();saveMovieTask?.cancel();if localFileSecurityScoped,let url=localFileURL {url.stopAccessingSecurityScopedResource()};for observer in observers {NotificationCenter.default.removeObserver(observer)}}
 private func plotDisplayPosition()->PlotDisplayPosition? {
  guard adapter.player.currentItem != nil else{return nil}
  let identity=engine.room?.mediaUrl ?? currentOriginalURL?.absoluteString ?? loadedURL
  guard !identity.isEmpty else{return nil}
  var components=URLComponents(string:identity);components?.query=nil;components?.fragment=nil
  return PlotDisplayPosition(key:PlotMemoryStore.key(components?.string ?? identity),position:max(0,adapter.position/1000))
 }
 private func diagnostic(_ event: String) {
  var data: [String:Any]=["diagnostic":true,"event":event,"clientVersion":Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "unknown","version":engine.room?.version ?? 0,"positionMs":adapter.position,"playbackRate":adapter.player.rate,"timeControlStatus":adapter.player.timeControlStatus.rawValue,"localVideoTest":localVideoTest,"localTimeMs":clock.localNow(),"serverTimeMs":clock.ready ? clock.serverNow() as Any : NSNull()]
  data["disconnectCount"]=disconnectCount;data["lastDisconnectReason"]=lastDisconnectReason;data["ignoredFrames"]=ignoredFrames
  if let log=adapter.player.currentItem?.accessLog()?.events.last {
   data["droppedVideoFrames"]=log.numberOfDroppedVideoFrames;data["stalls"]=log.numberOfStalls;data["observedBitrate"]=log.observedBitrate
   if let raw=log.uri,let u=URL(string:raw),u.host=="devstreaming-cdn.apple.com" {data["appleAccessLogPath"]=u.path}
  }
  if let log=adapter.player.currentItem?.errorLog()?.events.last {data["errorStatusCode"]=log.errorStatusCode}
  data["seekInProgress"]=adapter.isSeeking
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
  // Rebuilding the same AVPlayerItem retains the film identity, selected
  // subtitle track and existing plot evidence. The room clock stays intact.
  playbackRecovery.reset();setPlaybackRecoveryVisible(false)
  bankNativePlaybackEnded=false
  questionBankRuntime.playbackJumped()
  // Room media identity remains stable across WebSocket reconnects and
  // refreshed signed playback URLs. Only a genuinely different film resets
  // watched subtitle evidence and imported subtitle state.
  let identity=engine.room?.mediaUrl ?? url.absoluteString
  var components=URLComponents(string:identity);components?.query=nil;components?.fragment=nil
  let plotKey=PlotMemoryStore.key(components?.string ?? identity)
  if requestedSubtitleFilmKey != plotKey {
   pendingPlotPredictionReview=nil;plotPredictionReviewTask?.cancel();plotPredictionReviewTask=nil
   reviewedPlotPollIDs=[]
   requestedSubtitleIndex=nil
   requestedSubtitleFilmKey=plotKey
  }
  if externalSubtitles.isCurrentPlotFilm(plotKey) {plotIntelligence.preserveCurrentFilmEvidence()}
  externalSubtitles.beginPlotFilm(plotKey)
   visualSampler.beginFilm(plotKey)
  currentOriginalURL=url
  filmMaterials.selectMovie(url)
  questionBankRuntime.restore(filmKey:plotKey,source:url,durationMs:0)
  if plotIntelligence.wholeFilm.filmKey != plotKey {plotIntelligence.wholeFilm.reset(film:plotKey)}
  if aiOnlySubtitle?.film != plotKey {aiOnlySubtitle=nil;aiOnlySubtitleImportStatus=""}
  nativeWindowRecoverySerial+=1;nativeWindowRecoveryTask?.cancel();nativeWindowRecoveryTask=nil
  nativeIndexTask?.cancel();nativeIndexTask=nil;nativeIndexRequestKey=""
  originalPGSDecodeTask?.cancel();originalPGSDecodeTask=nil
  mediaLoadGeneration += 1;let g=mediaLoadGeneration
  let useAtmos=atmosReferenceOverride && url.absoluteString==appleReferenceURL
  let needsRemux=forceRemux || MKVRemux.needed(url:url,fileName:url==baiduPlaybackURL ? baiduFileName : nil)
  lastStepTarget=nil;clearOptimisticPlayback();adapter.pause();adapter.resetPendingSeeks();adapter.player.replaceCurrentItem(with:nil)
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
    if localVideoTest && localPlayIntent {adapter.play()}
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
  subtitleGroup=nil;subtitleLabels=[];selectedSubtitleIndex = externalSubtitles.enabled ? -2 : (requestedSubtitleIndex ?? -1)
  videoBadges=[]
  if MediaSourceCatalog.canShare(originalURL.absoluteString),originalURL != baiduPlaybackURL {library.played(originalURL.absoluteString,title:movieTitle)}
  streamInfo="等待读取播放轨道";adapter.pause();adapter.resetPendingSeeks();externalSubtitles.attachNativeOutput(to:item);adapter.player.replaceCurrentItem(with:item);visualSampler.attach(to:item);updateMediaInfo()
  if let position=recoveryResumePosition {
   recoveryResumePosition=nil
   // Seek only after the replacement item has become ready.
   let requested=position
   Task { [weak self,weak item] in
    for _ in 0..<100 {
     guard let self=self,item != nil,self.adapter.player.currentItem === item else {return}
     if self.adapter.ready {self.adapter.seekTo(requested);return}
     try? await Task.sleep(nanoseconds:50_000_000)
    }
   }
  }
  // Show already saved film evidence immediately after the player is reattached.
  Task {await plotIntelligence.collect()}
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
     self.adapter.itemBecameReady(observed)
     if self.localVideoTest && self.localPlayIntent {self.adapter.play()}
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
    let title=option.commonMetadata.first(where:{$0.commonKey == .commonKeyTitle})?.stringValue ?? option.displayName
    if var choices=remuxLabels[title],let first=choices.first {
     choices.removeFirst();remuxLabels[title]=choices;return TrackLabel.localized(first,language:option.extendedLanguageTag)
    }
    return AudioTrackDetail.label(name:title,index:index,language:option.extendedLanguageTag ?? option.locale?.identifier,subtypes:option.mediaSubTypes.map {fourCC($0.uint32Value)},tracks:tracks,optionCount:group?.options.count ?? 0)
   } ?? []
   if let group=group,let current=item.currentMediaSelection.selectedMediaOption(in:group) {selectedAudioIndex=group.options.firstIndex(where:{$0 === current}) ?? -1}
   updateMediaInfo();diagnostic("audioOptionsLoaded")
  }
  Task {
   let group=try? await item.asset.loadMediaSelectionGroup(for:.legible)
   guard generation==trackSelectionGeneration,adapter.player.currentItem === item else {return}
   subtitleGroup=group
   subtitleLabels=group?.options.enumerated().map {index,option in
    let title=option.commonMetadata.first(where:{$0.commonKey == .commonKeyTitle})?.stringValue ?? option.displayName
    return TrackLabel.localized(title,language:option.extendedLanguageTag ?? option.locale?.identifier,subtitle:true)+" · 字幕 \(index+1)"
   } ?? []
   if let group=group {
    // The menu may have been used before AVFoundation exposed this group.
    // Reapply the user choice each time an item is installed or becomes ready.
    if externalSubtitles.enabled || requestedSubtitleIndex == -2 {
     item.select(nil,in:group);selectedSubtitleIndex = -2
    } else if let requested=requestedSubtitleIndex,requested >= 0,group.options.indices.contains(requested) {
     item.select(group.options[requested],in:group);selectedSubtitleIndex=requested
    } else if requestedSubtitleIndex == -1 {
     item.selectMediaOptionAutomatically(in:group);selectedSubtitleIndex = -1
    } else if let current=item.currentMediaSelection.selectedMediaOption(in:group) {
     selectedSubtitleIndex=group.options.firstIndex(where:{$0 === current}) ?? -1
    } else {
     selectedSubtitleIndex = -1
    }
   }
   if selectedSubtitleIndex>=0 && !externalSubtitles.enabled {
    prepareNativeSubtitleIndex(item:item,track:selectedSubtitleIndex)
    prepareOriginalPGSBitmap(item:item,track:selectedSubtitleIndex)
   }
   prepareCompleteFilmForAI()
   diagnostic("subtitleOptionsLoaded")
  }
 }
 func prepareCompleteFilmForAI(force:Bool=false) {
  // V2 never initiates a full-film scan from playback metadata callbacks.
  guard force else{return}
  if questionBankRuntime.active != nil && !force {return}
  guard let source=currentOriginalURL,let key=plotDisplayPosition()?.key else{return}
  if force {plotIntelligence.wholeFilm.reset(film:key)}
  if let ai=aiOnlySubtitle,ai.film==key {
   plotIntelligence.wholeFilm.useExternalForAI(ai.document,film:key)
   return
  }
  if externalSubtitles.enabled,let document=externalSubtitles.completeExternalForAI {
   plotIntelligence.wholeFilm.useExternalForAI(document,film:key)
   return
  }
  let chosen=requestedSubtitleIndex ?? -1
  let title=subtitleLabels.indices.contains(chosen) ? subtitleLabels[chosen] : nil
  let option=subtitleGroup?.options.indices.contains(chosen)==true ? subtitleGroup?.options[chosen] : nil
  let stream=mkvRemux.aiSubtitleStreamIndices.indices.contains(chosen) ? mkvRemux.aiSubtitleStreamIndices[chosen] : nil
  plotIntelligence.wholeFilm.readLocalMovie(source,film:key,title:title,language:option?.extendedLanguageTag,streamIndex:stream,allowOCR:externalSubtitles.convertPGSForAI)
 }
 /// Importing a complete subtitle for AI leaves the viewer's actual subtitle
 /// selection, rendering, audio, and playback timeline completely unchanged.
 func importFullFilmSubtitleForAI(_ url:URL) async {
  guard let key=plotDisplayPosition()?.key else {
   aiOnlySubtitleImportStatus="请先加载影片，再导入用于 AI 的完整字幕。"
   return
  }
  let ext=url.pathExtension.lowercased()
  guard ["srt","vtt","ass","ssa"].contains(ext) else {
   aiOnlySubtitleImportStatus="请选择 SRT、VTT、ASS 或 SSA 完整字幕。"
   return
  }
  aiOnlySubtitleImportStatus="正在读取供 AI 分析的完整字幕…"
  do {
   let document=try await Task.detached(priority:.userInitiated) {() throws->SubtitleDocument in
    let access=url.startAccessingSecurityScopedResource()
    defer {if access {url.stopAccessingSecurityScopedResource()}}
    let handle=try FileHandle(forReadingFrom:url)
    defer {try? handle.close()}
    let bytes=try handle.read(upToCount:SubtitleParser.maxBytes+1) ?? Data()
    return try SubtitleParser.parse(bytes,extension:ext)
   }.value
   guard plotDisplayPosition()?.key==key else {
    aiOnlySubtitleImportStatus="导入期间已切换影片，请重新选择当前影片的字幕。"
    return
   }
   aiOnlySubtitle=(film:key,document:document)
   aiOnlySubtitleOrigin="素材专用备用字幕"
   filmMaterials.invalidateSubtitleSelection()
   aiOnlySubtitleImportStatus="已选用 \(document.cues.count) 条完整备用字幕作为 AI 素材来源；播放字幕保持不变，不自动调用 AI。"
   // V2 import is data-only. Legacy analysis requires its explicit Continue action.
  } catch {
   aiOnlySubtitleImportStatus=(error as? SubtitleParseError)==(.size) ? "字幕超过 5MB，请换用较小的完整字幕文件。" : "完整字幕读取失败；请确认文件格式、编码及文件访问权限。"
  }
 }
 /// Read a signed subtitle sibling of the current router USB movie for AI materials only.
 func importRouterFullFilmSubtitleForAI(_ option:RouterUSBSubtitleOption,movie:URL) async {
  guard let key=plotDisplayPosition()?.key,bankMovieURL==movie else {
   aiOnlySubtitleImportStatus="影片已切换，请重新选择当前 U 盘电影的字幕。";return
  }
  aiOnlySubtitleImportStatus="正在从路由器 U 盘读取 \(option.name)…"
  do {
   let document=try await RouterUSBSubtitleCatalog.read(option,for:movie)
   guard plotDisplayPosition()?.key==key,bankMovieURL==movie else {
    aiOnlySubtitleImportStatus="读取期间影片已切换，已忽略旧字幕。";return
   }
   aiOnlySubtitle=(film:key,document:document)
   aiOnlySubtitleOrigin="路由器 U 盘外挂字幕（素材专用）"
   filmMaterials.invalidateSubtitleSelection()
   aiOnlySubtitleImportStatus="已从 U 盘选用 \(option.name)，共 \(document.cues.count) 条；播放字幕不变。"
  } catch {
   aiOnlySubtitleImportStatus="U 盘完整字幕读取失败："+error.localizedDescription
  }
 }
 func clearFullFilmSubtitleForAI() {
  guard hasMaterialOnlySubtitle else{return}
  aiOnlySubtitle=nil
  aiOnlySubtitleOrigin="素材专用备用字幕"
  filmMaterials.invalidateSubtitleSelection()
  aiOnlySubtitleImportStatus="已取消素材专用备用字幕，下次导出按当前播放字幕选择读取。"
 }
 private func recoverCurrentNativeSubtitleWindow(item:AVPlayerItem,position:Double) {
  guard nativeWindowRecoveryTask==nil,!externalSubtitles.enabled,selectedSubtitleIndex>=0,
   let source=(item.asset as? AVURLAsset)?.url,NativeSubtitleIndexReader.isDemandDrivenLocal(master:source) else{return}
  let track=selectedSubtitleIndex,generation=mediaLoadGeneration
  nativeWindowRecoverySerial+=1;let ticket=nativeWindowRecoverySerial
  nativeWindowRecoveryTask=Task { [weak self,weak item] in
   guard let self else{return}
   defer{if self.nativeWindowRecoverySerial==ticket {self.nativeWindowRecoveryTask=nil}}
   guard let item else{return}
   let document=await NativeSubtitleIndexReader.fetchCurrentWindow(master:source,track:track,at:position)
   guard !Task.isCancelled,generation==self.mediaLoadGeneration,self.adapter.player.currentItem === item,
    self.selectedSubtitleIndex==track,!self.externalSubtitles.enabled,let document else{return}
   self.externalSubtitles.recoverCurrentNativeWindow(document,for:item)
  }
 }
 private func prepareNativeSubtitleIndex(item:AVPlayerItem,track:Int) {
  guard track>=0,!externalSubtitles.enabled,let source=(item.asset as? AVURLAsset)?.url,
        source.pathExtension.lowercased()=="m3u8" else{return}
  if mkvRemux.pgsOCRRendition && !externalSubtitles.convertPGSForAI {
   externalSubtitles.nativeIndexDisabledForAI();return
  }
  // PrismCore publishes a complete planned playlist before its subtitle files
  // exist. Probing every VTT ahead can wait minutes or re-anchor its producer,
  // competing with the actual movie. Analyze observed legible cues instead.
  if NativeSubtitleIndexReader.isDemandDrivenLocal(master:source) {
   nativeWindowRecoverySerial+=1;nativeWindowRecoveryTask?.cancel();nativeWindowRecoveryTask=nil
  nativeIndexTask?.cancel();nativeIndexTask=nil;nativeIndexRequestKey=""
   externalSubtitles.nativeIndexStreamingStarted();return
  }
  if externalSubtitles.nativeIndexedTrack==track {return}
  let key="\(mediaLoadGeneration):\(track):\(source.absoluteString)"
  guard key != nativeIndexRequestKey else{return}
  nativeIndexTask?.cancel();nativeIndexRequestKey=key
  externalSubtitles.nativeIndexStarted()
  nativeIndexTask=Task { [weak self,weak item] in
   let result=await NativeSubtitleIndexReader.fetch(master:source,track:track)
   guard !Task.isCancelled,let self,let item,self.nativeIndexRequestKey==key,
     self.adapter.player.currentItem === item,
     !self.externalSubtitles.enabled,self.selectedSubtitleIndex==track else{return}
   if let result {
    self.externalSubtitles.installNativeIndex(result,track:track,
     forAIOnly:self.mkvRemux.pgsOCRRendition)
    await self.plotIntelligence.collect()
   } else {self.externalSubtitles.nativeIndexUnavailable()}
  }
 }
 /// Experimental local-file PGS path. Does not read network movies twice or
 /// change any source/room/PrismCore playback state; uses original palette.
 private func prepareOriginalPGSBitmap(item:AVPlayerItem,track:Int) {
  originalPGSDecodeTask?.cancel();originalPGSDecodeTask=nil
  guard track==0,!externalSubtitles.enabled,
        externalSubtitles.originalPGSBitmapEnabled,
        let streamIndex=mkvRemux.uniquePGSStreamIndex,
        let original=currentOriginalURL,original.isFileURL else{return}
  let generation=mediaLoadGeneration
  originalPGSDecodeTask=Task { [weak self,weak item] in
   let decoder=Task.detached(priority:.utility) {
    OriginalPGSFileExtractor.extract(url:original,streamIndex:streamIndex)
   }
   let events=await withTaskCancellationHandler(operation:{await decoder.value},onCancel:{decoder.cancel()})
   guard !Task.isCancelled,!events.isEmpty,let self,let item,
         generation==self.mediaLoadGeneration,
         self.adapter.player.currentItem === item,
         !self.externalSubtitles.enabled,
         self.externalSubtitles.originalPGSBitmapEnabled,
         self.selectedSubtitleIndex==track else{return}
   self.externalSubtitles.installOriginalPGS(events,track:track)
  }
 }
 // Keep an explicitly selected built-in subtitle track active across
 // decoder/HLS option resets. Normal dialogue gaps never trigger a reselect.
 private var lastNativeSubtitleRepairAt=0.0
 private func restoreSelectedNativeSubtitleIfNeeded() {
  guard !externalSubtitles.enabled,let requested=requestedSubtitleIndex,requested>=0,
   let item=adapter.player.currentItem,item.status == .readyToPlay,
   let group=subtitleGroup,group.options.indices.contains(requested) else {return}
  let expected=group.options[requested]
  guard item.currentMediaSelection.selectedMediaOption(in:group) !== expected else {return}
  let now=Date().timeIntervalSince1970
  guard now-lastNativeSubtitleRepairAt>=15 else{return}
  lastNativeSubtitleRepairAt=now
  item.select(expected,in:group)
  selectedSubtitleIndex=requested
  diagnostic("nativeSubtitleOptionRecovered")
 }
 func importSubtitle(_ url: URL) {
  Task {if await externalSubtitles.importFile(url) {enableExternalSubtitle();filmMaterials.invalidateSubtitleSelection()}}
 }
 func enableExternalSubtitle() {
  guard externalSubtitles.available else {return}
  nativeWindowRecoverySerial+=1;nativeWindowRecoveryTask?.cancel();nativeWindowRecoveryTask=nil
  nativeIndexTask?.cancel();nativeIndexTask=nil;nativeIndexRequestKey=""
  if let item=adapter.player.currentItem,let group=subtitleGroup {item.select(nil,in:group)}
  requestedSubtitleIndex = -2
  selectedSubtitleIndex = -2;externalSubtitles.enabled=true
 }
 func chooseSubtitle(_ index: Int) {
  requestedSubtitleIndex=index
  // Reselecting an already applied track must preserve its earlier cues.
  // A pending selection without a loaded group still needs to be applied later.
  if index==selectedSubtitleIndex && !externalSubtitles.enabled,
    let item=adapter.player.currentItem,let group=subtitleGroup {
   let active=item.currentMediaSelection.selectedMediaOption(in:group)
   if (index == -2 && active == nil) ||
      (index == -1 && active != nil) ||
      (index >= 0 && group.options.indices.contains(index) && active === group.options[index]) {return}
  }
  nativeWindowRecoverySerial+=1;nativeWindowRecoveryTask?.cancel();nativeWindowRecoveryTask=nil
  nativeIndexTask?.cancel();nativeIndexTask=nil;nativeIndexRequestKey=""
  filmMaterials.invalidateSubtitleSelection()
  externalSubtitles.nativeSelectionChanged(enabled:index != -2);externalSubtitles.enabled=false;selectedSubtitleIndex=index
  guard let item=adapter.player.currentItem,let group=subtitleGroup else {return}
  if index == -1 {item.selectMediaOptionAutomatically(in:group)}
  else if index == -2 {item.select(nil,in:group)}
  else {guard group.options.indices.contains(index) else {return};item.select(group.options[index],in:group)}
  selectedSubtitleIndex=index
  prepareCompleteFilmForAI()
  if index>=0 {
   prepareNativeSubtitleIndex(item:item,track:index)
   prepareOriginalPGSBitmap(item:item,track:index)
  }
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
    forgetRememberedMovie();releaseLocalFileAccess()
    credentials=next;credentialServer=base;roomID=nextRoom
    UserDefaults.standard.set(data,forKey:"credentials");UserDefaults.standard.set(base,forKey:"server");connect()
   } catch {requestStatus="房间请求失败：\(error.localizedDescription)"}
  }
 }
 func connect() {
  stopP2P()
  supportsInstantControls=false;localVideoTest=false;localPlayIntent=false;queuedOperations=[];inFlight=nil;inFlightStartedAt=nil;operationRetry=0;mediaLoadGeneration += 1;if adapter.player.currentItem==nil {loadedURL=""}
  guard foreground,let token=credentials?["token"] as? String else {return}
  plotIntelligence.preserveCurrentFilmEvidence()
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
  setSpeedHold(false)
  voice.cancel(message:"连接中断，当前录音已取消，未发送")
   plotIntelligence.preserveCurrentFilmEvidence()
  // Invalidate both send and receive callbacks before scheduling one retry.
  generation += 1;let next=generation;socket?.cancel(with:.goingAway,reason:nil);socket=nil
  stopP2P();connected=false;engine.resetSession();playbackRecovery.reset();setPlaybackRecoveryVisible(false);attempt += 1
  disconnectCount += 1;lastDisconnectReason=reason
  inFlight=nil;inFlightStartedAt=nil;queuedOperations=[]
  clearOptimisticPlayback();lastStepTarget=nil
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
  if type=="WELCOME" {p2pSupported=(obj["p2pSignalingVersion"] as? Int ?? 0)>=1;supportsInstantControls=(obj["instantControlVersion"] as? Int ?? 0)>=1;connected=true;attempt=0;sequence=(obj["lastSequence"] as? NSNumber)?.int64Value ?? 0;lastStepTarget=nil;clearOptimisticPlayback();pingBurst()}
  if let raw=obj["room"] as? [String:Any],let data=try? JSONSerialization.data(withJSONObject:raw),let room=try? JSONDecoder().decode(Room.self,from:data) {
   if outboxRoom != room.roomId {outbox=[:];outboxRoom=room.roomId}
   if !optimisticRoomID.isEmpty && optimisticRoomID != room.roomId {clearOptimisticPlayback()}
   if (room.roomId != engine.room?.roomId || room.version >= (engine.room?.version ?? 0)),
      engine.room.map(RoomPresentationState.init) != RoomPresentationState(room) {objectWillChange.send()}
   let prior=engine.room
   if (prior==nil || prior?.roomId != room.roomId || room.version >= (prior?.version ?? 0)),
      prior != nil,(prior?.roomId != room.roomId || prior?.mediaUrl != room.mediaUrl),
      (localFileURL != nil || restoreMovieTask != nil),
      localSourceRoomID != room.roomId || localSourceRoomURL != room.mediaUrl {
    // A real room/source switch invalidates the old association. A host's
    // acknowledged reference equals localSourceRoomURL and is retained.
    let expected=rememberedMovie?.context
    if localFileURL != nil || expected?.roomID != room.roomId || expected?.mediaID != room.mediaUrl {forgetRememberedMovie();releaseLocalFileAccess()}
   }
   engine.receive(room);isHost=room.hostId == (credentials?["userId"] as? String);if isRoomHost != isHost {isRoomHost=isHost}
   if p2pFastUntil>0 && (room.roomId != p2pRoomID || room.version>p2pFastVersion) {p2pFastUntil=0}
   p2pGate.serverState(version:room.version)
   if plotPollWaiting {clearOptimisticPlayback()}
   if usingDifferentQuality,variantReferenceDuration<=0,let duration=room.duration,duration>0 {variantReferenceDuration=duration}
   chat.reset(room.roomId);let nextTitle=room.title?.isEmpty == false ? room.title! : "一起看电影";if roomTitle != nextTitle {roomTitle=nextTitle};let nextWait=room.waitForPeer ?? false;if waitForPeer != nextWait {waitForPeer=nextWait}
   let reasons=["buffering":"等待对方缓冲","disconnected":"等待对方重新连接","ended":"播放完毕，点播放可重播","source":"等待双方授权并匹配同一百度影片","server_restart":"同步服务器已恢复，影片保持暂停；点播放继续"]
   let nextNotice=reasons[room.pauseReason ?? ""] ?? "";if roomNotice != nextNotice {roomNotice=nextNotice}
   if let rawMembers=obj["members"],let data=try? JSONSerialization.data(withJSONObject:rawMembers),let roster=try? JSONDecoder().decode([RoomMember].self,from:data) {applyMembers(roster)}
   let restoring=(type=="WELCOME" && pendingLocalFile==nil && localFileURL==nil) ? restoreRememberedMovie(for:room) : false
   if restoring {loadedURL=room.mediaUrl}
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
  if type=="P2P_SIGNAL" {receiveP2PSignal(obj);return}
  if type=="CONTROL_REQUEST" {pending=obj["data"] as? [String:Any]}
  if type=="PRESENCE",let raw=obj["members"],let data=try? JSONSerialization.data(withJSONObject:raw),let roster=try? JSONDecoder().decode([RoomMember].self,from:data) {applyMembers(roster)}
  if type=="WELCOME" {
   questionBankRuntime.reconnected()
   restorePendingRoomMedia()
   if let list=obj["messages"] as? [[String:Any]] {for message in list {acceptChat(message)}}
   send(["type":"PROFILE_UPDATE","data":["name":nickname,"timelineOffset":Double(offsetSeconds).map {$0*1000} ?? 0]])
   for message in outbox.values {send(message)}
   if let file=pendingLocalFile {pendingLocalFile=nil;useLocalFile(file)}
  }
  if type=="WELCOME" {supportsBlockingPolls=(obj["plotPollCapabilities"] as? [String:Any])?["blocking"] as? Bool == true}
  if type=="PLOT_POLL_STATE" || obj.keys.contains("poll") {
   let incoming=obj["poll"] as? [String:Any]
   // A blocking question must always release the active 2x lease, even if
   // the user is still pressing the fullscreen gesture surface.
   if incoming?["waitingForAnswers"] as? Bool == true && speedHoldID != nil {setSpeedHold(false)}
   if !PlotPollPresentation.same(plotPoll,incoming) {plotPoll=incoming}
   questionBankRuntime.observePoll(incoming)
   // Capture an answered prediction only AFTER the server has revealed both
   // votes. Its correct outcome is deliberately unknown until future scenes
   // have actually played. Replay of WELCOME/STATE cannot duplicate a review.
   if questionBankRuntime.active == nil,isHost,let poll=incoming,poll["revealed"] as? Bool == true,
      poll["questionType"] as? String == "prediction",
      let id=poll["id"] as? String,!reviewedPlotPollIDs.contains(id),
      let room=engine.room,let question=poll["question"] as? String,
      let options=poll["options"] as? [String],let votes=poll["answers"] as? [String:String] {
    let millis=(poll["positionMs"] as? NSNumber)?.doubleValue ?? -1
    let review=PlotPendingReview(id:id,roomId:room.roomId,mediaId:room.mediaUrl,
      at:max(0,millis/1000),question:question,choices:options,answers:votes)
    if millis>=0 && review.isReady {
     pendingPlotPredictionReview=review
     reviewedPlotPollIDs.insert(id)
    }
   }
  }
  if type=="CHAT_MESSAGE",let message=obj["message"] as? [String:Any] {acceptChat(message,live:true)}
  if type=="REACTION",let emoji=obj["emoji"] as? String {chat.reaction(emoji,now:clock.localNow())}
  if type=="CHAT_TYPING",obj["userId"] as? String != credentials?["userId"] as? String {chat.typing(obj["name"] as? String ?? "好友",now:clock.localNow())}
  if type=="ROOM_CLOSE" || type=="ROOM_LEAVE" {clearRoom();return}
  if obj["ackUserId"] as? String == credentials?["userId"] as? String,(obj["ackSequence"] as? NSNumber)?.int64Value == inFlightSequence,inFlight != nil {
   if inFlight?["type"] as? String=="ROOM_MEDIA",let change=pendingRoomMedia,let room=engine.room,change.matches(room) {finishRoomMedia("房间影片已设置；双方正在加载新影片。")}
   inFlight=nil;inFlightStartedAt=nil;operationRetry=0
   if !holdingLocalPause && !queuedOperations.contains(where:{["PLAY","PAUSE","SEEK","INSTANT_CONTROL"].contains($0["type"] as? String ?? "")}) {clearOptimisticPlayback()}
   flushOperations()
  }
  if type=="ERROR" {
   let code=obj["error"] as? String ?? "ERROR"
   if code=="EXPIRED" {clearRoom();requestStatus="房间已过期";return}
   if code=="STALE_VERSION",let operation=inFlight,operationRetry<1 {operationRetry += 1;inFlight=nil;inFlightStartedAt=nil;queuedOperations.insert(operation,at:0);flushOperations()}
   else {inFlight=nil;inFlightStartedAt=nil;queuedOperations=[];clearOptimisticPlayback();requestStatus=errorText(code);if pendingRoomMedia != nil {finishRoomMedia(errorText(code))}}
  }
 }
 func retryCompatibility() {
  guard let url=currentOriginalURL else {requestStatus="请先选择并加载影片";return}
  loadMedia(url,forceRemux:true)
 }
 #if DEBUG
 func installTrackPlaybackFixture() throws {
  localVideoTest=true;loadMedia(try TrackUITestFixture.url())
  Task {
   for _ in 0..<100 {
    if !subtitleLabels.isEmpty {
     if selectedSubtitleIndex != 0 {chooseSubtitle(0)}
     for _ in 0..<100 {
      if !externalSubtitles.text.isEmpty && adapter.position>150 {adapter.pause();return}
      try? await Task.sleep(nanoseconds:100_000_000)
     }
     adapter.pause();return
    }
    try? await Task.sleep(nanoseconds:100_000_000)
   }
  }
 }
 #endif
 func checkLocalVideo() {
  generation += 1;socket?.cancel(with:.goingAway,reason:nil);connected=false;clock.reset();localVideoTest=true;localPlayIntent=true;recoveryRebuilds=0
  guard let url=HTTPSource().resolve(mediaURL) else {status="无效测试视频 URL";return}
  adapter.setPlaybackSpeed(1);loadedURL=mediaURL;loadMedia(url)
  status="本机视频验证：可测试 PLAY / PAUSE / SEEK；尚未加入同步房间"
 }
 // Rapid ±10s taps accumulate against the latest requested target,
 // even when the decoder has not yet reached that position.
 func skipBy(_ milliseconds:Double) {
  guard milliseconds.isFinite else {return}
  let now=clock.localNow()
  let baseline:Double
  if let previous=lastStepTarget,now-lastStepTime<1300 {
   baseline=previous
  } else {baseline=adapter.position-engine.timelineOffset}
  let desired=max(0,baseline+milliseconds)
  let end=adapter.duration
  let bounded=end.isFinite && end>0 ? min(desired,max(0,end-engine.timelineOffset)) : desired
  lastStepTarget=bounded;lastStepTime=now
  control("SEEK",position:bounded)
 }
 func control(_ type: String,position: Double=0) {
  if type == "SEEK" || type == "REPLAY" {bankNativePlaybackEnded=false;questionBankRuntime.playbackJumped()}
  if plotPollWaiting && type != "PAUSE" {requestStatus="请双方先回答剧情问题，再继续播放";feedback.showPlaybackAction(requestStatus);return}
  guard position.isFinite else {return}
  cancelRecoveryPreroll()
  if type != "SEEK" {lastStepTarget=nil}
  let action=["PLAY":"播放","PAUSE":"暂停","SEEK":"跳转"][type] ?? "操作"
  feedback.showPlaybackAction(localVideoTest ? "正在\(action)…" : (isHost ? "正在同步\(action)…" : "正在请求房主\(action)…"))
  // A manual PLAY during a known stall must rebuild the wedged local HLS
  // session instead of resetting the recovery clock or sending another
  // room playback command. Preserve the signed source and current position.
  if type == "PLAY" && playbackNeedsRecovery,let original=currentOriginalURL {
   recoveryResumePosition=localVideoTest ? adapter.position : (engine.target()?.0 ?? adapter.position)
   recoveryRebuilds=0
   requestStatus="正在恢复停止读取的影片…"
   loadMedia(original)
   return
  }
  if localVideoTest {
   if type == "PLAY" {localPlayIntent=true}
   else if type == "PAUSE" {localPlayIntent=false;recoveryRebuilds=0}
  }
  playbackRecovery.reset();setPlaybackRecoveryVisible(false)
  controlSettleUntil=clock.localNow()+2500
  if localVideoTest {
   switch type {case "PLAY":adapter.play();case "PAUSE":adapter.pause();case "SEEK":adapter.seekTo(position);default:break};return
  }
  guard connected && clock.ready else {requestStatus="尚未连接或正在校准时钟";feedback.showPlaybackAction(requestStatus);return}
  if supportsInstantControls,["PLAY","PAUSE","SEEK","REPLAY"].contains(type),let room=engine.room {
   guard variantDurationCheck == .compatible else {requestStatus="请先确认影片版本";return}
   if type=="PLAY",adapter.player.currentItem?.status == .failed,let original=currentOriginalURL {loadMedia(original);return}
   queuedOperations.removeAll {($0["type"] as? String)=="INSTANT_CONTROL"}
   let playhead=max(0,adapter.position-engine.timelineOffset)
   let atEnd=adapter.duration>0 && adapter.position>=adapter.duration-150
   let kind=type=="PLAY" && atEnd ? "REPLAY" : type
   let canonical=(kind=="SEEK" ? max(0,position) : kind=="REPLAY" ? 0 : playhead)
   let operation:[String:Any]=["type":"INSTANT_CONTROL","data":["type":kind,"position":canonical,"commandTime":clock.serverNow(),"mediaUrl":room.mediaUrl]]
   queuedOperations.append(operation)
   optimisticRoomID=room.roomId;optimisticUntil=clock.localNow()+8000
   switch kind {
   case "PLAY":optimisticPlaying=true;adapter.play()
   case "PAUSE":optimisticPlaying=false;adapter.pause()
   case "SEEK":adapter.seekTo(canonical+engine.timelineOffset)
   case "REPLAY":optimisticPlaying=true;adapter.seekTo(engine.timelineOffset);adapter.play()
   default:break
   }
   feedback.showPlaybackAction(action)
   flushOperations();return
  }
  if type == "PLAY",engine.target()?.1 == "playing",adapter.ready,
     inFlight == nil,queuedOperations.isEmpty,!holdingLocalPause {
   playbackRecovery.reset();adapter.play()
   setPlaybackRecoveryVisible(false);feedback.showPlaybackAction("已尝试恢复当前影片播放")
   return
  }
  // A rapid second tap before the first PLAY acknowledgement must not queue
  // another start (or run another media preparation while one is in flight).
  if type == "PLAY" && (inFlight?["type"] as? String == "PLAY" ||
      queuedOperations.contains(where:{($0["type"] as? String)=="PLAY"})) {
   feedback.showPlaybackAction("播放指令处理中")
   return
  }
  // Failed AVPlayerItem instances cannot safely accept a new play command.
  // Rebuild the *same* source while keeping subtitle and film identity.
  if type == "PLAY",let item=adapter.player.currentItem,item.status == .failed {
   guard let original=currentOriginalURL else {requestStatus="当前影片加载失败，请检查片源";return}
   requestStatus="播放器需要恢复，正在重新准备当前影片"
   loadMedia(original)
   return
  }
  var operation: [String:Any]=["type":type,"position":max(0,position)]
  if isHost {
   // Keep only the last pending jump while preserving pause/play and media actions.
   if type=="SEEK" {queuedOperations.removeAll {($0["type"] as? String)=="SEEK"}}
   guard queuedOperations.count<8 else {requestStatus="请等待前面的操作完成";feedback.showPlaybackAction(requestStatus);return}
   queuedOperations.append(operation)
   applyOptimisticPlayback(type,position:operation["position"] as? Double ?? 0)
   flushOperations()
  }
  else {sequence += 1;operation["sequence"]=sequence;send(["type":"CONTROL_REQUEST","sequence":sequence,"data":operation]);requestStatus="已向房主发送请求"}

 }
 func approve() {guard let p=pending else {return};control(p["type"] as? String ?? "",position:p["position"] as? Double ?? 0);pending=nil}
 func disconnectForTest() {
  generation += 1;socket?.cancel(with:.goingAway,reason:nil);connected=false;adapter.pause();let g=generation
  Task {try? await Task.sleep(nanoseconds:3_000_000_000);if g==generation {connect()} }
 }
 private func cancelRecoveryPreroll() {
  guard prerolling else {return}
  prerollGeneration += 1;prerolling=false;prerollPrepared=false
  adapter.player.cancelPendingPrerolls()
 }
 private func setPlaybackRecoveryVisible(_ value:Bool) {
  if playbackNeedsRecovery != value {playbackNeedsRecovery=value}
 }
 private func monitorLocalPlaybackRecovery() {
  let now=clock.localNow()
  let shouldPlay=foreground && localPlayIntent && currentOriginalURL != nil &&
   adapter.player.currentItem?.status == .readyToPlay && !adapter.isSeeking
  let action=playbackRecovery.observe(now:now,position:adapter.position,shouldPlay:shouldPlay)
  switch action {
  case .none:
   setPlaybackRecoveryVisible(shouldPlay && now-(playbackRecovery.stalledSince ?? now)>=5000)
  case .wake:
   setPlaybackRecoveryVisible(true)
   adapter.play()
   diagnostic("localResumeAfterStall")
  case .rebuild:
   guard let original=currentOriginalURL else{return}
   guard recoveryRebuilds < 2 else {
    requestStatus="本机播放连续恢复失败，请重新打开影片"
    return
   }
   recoveryResumePosition=adapter.position
   recoveryRebuilds += 1
   diagnostic("localRebuildAfterStall")
   loadMedia(original)
  }
 }
 private func monitorPlaybackRecovery() {
  let current=engine.room
  let now=clock.localNow()
  let shouldPlay=foreground && connected && !plotPollWaiting &&
   now>=controlSettleUntil &&
   variantDurationCheck == .compatible && current?.target(clock.serverNow()).1 == "playing" &&
   adapter.player.currentItem != nil && adapter.player.currentItem?.status == .readyToPlay &&
   !localVideoTest && currentOriginalURL != nil &&
   inFlight == nil && queuedOperations.isEmpty
  let action=playbackRecovery.observe(now:now,position:adapter.position,shouldPlay:shouldPlay)
  switch action {
  case .none:break
  case .wake:
   setPlaybackRecoveryVisible(true)
   // Re-arm AVPlayer's internal play intent without replacing the film.
   adapter.pause();adapter.setPlaybackSpeed(current?.playbackRate == 2 ? 2 : 1);adapter.play()
   diagnostic("resumeAfterStall")
  case .rebuild:
   guard let original=currentOriginalURL else {return}
   guard recoveryRebuilds < 2 else {requestStatus="自动恢复未成功，请检查原片源或网络";return}
   setPlaybackRecoveryVisible(true)
   recoveryResumePosition=engine.target()?.0 ?? adapter.position
   recoveryRebuilds += 1
   diagnostic("rebuildStalledPlayerItem")
   loadMedia(original)
  }
  if action == .none {
   setPlaybackRecoveryVisible(shouldPlay && now-(playbackRecovery.stalledSince ?? now)>=5000)
  }
  if current?.target(clock.serverNow()).1 == "paused" {recoveryRebuilds=0}
 }
 private func reviewPlotPredictionIfReady() {
  guard questionBankRuntime.active == nil else{return}
  guard connected,isHost,plotPredictionReviewTask == nil,
   let review=pendingPlotPredictionReview,let room=engine.room else{return}
  guard room.roomId==review.roomId,room.mediaUrl==review.mediaId else {
   pendingPlotPredictionReview=nil;return
  }
  let position=adapter.position/1000
  if position>review.at+480 {pendingPlotPredictionReview=nil;return}
  guard review.canReview(position:position),PlotLocalAI.available else{return}
  let evidence=review.observed(externalSubtitles.observedPlotEvidence(),position:position)
  guard evidence.count>=3 else{return}
  pendingPlotPredictionReview=nil
  plotPredictionReviewTask=Task { [weak self] in
   let verdict=await PlotFutureJudge.evaluate(review,evidence:evidence)
   guard let self else{return}
   defer {self.plotPredictionReviewTask=nil}
   guard !Task.isCancelled,self.connected,self.isHost,
      self.engine.room?.roomId==review.roomId,self.engine.room?.mediaUrl==review.mediaId,
      self.adapter.position/1000>=review.at+180 else{return}
   // An unresolved outcome is never given a made-up "right answer".
   if let verdict {
    let message=PlotPredictionVerdict.message(verdict,review:review,members:self.members)
    guard message.utf8.count<=6000,message.count<=1000,self.outbox.count<20 else{return}
    let id="plot-review:"+review.id
    let frame:[String:Any]=["type":"CHAT_MESSAGE","data":["text":message,"clientMessageId":id]]
    self.outbox[id]=frame;self.send(frame)
   }
  }
 }
 private func tick() {
  if localVideoTest {ticks += 1;monitorLocalPlaybackRecovery();if ticks%50 == 0 {inspectFormats();updateMediaInfo()};return}
  chat.tick(clock.localNow())
  if socket != nil {
   if let reason=RoomConnectionHealth.timeout(now:clock.localNow(),connected:connected,startedAt:connectionStartedAt,lastMessageAt:lastMessageAt,inFlightAt:inFlightStartedAt) {reconnect(generation,reason:reason);return}
  }
  guard connected else {return}
  if engine.target()?.1 == "playing" || adapter.isSeeking {cancelRecoveryPreroll()}
  if speedHoldID != nil,engine.target()?.1 == "paused" {setSpeedHold(false)}
  let error: Double?
  if variantDurationCheck == .compatible {
   if !plotPollWaiting,p2pFastUntil>clock.localNow(),let room=engine.room,room.roomId==p2pRoomID,room.version==p2pFastVersion {
    error=nil
   } else if let room=engine.room,optimisticRoomID==room.roomId,clock.localNow()<optimisticUntil,
      (inFlight != nil || !queuedOperations.isEmpty || holdingLocalPause) {
    // A pending host command must not be reverted by an outdated room snapshot.
    error=nil
    if holdingLocalPause {adapter.pause()}
   } else if speedHoldID != nil && speedHoldID != "local" && adapter.player.rate>0 && !plotPollWaiting {
    // Keep the local 2× rate while the server processes SPEED_HOLD.
    error=nil
   } else if speedHoldReleaseUntil>clock.localNow() && adapter.player.rate>0 && engine.room?.state=="playing" && !plotPollWaiting {
    error=nil
   } else {
    if optimisticPlaying != nil {clearOptimisticPlayback()}
    error=engine.tick()
   }
  } else {clearOptimisticPlayback();adapter.pause();error=nil}
  monitorPlaybackRecovery()
  if ticks%100 == 0 {reviewPlotPredictionIfReady()}
  ticks += 1
  if clock.ready {flushOperations()}
  if adapter.player.rate != lastLoggedSpeed {lastLoggedSpeed=adapter.player.rate;diagnostic("speedChanged")}
  if engine.resyncCount != lastLoggedResync {lastLoggedResync=engine.resyncCount;diagnostic("automaticResync")}
  if ticks%10 == 0 {
   tickFilmBank()
   send(["type":"SYNC"])
   let item=adapter.player.currentItem
   let sourceValid=BaiduMediaReference(value:engine.room?.mediaUrl ?? "")==nil || hasBaiduMatch
   let recovering=engine.room?.autoResume == true
   if recovering {if recoveryStartedAt==nil {recoveryStartedAt=clock.localNow()}} else {recoveryStartedAt=nil}
   let fallback=recovering && prerollPrepared && item?.isPlaybackLikelyToKeepUp == true && clock.localNow()-(recoveryStartedAt ?? clock.localNow())>=10000
   let bufferedAhead=adapter.bufferedAheadMs
   let readiness=PlaybackReadinessPolicy.evaluate(prepared:adapter.ready,waiting:adapter.buffering,playing:adapter.player.timeControlStatus == .playing,bufferEmpty:item?.isPlaybackBufferEmpty ?? true,bufferedMs:bufferedAhead,positionMs:adapter.position,durationMs:adapter.duration,recovering:recovering && !usingLocalFile,preparedFallback:fallback)
   let bufferReady=sourceValid && variantDurationCheck == .compatible && readiness.ready
   // A host's alternate encode must not redefine the canonical room duration,
   // otherwise a mismatched cut could pass its own check on the next snapshot.
   let reportedDuration=usingDifferentQuality && isHost ? (variantReferenceDuration>0 ? variantReferenceDuration+engine.timelineOffset : 0) : adapter.duration
   send(["type":"PLAYER_STATUS","data":["sourceId":hasBaiduMatch ? baiduSourceID : "","ready":bufferReady,"buffering":readiness.buffering,"position":max(0,adapter.position-engine.timelineOffset),"duration":reportedDuration]])
   let safePreroll=RecoveryBufferPolicy.canPreroll(prepared:adapter.ready,
    pausedIntent:engine.target()?.1 == "paused",
    nativePaused:adapter.player.timeControlStatus == .paused && adapter.player.rate == 0,
    controlPending:clock.localNow()<controlSettleUntil || inFlight != nil || !queuedOperations.isEmpty)
   if recovering && !usingLocalFile && !bufferReady && safePreroll && !prerolling && clock.localNow()-lastPrerollAt>=3000 {
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
   let telemetry: [String:Any]=["clientVersion":Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "unknown","timelineOffsetMs":engine.timelineOffset,"executeAtMs":engine.room?.executeAt ?? 0,"playbackRate":adapter.player.rate,"resyncCount":engine.resyncCount,"bufferedAheadMs":bufferedAhead,"recoveryReserveMs":12000,"positionMs":position,"expectedMs":expected,"errorMs":measuredError,"rttMs":clock.rtt,"version":engine.room?.version ?? 0,"ready":bufferReady,"itemReady":adapter.ready,"bufferEmpty":item?.isPlaybackBufferEmpty ?? true,"likelyToKeepUp":item?.isPlaybackLikelyToKeepUp ?? false,"prerollPrepared":prerollPrepared,"autoResume":recovering,"buffering":readiness.buffering,"waiting":adapter.buffering,"playing":adapter.player.timeControlStatus == .playing,"serverTimeMs":clock.ready ? clock.serverNow() as Any : NSNull()]
   var connectionTelemetry=telemetry;connectionTelemetry["disconnectCount"]=disconnectCount;connectionTelemetry["lastDisconnectReason"]=lastDisconnectReason;connectionTelemetry["ignoredFrames"]=ignoredFrames
   send(["type":"TELEMETRY","data":connectionTelemetry])
   status="0.5.6 \(isHost ? "HOST" : "GUEST") room=\(credentials?["roomId"] as? String ?? "") v=\(engine.room?.version ?? 0)\n位置 \(Int(adapter.position/1000))s 误差 \(error.map {String(Int($0))} ?? "n/a")ms RTT \(Int(clock.rtt))ms \(adapter.buffering ? "BUFFERING" : "")\n已缓存 \(Int(bufferedAhead/1000))s"
  }
  if ticks%50 == 0 {inspectFormats();updateMediaInfo()}
  if ticks%150 == 0 {pingBurst()}
 }
}

extension TestClient {
 private func applyMembers(_ value: [RoomMember]) {
  let next=value.sorted {$0.userId<$1.userId};if members != next {members=next}
  if let me=value.first(where:{$0.userId == credentials?["userId"] as? String}) {engine.timelineOffset=me.timelineOffset}
  refreshP2P()
 }
 private func acceptChat(_ raw: [String:Any],live: Bool=false) {
  guard let data=try? JSONSerialization.data(withJSONObject:raw),let message=try? JSONDecoder().decode(ChatMessage.self,from:data) else {return}
  outbox.removeValue(forKey:message.clientMessageId)
  if message.userId == credentials?["userId"] as? String {questionBankRuntime.acknowledgeReveal(message.clientMessageId)}
  // Private final recap segments are transported through the existing room
  // chat protocol, but shown only in the dedicated plot drawer. Do not flood
  // chat or fullscreen danmaku with partial correct answers.
  if message.clientMessageId.hasPrefix("bank-final:") {return}
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
 private func forgetRememberedMovie() {
  localSelectionGeneration+=1;restoreMovieTask?.cancel();restoreMovieTask=nil;saveMovieTask?.cancel();saveMovieTask=nil
  rememberedMovie=nil;localMoviePersistenceStatus=""
  do {try movieSelectionStore.clear()} catch {localMoviePersistenceStatus="清除影片关联失败，请检查本机存储。"}
 }
 private func rememberCurrentLocalMovie() {
  guard let url=localFileURL,!localSourceRoomID.isEmpty,!localSourceRoomURL.isEmpty else{return}
  let context=RoomMovieContext(server:credentialServer,roomID:localSourceRoomID,mediaID:localSourceRoomURL)
  let selection=localSelectionGeneration,documents=movieSelectionStore.documents
  let variant=variantRoomID==context.roomID && variantMediaURL==context.mediaID,duration=variantReferenceDuration
  saveMovieTask?.cancel();rememberedMovie=nil;try? movieSelectionStore.clear();localMoviePersistenceStatus="正在记住本机影片…"
  let worker=Task.detached(priority:.utility){try RoomMovieSelection.capture(url,context:context,documents:documents,confirmedVariant:variant,referenceDuration:duration)}
  saveMovieTask=worker
  Task {[weak self] in
   let result=await worker.result
   guard let self,selection==self.localSelectionGeneration,self.localFileURL==url,
         self.localSourceRoomID==context.roomID,self.localSourceRoomURL==context.mediaID else{return}
   self.saveMovieTask=nil
   switch result {
   case .success(let record):
    do {try self.movieSelectionStore.save(record);self.rememberedMovie=record;self.localMoviePersistenceStatus="已记住本机影片，重新打开 App 自动恢复。"}
    catch {self.localMoviePersistenceStatus="影片已选择，但保存关联失败，请检查可用空间。"}
   case .failure(let error):
    if !(error is CancellationError) {self.localMoviePersistenceStatus="影片可继续播放，但暂未保存重启授权："+error.localizedDescription}
   }
  }
 }
 @discardableResult private func restoreRememberedMovie(for room:Room)->Bool {
  guard let record=rememberedMovie else{return false}
  let context=RoomMovieContext(server:credentialServer,roomID:room.roomId,mediaID:room.mediaUrl)
  guard record.context==context else{forgetRememberedMovie();return false}
  if restoreMovieTask != nil {return true}
  let selection=localSelectionGeneration,documents=movieSelectionStore.documents
  localMoviePersistenceStatus="正在恢复上次本机影片…";requestStatus=localMoviePersistenceStatus
  let worker=Task.detached(priority:.utility){try record.resolve(documents:documents)}
  restoreMovieTask=worker
  Task {[weak self] in
   let result=await worker.result
   guard let self,selection==self.localSelectionGeneration else{return}
   self.restoreMovieTask=nil
   guard self.localFileURL==nil,self.pendingLocalFile==nil,let current=self.engine.room,
         RoomMovieContext(server:self.credentialServer,roomID:current.roomId,mediaID:current.mediaUrl)==context else{return}
   switch result {
   case .success(let file):
    self.localFileURL=file.url;self.localFileSecurityScoped=file.transferAccess();self.localFileName=file.url.lastPathComponent
    if let name=FilmSourceTitle.fromFileName(file.url.lastPathComponent) {self.movieTitle=name}
    self.localSourceRoomID=context.roomID;self.localSourceRoomURL=context.mediaID
    self.baiduPlaybackURL=nil;self.baiduFileName="";self.activeLocalSource="";self.localMediaURL=""
    self.baiduSourceID=BaiduMediaReference(value:context.mediaID)==nil ? "" : context.mediaID
    self.baiduSourceRoom=self.baiduSourceID.isEmpty ? "" : context.roomID
    self.variantRoomID=record.confirmedVariant ? context.roomID : "";self.variantMediaURL=record.confirmedVariant ? context.mediaID : ""
    let currentDuration=current.duration ?? 0
    self.variantReferenceDuration=record.confirmedVariant ? (currentDuration>0 ? currentDuration : record.referenceDuration) : 0
    do {try self.movieSelectionStore.save(file.refreshed);self.rememberedMovie=file.refreshed;self.localMoviePersistenceStatus="已自动恢复上次本机影片。"}
    catch {self.localMoviePersistenceStatus="影片已恢复，但更新文件授权失败，下次可能需要重新选择。"}
    self.loadedURL=context.mediaID;self.loadMedia(file.url);self.requestStatus="已恢复本机影片，按房间进度同步。"
   case .failure(let error):
    if !(error is CancellationError) {self.localMoviePersistenceStatus="本机影片恢复失败："+error.localizedDescription;self.requestStatus=self.localMoviePersistenceStatus}
   }
  }
  return true
 }
 private func releaseLocalFileAccess() {
  if localFileSecurityScoped,let url=localFileURL {url.stopAccessingSecurityScopedResource()}
  localFileSecurityScoped=false;localFileURL=nil;localFileName=""
 }
 private func errorText(_ code: String) -> String {
  let messages=["PLOT_ANSWER_REQUIRED":"请双方先回答剧情问题，再继续播放","STALE_VERSION":"房间状态刚发生变化，请再试一次","HOST_REQUIRED":"只有房主可以执行此操作","HOST_OFFLINE":"房主已离线","SEEK_AFTER_END":"跳转位置超出影片时长","ROOM_FULL":"房间已满","INVALID_SOURCE":"片源链接无效或包含账户凭据","SOURCE_NOT_READY":"等待两端匹配同一百度影片并准备好后再播放","RATE_LIMIT":"操作过于频繁，请稍后再试","EXPIRED":"房间已过期","INVALID_MESSAGE":"消息为空或过长"]
  return messages[code] ?? code
 }
 private func flushOperations() {
  guard connected,engine.room != nil,inFlight==nil,let first=queuedOperations.first,
        isHost || first["type"] as? String == "INSTANT_CONTROL" else {return}
  // Changing metadata uses the room snapshot/version, not a playback clock.
  guard clock.ready || ["ROOM_MEDIA","ROOM_SETTINGS"].contains(first["type"] as? String ?? "") else {return}
  let operation=queuedOperations.removeFirst();sequence += 1;inFlightSequence=sequence;inFlight=operation
  inFlightStartedAt=clock.localNow()
  var command=operation;command["sequence"]=sequence;command["baseVersion"]=engine.room?.version ?? 0
  send(command)
  sendP2PHint(command)
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
  forgetRememberedMovie();releaseLocalFileAccess();activeLocalSource=localMediaURL;localSourceRoomURL=roomURL;localSourceRoomID=engine.room?.roomId ?? ""
  if localMediaURL.isEmpty {movieTitle=roomTitle}
  else if let name=FilmSourceTitle.fromMediaURL(localMediaURL) {movieTitle=name}
  loadMedia(playbackSource(for:room))
  requestStatus=localMediaURL.isEmpty ? "恢复房间片源" : "本机片源已应用；链接未传给服务器或对方，请确认同一剪辑版本"
 }
 func beginLocalFileSelection(publishRoom: Bool=true) {
  localQualityCandidate=nil
  requestStatus="请选择已下载的本地影片。"
  localSelectionGeneration += 1;restoreMovieTask?.cancel();restoreMovieTask=nil;saveMovieTask?.cancel();saveMovieTask=nil;localMoviePersistenceStatus="";pendingLocalFile=nil
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
   guard selection==localSelectionGeneration,engine.room?.roomId==room.roomId,engine.room?.mediaUrl==room.mediaUrl else{return}
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
   if let name=FilmSourceTitle.fromFileName(url.lastPathComponent) {movieTitle=name}
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
   rememberCurrentLocalMovie()
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
 var cleanupSourceURL:URL? {usingLocalFile ? localFileURL : nil}
 func detachLocalFileForCleanup(_ expected:URL)->Bool {
  guard cleanupSourceURL==expected,currentOriginalURL==expected || currentOriginalURL==nil else{return false}
  forgetRememberedMovie()
  plotIntelligence.wholeFilm.cancel()
  voice.disable();setSpeedHold(false);clearOptimisticPlayback()
  plotIntelligence.preserveCurrentFilmEvidence();plotIntelligence.cancel()
  nativeWindowRecoverySerial+=1;nativeWindowRecoveryTask?.cancel();nativeWindowRecoveryTask=nil
  nativeIndexTask?.cancel();nativeIndexTask=nil;nativeIndexRequestKey=""
  originalPGSDecodeTask?.cancel();originalPGSDecodeTask=nil
  localSelectionGeneration+=1;pendingLocalFile=nil;localQualityCandidate=nil
  stopUnmatchedMedia();releaseLocalFileAccess()
  activeLocalSource="";localMediaURL="";localSourceRoomURL="";localSourceRoomID=""
  baiduSourceID="";baiduSourceRoom="";baiduPlaybackURL=nil;baiduFileName=""
  variantRoomID="";variantMediaURL="";variantReferenceDuration=0
  playbackRecovery.reset();setPlaybackRecoveryVisible(false)
  requestStatus="正在清理本地文件…"
  return true
 }
 #if DEBUG
 func installCleanupTestSource(_ url:URL) {
  localFileURL=url;localFileName=url.lastPathComponent
  localSourceRoomURL=engine.room?.mediaUrl ?? "";localSourceRoomID=engine.room?.roomId ?? ""
  loadMedia(url)
 }
 #endif
 func clearLocalFileSource() {
  forgetRememberedMovie()
  localQualityCandidate=nil;variantRoomID="";variantMediaURL=""
  localSelectionGeneration += 1;pendingLocalFile=nil
  guard let room=engine.room else {releaseLocalFileAccess();requestStatus="本地影片已清除";return}
  let wasMatched=BaiduMediaReference(value:room.mediaUrl) != nil
  releaseLocalFileAccess();activeLocalSource="";localMediaURL="";localSourceRoomURL="";localSourceRoomID=""
  movieTitle=roomTitle
  if wasMatched {
   baiduSourceID="";baiduSourceRoom="";stopUnmatchedMedia()
   requestStatus="本地影片已清除；当前房间仍需重新选择同一文件。"
  } else if let url=HTTPSource().resolve(room.mediaUrl) {
   loadMedia(url);requestStatus="本地影片已清除，已恢复房间片源。"
  }
 }
 private func stopUnmatchedMedia() {
  mediaLoadGeneration += 1;mkvRemux.stop();adapter.pause();adapter.resetPendingSeeks();adapter.player.replaceCurrentItem(with:nil);externalSubtitles.clear();visualSampler.clear();currentOriginalURL=nil
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
  forgetRememberedMovie();releaseLocalFileAccess();baiduSourceID=reference;baiduSourceRoom=room.roomId;baiduPlaybackURL=url;baiduFileName=file.name
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
   mediaLoadGeneration += 1;mkvRemux.stop();adapter.pause();adapter.resetPendingSeeks();adapter.player.replaceCurrentItem(with:nil);loadedURL=""
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
 func publishPlotPoll(_ question:PlotQuestion) {
  guard connected,isRoomHost,let room=engine.room else {requestStatus="只有已连接的房主能出题";return}
  if question.blocking && !supportsBlockingPolls {requestStatus="当前服务器尚未支持答题后继续播放";return}
  send(["type":"PLOT_POLL_CREATE","data":["question":question.text,"options":question.choices,"questionType":question.kind,"blocking":question.blocking,"positionMs":max(0,adapter.position-engine.timelineOffset)]])
 }
 func cancelPlotPoll() {guard connected,isRoomHost else {return};send(["type":"PLOT_POLL_CANCEL"])}
 func answerPlotPoll(_ text:String) {
  guard connected,let poll=plotPoll,let id=poll["id"] as? String,!plotPollSubmitted else {return}
  let answer=String(text.trimmingCharacters(in:.whitespacesAndNewlines).prefix(180))
  guard !answer.isEmpty else {return}
  send(["type":"PLOT_POLL_ANSWER","data":["id":id,"answer":answer]])
 }
 func sendChat() {
  let text=chatDraft.text.trimmingCharacters(in:.whitespacesAndNewlines)
  guard connected else {requestStatus="连接恢复后再发送消息";return}
  guard !text.isEmpty,text.unicodeScalars.count<=1000,text.utf8.count<=6000,outbox.count<20 else {requestStatus="消息为空或超过1000字";return}
  let id=UUID().uuidString;let message: [String:Any]=["type":"CHAT_MESSAGE","data":["text":text,"clientMessageId":id]];outbox[id]=message;send(message);chatDraft.text=""
 }
 var playbackVolume:Float {voiceDucker?.userVolume ?? adapter.player.volume}
 func setPlaybackVolume(_ value:Float) {voiceDucker?.setUserVolume(value)}
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
 func leaveRoom() {forgetRememberedMovie();voice.disable();guard connected else {clearRoom();return};send(["type":"ROOM_LEAVE"])}
 private func clearRoom() {
  stopP2P()
  forgetRememberedMovie()
  supportsBlockingPolls=false
  plotIntelligence.cancel()
  voice.disable()
  localQualityCandidate=nil;variantRoomID="";variantMediaURL=""
  if pendingRoomMedia != nil {finishRoomMedia("已离开房间，换片请求已取消。")}
  localSelectionGeneration += 1;pendingLocalFile=nil;localSelectionRoom="";localSelectionMedia=""
  externalSubtitles.clear()
  visualSampler.clear()
  releaseLocalFileAccess();mkvRemux.stop();baiduSourceID="";baiduSourceRoom="";baiduPlaybackURL=nil;baiduFileName="";activeLocalSource="";localMediaURL="";localSourceRoomURL="";localSourceRoomID=""
  mediaLoadGeneration += 1;generation += 1;connected=false;clearOptimisticPlayback();socket?.cancel(with:.goingAway,reason:nil);socket=nil;credentials=nil;UserDefaults.standard.removeObject(forKey:"credentials")
  plotPoll=nil
  outbox=[:];outboxRoom="";queuedOperations=[];inFlight=nil;inFlightStartedAt=nil;isHost=false;isRoomHost=false;engine.resetSession();adapter.resetPendingSeeks();adapter.player.replaceCurrentItem(with:nil);loadedURL="";roomID="";members=[];chat.reset("");roomNotice="";roomTitle="一起看电影";status="已离开房间";requestStatus=""
 }
 private func applyOptimisticPlayback(_ type:String,position:Double) {
  guard isHost,connected,engine.room != nil,variantDurationCheck == .compatible,
        adapter.player.currentItem?.status == .readyToPlay,!plotPollWaiting else {return}
  // The server schedules room PLAY 750 ms ahead so both devices start together.
  // Starting the host AVPlayer now plays ~750 ms ahead, then the next room
  // snapshot forces correction (and can stall decoding at the 1 s mark).
  // Preserve the immediate UI acknowledgement, but let the synced room clock
  // start the video once; never optimistically start or rewind a PLAY.
  if type == "PLAY" {clearOptimisticPlayback();return}
  optimisticRoomID=engine.room?.roomId ?? ""
  optimisticUntil=clock.localNow()+1800
  switch type {
  case "PAUSE":optimisticPlaying=false;adapter.pause()
  case "SEEK":adapter.seekTo(position+engine.timelineOffset)
  default:break
  }
 }
 private func clearOptimisticPlayback() {
  optimisticUntil=0;optimisticRoomID=""
  if optimisticPlaying != nil {optimisticPlaying=nil}
 }
 func setSpeedHold(_ active:Bool) {
  if active && plotPollWaiting {feedback.showPlaybackAction("请先回答剧情问题");return}
  if active {
   guard speedHoldID==nil,requestedPlaying else {return}
   if localVideoTest {adapter.setPlaybackSpeed(2);speedHoldID="local";return}
   guard connected else {return}
   speedHoldID=UUID().uuidString
   speedHoldReleaseUntil=0
   adapter.setPlaybackSpeed(2)
   sendSpeedHold()
   let timer=Timer(timeInterval:0.5,repeats:true){[weak self] _ in Task {@MainActor in self?.sendSpeedHold()}}
   speedHoldTimer=timer;RunLoop.main.add(timer,forMode:.common)
  } else {
   speedHoldTimer?.invalidate();speedHoldTimer=nil
   guard let id=speedHoldID else {return};speedHoldID=nil
   if id=="local" {adapter.setPlaybackSpeed(1)}
   else {adapter.setPlaybackSpeed(1);speedHoldReleaseUntil=clock.localNow()+600;send(["type":"SPEED_HOLD","data":["active":false,"holdId":id]])}
  }
 }
 private func sendSpeedHold() {guard connected,let id=speedHoldID else {setSpeedHold(false);return};send(["type":"SPEED_HOLD","data":["active":true,"holdId":id]])}
 func handleBackground() {stopP2P();plotPredictionReviewTask?.cancel();plotPredictionReviewTask=nil;plotIntelligence.preserveCurrentFilmEvidence();visualSampler.setForeground(false);setSpeedHold(false);clearOptimisticPlayback();voice.disable();mkvRemux.stop();mediaLoadGeneration += 1;loadedURL="";adapter.player.cancelPendingPrerolls();prerolling=false;foreground=false;chat.visible=false;generation += 1;connected=false;socket?.cancel(with:.goingAway,reason:nil);socket=nil;queuedOperations=[];inFlight=nil;inFlightStartedAt=nil;engine.resetSession();adapter.resetPendingSeeks();adapter.player.replaceCurrentItem(with:nil);status="后台暂停，返回后自动同步";if pendingRoomMedia != nil {mediaFeedback.requestStatus="换片请求已保留，返回房间后继续确认…"}}
 func handleForeground() {guard !foreground else {return};foreground=true;chat.visible=true;visualSampler.setForeground(true);if credentials != nil {connect()}}
 var durationWarning: String {
  let durations=members.filter {$0.duration>0}.map {$0.duration-$0.timelineOffset}
  guard durations.count==2,abs(durations[0]-durations[1])>5000 else {return ""}
  return "双方影片时长不同，请确认剪辑一致；时间偏移只能校准片头差异。"
 }
}


extension TestClient {
 private func p2pKnownPeerOnline() -> Bool {
  guard !p2pPeerID.isEmpty,let room=engine.room,room.roomId==p2pRoomID else{return false}
  return members.contains {$0.userId == p2pPeerID && $0.online}
 }
 private func stopP2P() {
  p2pTransport.close()
  p2pGate.reset();p2pSupported=false;p2pPeerID="";p2pRoomID=""
  p2pEstablished=false;p2pFastUntil=0;p2pFastVersion=0
  p2pLastOfferAt=0;p2pStatus="Muse 房间同步"
 }
 private func refreshP2P() {
  guard connected,foreground,p2pSupported,
        let room=engine.room,let me=credentials?["userId"] as? String,!me.isEmpty else{return}
  let peers=members.filter {$0.userId != me && $0.online}
  guard peers.count==1,members.count==2 else {
   if !p2pPeerID.isEmpty {
    p2pTransport.close();p2pGate.reset();p2pPeerID=""
    p2pEstablished=false;p2pStatus="Muse 备用"
   }
   return
  }
  let remote=peers[0].userId
  if p2pPeerID != remote || p2pRoomID != room.roomId {
   p2pPeerID=remote;p2pRoomID=room.roomId;p2pEstablished=false
   p2pGate.attach(roomID:room.roomId,hostUserID:room.hostId,localUserID:me,serverVersion:room.version)
   p2pLastOfferAt=clock.localNow()
   p2pTransport.start(host:room.hostId==me,peerUserID:remote)
  } else {
   p2pGate.serverState(version:room.version)
   if room.hostId==me && !p2pEstablished && clock.localNow()-p2pLastOfferAt>15_000 {
    p2pLastOfferAt=clock.localNow()
    p2pTransport.start(host:true,peerUserID:remote)
   }
  }
 }
 private func receiveP2PSignal(_ message:[String:Any]) {
  guard connected,p2pSupported,let source=message["fromUserId"] as? String,
        let data=message["data"] as? [String:Any],
        let kind=data["kind"] as? String,
        let payload=data["payload"] as? [String:Any] else{return}
  refreshP2P()
  guard source==p2pPeerID,p2pKnownPeerOnline() else{return}
  p2pTransport.receiveSignal(kind:kind,payload:payload)
 }
 private func sendP2PHint(_ command:[String:Any]) {
  guard p2pEstablished,p2pKnownPeerOnline(),let room=engine.room,
        room.hostId == credentials?["userId"] as? String,
        !plotPollWaiting,variantDurationCheck == .compatible else{return}
  let outer=command["type"] as? String ?? ""
  let details=outer=="INSTANT_CONTROL" ? command["data"] as? [String:Any] : command
  guard let fields=details,let name=fields["type"] as? String,
        ["PLAY","PAUSE","SEEK"].contains(name),
        let seq=(command["sequence"] as? NSNumber)?.int64Value else{return}
  let position=(fields["position"] as? NSNumber)?.doubleValue ?? 0
  let payload:[String:Any]=[
   "type":"CONTROL_HINT","roomID":room.roomId,
   "senderUserID":room.hostId,"roomVersion":room.version,
   "sequence":seq,"action":name,"positionMs":position,
   "issuedAtMs":Date().timeIntervalSince1970*1000,"mediaURL":room.mediaUrl
  ]
  p2pTransport.sendControl(payload)
 }
 private func receiveP2PControl(_ frame:[String:Any]) {
  guard connected,p2pEstablished,!isHost,let room=engine.room,
        room.roomId==p2pRoomID,
        let actionText=frame["action"] as? String,
        let action=P2PPlaybackAction(rawValue:actionText),
        let roomID=frame["roomID"] as? String,
        let sender=frame["senderUserID"] as? String,
        let version=(frame["roomVersion"] as? NSNumber)?.int64Value,
        let seq=(frame["sequence"] as? NSNumber)?.int64Value,
        let position=(frame["positionMs"] as? NSNumber)?.doubleValue,
        let sentAt=(frame["issuedAtMs"] as? NSNumber)?.doubleValue,
        frame["mediaURL"] as? String == room.mediaUrl,
        variantDurationCheck == .compatible,!plotPollWaiting,adapter.ready,
        (room.waitForPeer != true || members.allSatisfy({$0.ready && !$0.buffering})) else{return}
  let hint=P2PControlHint(roomID:roomID,senderUserID:sender,roomVersion:version,
                          sequence:seq,action:action,positionMs:position,issuedAtMs:sentAt)
  guard p2pGate.admit(hint,nowMs:Date().timeIntervalSince1970*1000) == .accepted else{return}
  p2pFastVersion=version;p2pFastUntil=clock.localNow()+1200
  switch action {
  case .pause:adapter.pause()
  case .seek:adapter.seekTo(position+engine.timelineOffset)
  case .play:adapter.play()
  }
 }
}
