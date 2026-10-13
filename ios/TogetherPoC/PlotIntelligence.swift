import Foundation
import Combine

struct PlotFrame {
 let key:String
 let position:Double
 let evidence:[PlotEvidence]
 var prediction:PlotPrediction?
 var plannedCheckpoint:Double? = nil
}
@MainActor final class PlotIntelligence:ObservableObject {
 @Published var mode:PlotMode {didSet {preferences.set(mode.rawValue,forKey:"plot-mode");momentTask?.cancel();momentTask=nil;if working {cancel()};result=nil;autoSuggestion=nil;selectedModel="尚未出题";reason="已切换到\(mode.title)，请重新生成问题"}}
 @Published var pauseForQuestions:Bool {didSet {preferences.set(pauseForQuestions,forKey:"plot-pause-for-questions")}}
 @Published var eventDrivenEnabled:Bool {didSet {preferences.set(eventDrivenEnabled,forKey:"plot-event-driven");if !eventDrivenEnabled {momentTask?.cancel();momentTask=nil}}}
 @Published var automaticAllowed:Bool {didSet {preferences.set(automaticAllowed,forKey:"plot-cloud-allowed");if !automaticAllowed && working {cancel()}}}
 @Published var consent:Bool {didSet {preferences.set(consent,forKey:"plot-cloud-consent");if !consent && working {cancel()}}}
 @Published var creditsDisabled:Bool {didSet {preferences.set(creditsDisabled,forKey:"plot-cloud-no-credits");if !creditsDisabled && working {cancel()}}}
 @Published var limit:Int {didSet {
  let bounded=min(50,max(1,limit))
  // @Published assignments invoke its wrapped setter again. Never write the
  // same value back inside the observer: that recurses until the process dies.
  if limit != bounded {limit=bounded;return}
  preferences.set(bounded,forKey:"plot-cloud-limit")
 }}
 @Published private(set) var working=false
 @Published private(set) var result:PlotQuestion?
 @Published private(set) var reason="手动生成，不影响播放"
 @Published private(set) var selectedModel="尚未出题"
 @Published private(set) var requests=0
 @Published private(set) var automaticRequests=0
 @Published private(set) var savedSubtitleCount=0
 var collectedSubtitleCount:Int {
  guard let current=frame?() else{return 0}
  return current.key==lastKey ? max(savedSubtitleCount,current.evidence.count) : current.evidence.count
 }
 @Published private(set) var assessment=PlotComplexity.uncertain
 @Published private(set) var latestBeat:PlotBeatAssessment?
 @Published private(set) var autoTriggerStatus="等待已播放字幕与剧情转折"
 @Published private(set) var previewCutoff=0.0
 @Published private(set) var autoSuggestion:PlotQuestion?
 @Published private(set) var fullFilmPreparationStatus="尚未获得完整字幕"
 let auth=ChatGPTAuthProbe()
 private let memory:PlotMemoryStore
 private let preferences:UserDefaults
 private var operation:Task<Void,Never>?
 private var deadline:Task<Void,Never>?
 private var timer:Timer?
 private var generation=0
 private var lastKey=""
 private var generationCutoff=0.0
 private var momentTask:Task<Void,Never>?
 private var mostRecentAutoKey=""
 private var mostRecentAutoPosition = -Double.infinity
 private var mostRecentPublishedPosition = -Double.infinity
 private var fullFilmTask:Task<Void,Never>?
 private var fullFilmPreparedKey=""
 private var fullFilmPreparedCount=0
 private var fullFilmQuestions:[Int:PlotQuestion]=[:]
 var mayPublishAutomatically:(()->Bool)?
 var automaticAvailabilityReason:(()->String?)?
 var publishAutomatically:((PlotQuestion)->Void)?
 var isSubtitleCurrentlyShown:(()->Bool)?
 var frame:(()->PlotFrame?)?
 var visualEvidenceEnabled=false
 func visualChanged() {guard visualEvidenceEnabled else{return};subtitleChanged("")}
 /// Read the whole subtitle timeline to choose key moments. Each local-model
 /// prompt receives only earlier dialogue, so no future scene can spoil a
 /// preplanned question. This is best effort and never blocks playback.
 func prepareFullFilm(_ document:SubtitleDocument,source:String,key:String,checkpoints:[PlotQuestionCheckpoint]) {
  guard !key.isEmpty,document.cues.count>=6 else{return}
  let signature="\(key):\(source):\(document.cues.count):\(checkpoints.count)"
  guard signature != fullFilmPreparedKey else{return}
  fullFilmTask?.cancel()
  fullFilmPreparedKey=signature
  fullFilmQuestions=[:];fullFilmPreparedCount=0
  guard PlotLocalAI.available else {
   fullFilmPreparationStatus="全片字幕已建立时间轴；苹果本地 AI 暂不可用，播放时继续实时分析"
   return
  }
  let points=Array(checkpoints.sorted{$0.score>$1.score}.prefix(5)).sorted{$0.at<$1.at}
  fullFilmPreparationStatus="已读取完整字幕（\(document.cues.count)条），正在提前规划剧情问题…"
  fullFilmTask=Task(priority:.background) {[weak self] in
   guard let self else{return}
   for point in points {
    if Task.isCancelled || self.fullFilmPreparedKey != signature {return}
    let context=PlotFullFilmPlanner.context(document,at:point.at,source:source)
    guard context.sufficient else{continue}
    if let answer=await PlotLocalAI.question(context,automatic:true,planned:true),
       PlotQuality.check(answer,context:context,history:[]),
       PlotMomentGate.questionIsTimely(answer,context:context),
       !Task.isCancelled,self.fullFilmPreparedKey==signature {
      self.fullFilmQuestions[Int(point.at.rounded())]=answer
      self.fullFilmPreparedCount+=1
    }
    self.fullFilmPreparationStatus="全片索引已就绪 · 已规划\(self.fullFilmPreparedCount)/\(points.count)道有证据的问题"
    await Task.yield()
   }
   if !Task.isCancelled,self.fullFilmPreparedKey==signature {
    self.fullFilmPreparationStatus="全片预分析完成 · \(self.fullFilmPreparedCount)道待复核问题；播放时继续补充"
   }
  }
 }
 private func preparedQuestion(for snapshot:PlotFrame,context:PlotContext,history:[String])->PlotQuestion? {
  guard let checkpoint=snapshot.plannedCheckpoint else{return nil}
  let key=Int(checkpoint.rounded())
  guard let question=fullFilmQuestions[key],fullFilmPreparedKey.hasPrefix(snapshot.key+":"),
   PlotQuality.check(question,context:context,history:history),
   PlotMomentGate.questionIsTimely(question,context:context) else{return nil}
  return question
 }
 init(memory:PlotMemoryStore=PlotMemoryStore(),preferences:UserDefaults = .standard) {
  self.memory=memory;self.preferences=preferences
  mode=PlotMode(rawValue:preferences.string(forKey:"plot-mode") ?? "") ?? .smart
  pauseForQuestions=preferences.object(forKey:"plot-pause-for-questions") as? Bool ?? true
  eventDrivenEnabled=preferences.object(forKey:"plot-event-driven") as? Bool ?? true
  automaticAllowed=preferences.bool(forKey:"plot-cloud-allowed")
  consent=preferences.bool(forKey:"plot-cloud-consent")
  creditsDisabled=preferences.bool(forKey:"plot-cloud-no-credits")
  limit=min(50,max(1,preferences.object(forKey:"plot-cloud-limit") as? Int ?? 10))
 }
 func start() {
  guard timer==nil else {return}
  let next=Timer(timeInterval:20,repeats:true){[weak self] _ in Task{@MainActor in await self?.collect()}}
  timer=next;RunLoop.main.add(next,forMode:.common)
 }
 func collect() async {
  guard let snapshot=frame?(),snapshot.position.isFinite,snapshot.position>=0 else {return}
  if lastKey != snapshot.key {cancel();result=nil;autoSuggestion=nil;latestBeat=nil;autoTriggerStatus="已加载新影片，正在积累字幕";savedSubtitleCount=0;mostRecentAutoKey="";mostRecentAutoPosition = -.infinity;mostRecentPublishedPosition = -.infinity;lastKey=snapshot.key}
  else if snapshot.position<previewCutoff {result=nil}
  guard let state=try? await memory.ingest(snapshot.evidence,cutoff:snapshot.position,key:snapshot.key,prediction:snapshot.prediction) else {return}
  if frame?()?.key==snapshot.key {requests=state.budget.total;automaticRequests=state.budget.automatic;savedSubtitleCount=state.evidence.count}
  // AVPlayerItemLegibleOutput does not promise an empty end callback for every
  // caption. Evaluate natural quiet gaps at the existing 20-second sample too.
  // This is an opportunity to inspect a story beat, never a fixed-time prompt.
  if eventDrivenEnabled,!working,momentTask==nil,
   isSubtitleCurrentlyShown?()==false {
   subtitleChanged("")
  }
 }
 // Snapshot before the transport or player is torn down. The actor keeps
 // the final watched cues even if the normal 20-second sampler has not fired.
 func preserveCurrentFilmEvidence() {
  guard let snapshot=frame?(),lastKey.isEmpty || snapshot.key==lastKey else{return}
  Task(priority:.utility) {[memory] in
   _ = try? await memory.ingest(snapshot.evidence,cutoff:snapshot.position,key:snapshot.key,prediction:snapshot.prediction)
  }
 }
 func cancel() {generation+=1;operation?.cancel();operation=nil;deadline?.cancel();deadline=nil;working=false;reason="分析已取消，影片继续播放"}
 func subtitleChanged(_ text:String) {
  momentTask?.cancel();momentTask=nil
  // Only evaluate already-watched subtitles at the end of a caption.
  // A reconnect can replace the player, so merge stored film evidence
  // before deciding whether this quiet gap is a real plot turning point.
  guard text.isEmpty else{return}
  guard eventDrivenEnabled else{autoTriggerStatus="自动暂停提问已关闭";return}
  guard mode != .fallback else{autoTriggerStatus="免费备用题库只支持手动出题；自动提问请选择真实 AI";return}
  guard !working else{autoTriggerStatus="AI 正在分析剧情";return}
  if let blocked=automaticAvailabilityReason?() {autoTriggerStatus=blocked;return}
  guard mayPublishAutomatically?()==true else{autoTriggerStatus="当前房间不满足自动提问条件";return}
  guard let snapshot=frame?() else{autoTriggerStatus="暂未获得可用的影片进度";return}
  let key=snapshot.key,last=snapshot.evidence.last?.id ?? ""
  momentTask=Task {[weak self] in
   guard let self,!Task.isCancelled else{return}
   // Read persisted clues without writing the entire growing film JSON on
   // every subtitle gap. The normal 20-second sampler and generation pass
   // perform durable saves; disconnect also flushes the last observed batch.
   var saved=await self.memory.load(key)
   if !self.visualEvidenceEnabled {saved.evidence.removeAll{$0.source=="ondevice-vision"}}
   saved.ingest(snapshot.evidence,cutoff:snapshot.position)
   guard !Task.isCancelled,self.frame?()?.key==key else{return}
   let beat=PlotMomentGate.assess(saved.evidence,position:snapshot.position,minQuietSeconds:0)
   self.latestBeat=beat
   let scheduled=snapshot.plannedCheckpoint != nil &&
    PlotQuestionPlanner.hasWatchedEvidence(saved.evidence,at:snapshot.position)
   guard beat.isCandidate || scheduled else {
    self.autoTriggerStatus="已采集字幕，当前场景未达到剧情提问门槛（线索\(beat.informationChange) · 矛盾\(beat.contradiction) · 悬念\(beat.unresolvedMystery) · 剧情变化\(beat.storyDevelopment) · 画面变化\(beat.visualTransitions)）"
    return
   }
   guard key != self.mostRecentAutoKey ||
    PlotMomentGate.canAttempt(position:snapshot.position,lastAttempt:self.mostRecentAutoPosition,lastPublished:self.mostRecentPublishedPosition) else {
    self.autoTriggerStatus="已有剧情候选，正在避免重复打断"
    return
   }
   self.autoTriggerStatus=scheduled ? "进入预规划讨论区间，等待对白结束后分析" : "发现剧情候选，等待对白自然结束后复核"
   try? await Task.sleep(nanoseconds:3_500_000_000)
   guard !Task.isCancelled,self.eventDrivenEnabled,!self.working,self.mayPublishAutomatically?()==true,
    self.isSubtitleCurrentlyShown?()==false else{return}
   guard let current=self.frame?(),current.key==key,current.evidence.last?.id==last else{return}
   var restored=await self.memory.load(key)
   if !self.visualEvidenceEnabled {restored.evidence.removeAll{$0.source=="ondevice-vision"}}
   restored.ingest(current.evidence,cutoff:current.position)
   let checkpointReady=scheduled && current.plannedCheckpoint != nil &&
    PlotQuestionPlanner.hasWatchedEvidence(restored.evidence,at:current.position)
   guard !Task.isCancelled,
    (PlotMomentGate.likelyQuestionMoment(restored.evidence,position:current.position) || checkpointReady) else {
    self.autoTriggerStatus="候选剧情复核未通过，继续观影"
    return
   }
   self.mostRecentAutoKey=key;self.mostRecentAutoPosition=current.position
   self.autoTriggerStatus=checkpointReady ? "已到预规划讨论点，正在结合已看字幕与画面出题" : "剧情候选通过，正在请求 AI 生成问题"
   self.generate(autoMoment:true,plannedMoment:checkpointReady)
  }
 }
 func acknowledgeAutoSuggestion() {autoSuggestion=nil}
 func playbackJumped() {
  momentTask?.cancel();momentTask=nil;autoSuggestion=nil;latestBeat=nil
  guard let current=frame?() else {cancel();result=nil;return}
  if current.key != lastKey || (working && current.position<generationCutoff) {cancel()}
  if current.key != lastKey || current.position<previewCutoff {result=nil}
 }
 var previewUsable:Bool {guard let current=frame?() else {return false};return current.key==lastKey && current.position>=previewCutoff}
 func generate(manualDeep:Bool=false,regenerate:Bool=false,autoMoment:Bool=false,plannedMoment:Bool=false) {
  guard !working,let snapshot=frame?() else {reason="请先加载影片；本机出题无需房间在线";return}
  cancel();lastKey=snapshot.key;generationCutoff=snapshot.position;let token=generation
  working=true;result=nil;reason="正在分析已观看的剧情…"
  operation=Task(priority:.utility) {[weak self] in await self?.run(snapshot,token:token,manualDeep:manualDeep,regenerate:regenerate,autoMoment:autoMoment,plannedMoment:plannedMoment)}
  deadline=Task {[weak self] in
   try? await Task.sleep(nanoseconds:60_000_000_000)
   guard !Task.isCancelled,let self,self.generation==token,self.working else {return}
   self.cancel();self.reason="分析超时，可以重试；影片继续播放"
  }
 }
 private func run(_ snapshot:PlotFrame,token:Int,manualDeep:Bool,regenerate:Bool,autoMoment:Bool,plannedMoment:Bool) async {
  do {
   var state=try await memory.ingest(snapshot.evidence,cutoff:snapshot.position,key:snapshot.key,prediction:snapshot.prediction)
   if !visualEvidenceEnabled {state.evidence.removeAll{$0.source=="ondevice-vision"}}
   requests=state.budget.total;automaticRequests=state.budget.automatic
   if frame?()?.key==snapshot.key {savedSubtitleCount=state.evidence.count}
   let context=state.context(at:snapshot.position)
   let history=state.questions.filter{$0.cutoff<=snapshot.position}.map{$0.question.text}
   // Explicit model choices MUST NOT silently reuse a free-template cache.
   // This also permits users to switch from a cached fallback to real AI.
   let explicitlyCloud=manualDeep || mode == .chatgpt
   let explicitlyLocal=mode == .local && !manualDeep
   func matchesSelection(_ item:PlotQuestion)->Bool {
    if explicitlyCloud {return item.source=="ChatGPT"}
    if explicitlyLocal {return item.source=="Apple 设备端 AI"}
    if mode == .fallback {return item.source=="免费备用题库"}
    // A previous emergency template must not prevent fresh zero-cost AI
    // inference after Apple finishes downloading the on-device model.
    if mode == .smart {return item.source=="ChatGPT" || item.source=="Apple 设备端 AI"}
    return true
   }
   if autoMoment,let cached=state.reusable(at:snapshot.position),matchesSelection(cached) {autoTriggerStatus="该剧情片段已经生成过问题，为避免重复打断已跳过";working=false;deadline?.cancel();deadline=nil;return}
   if !regenerate,!manualDeep,let cached=state.reusable(at:snapshot.position),matchesSelection(cached) {
    complete(cached,reason:"复用该模型在同片段已生成的问题，没有再次消耗额度",frame:snapshot,token:token);return
   }
   let indexedReady=plannedMoment && snapshot.plannedCheckpoint != nil &&
    PlotQuestionPlanner.hasWatchedEvidence(context.recent,at:snapshot.position)
   if autoMoment && (!context.sufficient ||
    (!PlotMomentGate.likelyQuestionMoment(context.recent,position:snapshot.position) && !indexedReady)) {
    autoTriggerStatus="本次剧情线索不足，暂不暂停影片";working=false;deadline?.cancel();deadline=nil;return
   }
   let prepared=(mode == .smart || mode == .local) ? preparedQuestion(for:snapshot,context:context,history:history) : nil
   let score:PlotComplexity=prepared != nil ? .uncertain : ((mode == .smart || mode == .local) ? await PlotLocalAI.assess(context) : .uncertain)
   guard valid(snapshot,token:token) else {cancel();return}
   assessment=score
   var local:PlotQuestion?
   if mode == .smart || mode == .local {
    // Even without subtitles, use the REAL on-device model for an honest
    // context-free question; never claim it analyzed unobserved movie content.
    local=prepared ?? (context.sufficient ? await PlotLocalAI.question(context,automatic:autoMoment,planned:plannedMoment) : await PlotLocalAI.genericQuestion(at:snapshot.position))
   }
   guard valid(snapshot,token:token) else {cancel();return}
   var localGeneric = !context.sufficient
   var localGood=local.map{PlotQuality.check($0,context:context,history:history,allowGeneric:localGeneric && $0.evidenceIDs.isEmpty)} ?? false
   if !localGood && context.sufficient && (mode == .local || mode == .smart) && PlotLocalAI.available {
    // Try one genuine zero-cost model question, without claiming to know
    // a movie scene that the strict subtitle-evidence validator rejected.
    local=await PlotLocalAI.genericQuestion(at:snapshot.position)
    guard valid(snapshot,token:token) else {cancel();return}
    localGeneric=true
    localGood=local.map{PlotQuality.check($0,context:context,history:history,allowGeneric:$0.evidenceIDs.isEmpty)} ?? false
   }
   var chosen=localGood ? local : nil
   var explanation=localGood ? (prepared != nil ? "采用全片预规划问题，已使用实际看过的字幕重新核验" : (localGeneric ? "苹果本地 AI 已生成通用讨论题；未编造影片细节" : "苹果本地 AI 已根据已观看字幕出题")) :
     (PlotLocalAI.available ? "本地 AI 回答未通过格式、线索或重复检查" : PlotLocalAI.availabilityDetail)
   let policy=PlotRoutingPolicy(simple:preferences.object(forKey:"plot-simple-threshold") as? Int ?? 40,complex:preferences.object(forKey:"plot-complex-threshold") as? Int ?? 70)
   let requested=explicitlyCloud || (mode == .smart && policy.wantsCloud(score,localQuality:localGood,contextSufficient:context.sufficient))
   if requested {
    if let cached=state.reusable(at:snapshot.position),cached.source=="ChatGPT" {
     complete(cached,reason:"复用该片段已完成的 ChatGPT 问题，没有再次消耗额度",frame:snapshot,token:token);return
    }
    // Explicit model choice is itself a manual request. The automatic-call
    // toggle must only control automatic smart routing, not manual selection.
    // With no subtitles, never send invented film details; ask a general
    // question using the actual ChatGPT model.
    // A person pressing Generate in Smart mode may request an honest,
    // context-free ChatGPT question when subtitle evidence is missing.
    // Automatic moments still require evidence before any cloud request.
    let allowed=consent && creditsDisabled && auth.integrationReady && !auth.usagePaused && !auth.working &&
       (context.sufficient || explicitlyCloud || (!autoMoment && mode == .smart)) &&
       (!autoMoment || automaticAllowed) && (explicitlyCloud || automaticAllowed)
    if allowed {
     if try await memory.reserve(key:snapshot.key,segment:Int(snapshot.position/180),manual:!autoMoment,limit:limit,interval:180) {
      let current=await memory.load(snapshot.key);requests=current.budget.total;automaticRequests=current.budget.automatic
      do {
       guard valid(snapshot,token:token) else {cancel();return}
       let instruction=context.sufficient ? (plannedMoment ? PlotLocalAI.plannedMomentInstructions : (autoMoment ? PlotLocalAI.importantMomentInstructions : PlotLocalAI.questionInstructions)) : PlotLocalAI.noEvidenceInstructions
       let input=context.sufficient ? context.boundedInput : "当前影片播放到约\(Int(snapshot.position/60))分钟，暂无足够的已观看字幕；请生成一道不依赖任何虚构细节的通用讨论问题。"
       let text=try await auth.performInference(instructions:instruction,input:input,canSend:{self.valid(snapshot,token:token)})
       guard valid(snapshot,token:token) else {return}
       if let cloud=PlotPromptMaker.parse(text),PlotQuality.check(cloud,context:context,history:history,allowGeneric:!context.sufficient && cloud.evidenceIDs.isEmpty) {
        chosen=PlotQuestion(text:cloud.text,choices:cloud.choices,source:"ChatGPT",evidenceIDs:cloud.evidenceIDs,kind:cloud.kind)
        explanation=context.sufficient ? "ChatGPT 已根据已观看的字幕生成问题" : "ChatGPT 已生成通用讨论题，未读取或编造影片剧情"
       } else {
        try? await memory.fail(key:snapshot.key,segment:Int(snapshot.position/180))
        explanation="ChatGPT 已返回内容，但问题格式、线索引用或重复检查未通过；没有冒充成功"
       }
      } catch {
       try? await memory.fail(key:snapshot.key,segment:Int(snapshot.position/180))
       explanation="ChatGPT 请求失败：\(error.localizedDescription)。不会自动重试或切换到付费 API"
      }
     } else {
      explanation="该片段已请求过或仍在3分钟冷却期，为防止重复消耗额度暂不再次调用 ChatGPT"
     }
    } else if !consent {
     explanation="尚未同意向 ChatGPT 发送必要剧情摘要，请到授权与隐私设置开启"
    } else if !creditsDisabled {
     explanation="尚未确认已在官方设置禁用额外 Credits，请先完成额度保护设置"
    } else if !auth.integrationReady {
     explanation="ChatGPT 尚未完成首次授权，或本机授权已失效；不需要连续调用验收"
    } else if auth.usagePaused {
     explanation="ChatGPT 额度暂停；请检查官方用量设置"
    } else if mode == .smart && !automaticAllowed {
     explanation="尚未开启智能调用 ChatGPT，请在剧情推理室开启开关（同时需要本应用独立授权）"
    } else if !context.sufficient && autoMoment {
     explanation="没有足够的已观看字幕，智能模式不会自动消耗 ChatGPT 额度"
    } else {
     explanation="当前云端调用暂不可用，请稍后再试"
    }
   }
   guard valid(snapshot,token:token) else {cancel();return}
   // A user's explicit model selection is NOT the 'free template' mode.
   // Display the real failure instead of silently substituting a template.
   if (explicitlyCloud && chosen?.source != "ChatGPT") || (explicitlyLocal && chosen?.source != "Apple 设备端 AI") {
    selectedModel=explicitlyCloud ? "ChatGPT 未出题" : "苹果本地 AI 未出题"
    if autoMoment {autoTriggerStatus="已发现剧情候选，AI 未完成出题：\(explanation)"}
    reason=explanation;working=false;deadline?.cancel();deadline=nil;return
   }
   // Smart mode promises a real model. Show actionable failure information
   // instead of silently presenting a free template as its own output.
   if mode == .smart && chosen == nil {
    if autoMoment {autoTriggerStatus="已发现剧情候选，智能模式无法出题：\(explanation)"}
    selectedModel="智能模式未出题"
    reason=explanation+"；没有可用的真实 AI 结果，请检查设备端模型及 ChatGPT 授权/开关，或主动切换免费备用题库"
    working=false;deadline?.cancel();deadline=nil;return
   }
   // An automatic suggestion is NEVER a free template or an uncited question.
   // Avoid popping up an unrelated generic question mid-film.
   if autoMoment && (chosen == nil || chosen?.evidenceIDs.isEmpty == true || !PlotMomentGate.questionIsTimely(chosen!,context:context)) {
    autoTriggerStatus=chosen == nil ? "剧情候选有效，但真实 AI 未生成合格问题：\(explanation)" : "AI 问题缺乏当前剧情证据，已避免打断"
    working=false;deadline?.cancel();deadline=nil;return
   }
   let question=chosen ?? PlotFallback.question(context:context,history:history)
   guard chosen != nil || PlotQuality.check(question,context:context,history:history,allowGeneric:true) else {
    cancel();reason="生成的问题没有通过安全或重复检查，请稍后重试";return
   }
   let clues=(mode == .smart || mode == .local) && PlotLocalAI.available && context.sufficient ? await PlotLocalAI.summarize(context) : []
   guard valid(snapshot,token:token) else {cancel();return}
   try await memory.finish(key:snapshot.key,question:question,cutoff:snapshot.position,clues:clues,context:context)
   let why=score.confidence>=policy.minimumConfidence ? String(score.reasons.prefix(2).joined(separator:"；").prefix(100))+"。" : ""
   complete(question,reason:why+(chosen==nil ? "没有足够的可靠 AI 结果，因此明确使用免费备用题库。" : "")+explanation,frame:snapshot,token:token)
   if autoMoment && result != nil {
    // Automatic story questions always pause the shared playback. The server
    // coordinates both answers, readiness, and safe resumption.
    let safe=PlotQuestion(text:question.text,choices:question.choices,source:question.source,evidenceIDs:question.evidenceIDs,kind:question.kind,blocking:true)
    if mayPublishAutomatically?()==true && isSubtitleCurrentlyShown?()==false,
     let now=frame?(),now.key==snapshot.key,now.position>=snapshot.position,
     now.position-snapshot.position<=45 {
     mostRecentPublishedPosition=now.position
     autoTriggerStatus="已自动发布剧情问题，请回答后继续观影"
     autoSuggestion=safe
     publishAutomatically?(safe)
    }
   }
  } catch {
   guard generation==token else {return}
   cancel();reason="本地剧情记忆保存失败；没有消耗新的云端请求，请稍后再试"
  }
 }
 private func valid(_ snapshot:PlotFrame,token:Int)->Bool {
  guard !Task.isCancelled,generation==token,let current=frame?() else {return false}
  return current.key==snapshot.key && current.position>=snapshot.position
 }
 private func complete(_ question:PlotQuestion,reason:String,frame snapshot:PlotFrame,token:Int) {
  guard valid(snapshot,token:token) else {return}
  result=question;previewCutoff=snapshot.position;self.reason=reason;selectedModel=question.source;working=false;deadline?.cancel();deadline=nil
  let decision=PlotDecision(timestamp:Date().timeIntervalSince1970,position:snapshot.position,mode:mode.rawValue,selectedModel:question.source,reason:reason,complexityScore:assessment.complexityScore,confidence:assessment.confidence,requests:requests,quality:question.evidenceIDs.isEmpty ? "generic_fallback" : "evidence_checked",misjudgmentReview:"notReviewed")
  Task(priority:.utility) {try? await memory.record(key:snapshot.key,decision:decision)}
 }
 deinit {timer?.invalidate();operation?.cancel();deadline?.cancel();momentTask?.cancel();fullFilmTask?.cancel()}
}
