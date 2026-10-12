import Foundation
import Combine

struct PlotFrame {
 let key:String
 let position:Double
 let evidence:[PlotEvidence]
 var prediction:PlotPrediction?
}
@MainActor final class PlotIntelligence:ObservableObject {
 @Published var mode:PlotMode {didSet {preferences.set(mode.rawValue,forKey:"plot-mode");if working {cancel()}}}
 @Published var automaticAllowed:Bool {didSet {preferences.set(automaticAllowed,forKey:"plot-cloud-allowed");if !automaticAllowed && working {cancel()}}}
 @Published var consent:Bool {didSet {preferences.set(consent,forKey:"plot-cloud-consent");if !consent && working {cancel()}}}
 @Published var creditsDisabled:Bool {didSet {preferences.set(creditsDisabled,forKey:"plot-cloud-no-credits");if !creditsDisabled && working {cancel()}}}
 @Published var limit:Int {didSet {limit=min(50,max(1,limit));preferences.set(limit,forKey:"plot-cloud-limit")}}
 @Published private(set) var working=false
 @Published private(set) var result:PlotQuestion?
 @Published private(set) var reason="手动生成，不影响播放"
 @Published private(set) var selectedModel="尚未出题"
 @Published private(set) var requests=0
 @Published private(set) var automaticRequests=0
 @Published private(set) var assessment=PlotComplexity.uncertain
 @Published private(set) var previewCutoff=0.0
 let auth=ChatGPTAuthProbe()
 private let memory:PlotMemoryStore
 private let preferences:UserDefaults
 private var operation:Task<Void,Never>?
 private var deadline:Task<Void,Never>?
 private var timer:Timer?
 private var generation=0
 private var lastKey=""
 private var generationCutoff=0.0
 var frame:(()->PlotFrame?)?
 init(memory:PlotMemoryStore=PlotMemoryStore(),preferences:UserDefaults = .standard) {
  self.memory=memory;self.preferences=preferences
  mode=PlotMode(rawValue:preferences.string(forKey:"plot-mode") ?? "") ?? .smart
  automaticAllowed=preferences.bool(forKey:"plot-cloud-allowed")
  consent=preferences.bool(forKey:"plot-cloud-consent")
  creditsDisabled=preferences.bool(forKey:"plot-cloud-no-credits")
  limit=min(50,max(1,preferences.object(forKey:"plot-cloud-limit") as? Int ?? 5))
 }
 func start() {
  guard timer==nil else {return}
  let next=Timer(timeInterval:20,repeats:true){[weak self] _ in Task{@MainActor in await self?.collect()}}
  timer=next;RunLoop.main.add(next,forMode:.common)
 }
 func collect() async {
  guard let snapshot=frame?(),snapshot.position.isFinite,snapshot.position>=0 else {return}
  if lastKey != snapshot.key {cancel();result=nil;lastKey=snapshot.key}
  else if snapshot.position<previewCutoff {result=nil}
  guard let state=try? await memory.ingest(snapshot.evidence,cutoff:snapshot.position,key:snapshot.key,prediction:snapshot.prediction) else {return}
  if frame?()?.key==snapshot.key {requests=state.budget.total;automaticRequests=state.budget.automatic}
 }
 func cancel() {generation+=1;operation?.cancel();operation=nil;deadline?.cancel();deadline=nil;working=false;reason="分析已取消，影片继续播放"}
 func playbackJumped() {
  guard let current=frame?() else {cancel();result=nil;return}
  if current.key != lastKey || (working && current.position<generationCutoff) {cancel()}
  if current.key != lastKey || current.position<previewCutoff {result=nil}
 }
 var previewUsable:Bool {guard let current=frame?() else {return false};return current.key==lastKey && current.position>=previewCutoff}
 func generate(manualDeep:Bool=false,regenerate:Bool=false) {
  guard !working,let snapshot=frame?() else {reason="请先加载影片并连接房间";return}
  cancel();lastKey=snapshot.key;generationCutoff=snapshot.position;let token=generation
  working=true;result=nil;reason="正在分析已观看的剧情…"
  operation=Task(priority:.utility) {[weak self] in await self?.run(snapshot,token:token,manualDeep:manualDeep,regenerate:regenerate)}
  deadline=Task {[weak self] in
   try? await Task.sleep(nanoseconds:60_000_000_000)
   guard !Task.isCancelled,let self,self.generation==token,self.working else {return}
   self.cancel();self.reason="分析超时，可以重试；影片继续播放"
  }
 }
 private func run(_ snapshot:PlotFrame,token:Int,manualDeep:Bool,regenerate:Bool) async {
  do {
   let state=try await memory.ingest(snapshot.evidence,cutoff:snapshot.position,key:snapshot.key,prediction:snapshot.prediction)
   requests=state.budget.total;automaticRequests=state.budget.automatic
   let context=state.context(at:snapshot.position)
   let history=state.questions.filter{$0.cutoff<=snapshot.position}.map{$0.question.text}
   if !regenerate,!manualDeep,let cached=state.reusable(at:snapshot.position) {
    complete(cached,reason:"复用这个已观看片段的问题，不消耗额度",frame:snapshot,token:token);return
   }
   let score=(mode == .smart || mode == .local) ? await PlotLocalAI.assess(context) : .uncertain
   guard valid(snapshot,token:token) else {cancel();return}
   assessment=score
   var local:PlotQuestion?
   if mode == .smart || mode == .local {local=await PlotLocalAI.question(context)}
   guard valid(snapshot,token:token) else {cancel();return}
   let localGood=local.map{PlotQuality.check($0,context:context,history:history)} ?? false
   var chosen=localGood ? local : nil
   var explanation=localGood ? "本地问题有具体证据，无需调用 ChatGPT" : "本地上下文或出题质量不足，使用备用题库"
   let policy=PlotRoutingPolicy(simple:preferences.object(forKey:"plot-simple-threshold") as? Int ?? 40,complex:preferences.object(forKey:"plot-complex-threshold") as? Int ?? 70)
   let requested=manualDeep || mode == .chatgpt || (mode == .smart && policy.wantsCloud(score,localQuality:localGood))
   if requested {
    if let cached=state.reusable(at:snapshot.position) {
     complete(cached,reason:"同片段已有可复用问题，未再次请求 ChatGPT",frame:snapshot,token:token);return
    }
    let allowed=consent && creditsDisabled && auth.canSendInference && !auth.working && context.sufficient && (manualDeep || automaticAllowed)
    if allowed,try await memory.reserve(key:snapshot.key,segment:Int(snapshot.position/180),manual:manualDeep,limit:limit,interval:180) {
     let current=await memory.load(snapshot.key);requests=current.budget.total;automaticRequests=current.budget.automatic
     do {
      guard valid(snapshot,token:token) else {cancel();return}
      let text=try await auth.performInference(instructions:PlotLocalAI.questionInstructions,input:context.boundedInput,canSend:{self.valid(snapshot,token:token)})
      guard valid(snapshot,token:token) else {return}
      if var cloud=PlotPromptMaker.parse(text),PlotQuality.check(cloud,context:context,history:history) {
       cloud=PlotQuestion(text:cloud.text,choices:cloud.choices,source:"ChatGPT",evidenceIDs:cloud.evidenceIDs,kind:cloud.kind)
       chosen=cloud;explanation=manualDeep ? "你手动请求了深度推理" : "本地题目不足，依据已观看的跨场景线索升级"
      } else {try await memory.fail(key:snapshot.key,segment:Int(snapshot.position/180));explanation="云端题目未通过证据或重复检查，安全回退"}
     } catch {try? await memory.fail(key:snapshot.key,segment:Int(snapshot.position/180));explanation="ChatGPT 不可用，已停止该片段自动重试并回退"}
    } else {explanation="尚未授权、未同意、额度暂停或调用间隔受限，继续本地方案"}
   }
   guard valid(snapshot,token:token) else {cancel();return}
   let question=chosen ?? PlotFallback.question(context:context,history:history)
   guard PlotQuality.check(question,context:context,history:history,allowGeneric:chosen==nil) else {
    cancel();reason="暂时没有通过检查的新问题，可以继续观看后再生成";return
   }
   // Summaries are optional and generated only during a manual request. No
   // perpetual inference or background cloud requests while watching.
   let clues=(mode == .smart || mode == .local) && PlotLocalAI.available ? await PlotLocalAI.summarize(context) : []
   guard valid(snapshot,token:token) else {cancel();return}
   try await memory.finish(key:snapshot.key,question:question,cutoff:snapshot.position,clues:clues,context:context)
   let why=score.confidence>=policy.minimumConfidence ? String(score.reasons.prefix(2).joined(separator:"；").prefix(100))+"。" : ""
   complete(question,reason:why+explanation,frame:snapshot,token:token)
  } catch {
   guard generation==token else {return};cancel();reason="本地记忆保存失败，未调用付费接口；可稍后重试"
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
 deinit {timer?.invalidate();operation?.cancel();deadline?.cancel()}
}
