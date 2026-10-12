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
  limit=min(50,max(1,preferences.object(forKey:"plot-cloud-limit") as? Int ?? 10))
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
  guard !working,let snapshot=frame?() else {reason="请先加载影片；本机出题无需房间在线";return}
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
   // Explicit model choices MUST NOT silently reuse a free-template cache.
   // This also permits users to switch from a cached fallback to real AI.
   let explicitlyCloud=manualDeep || mode == .chatgpt
   let explicitlyLocal=mode == .local && !manualDeep
   func matchesSelection(_ item:PlotQuestion)->Bool {
    if explicitlyCloud {return item.source=="ChatGPT"}
    if explicitlyLocal {return item.source=="Apple 设备端 AI"}
    return true
   }
   if !regenerate,!manualDeep,let cached=state.reusable(at:snapshot.position),matchesSelection(cached) {
    complete(cached,reason:"复用该模型在同片段已生成的问题，没有再次消耗额度",frame:snapshot,token:token);return
   }
   let score=(mode == .smart || mode == .local) ? await PlotLocalAI.assess(context) : .uncertain
   guard valid(snapshot,token:token) else {cancel();return}
   assessment=score
   var local:PlotQuestion?
   if mode == .smart || mode == .local {
    // Even without subtitles, use the REAL on-device model for an honest
    // context-free question; never claim it analyzed unobserved movie content.
    local=context.sufficient ? await PlotLocalAI.question(context) : await PlotLocalAI.genericQuestion(at:snapshot.position)
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
   var explanation=localGood ? (localGeneric ? "苹果本地 AI 已生成通用讨论题；未编造影片细节" : "苹果本地 AI 已根据已观看字幕出题") :
     (PlotLocalAI.available ? "本地 AI 回答未通过格式、线索或重复检查" : "苹果系统设备端语言模型暂不可用")
   let policy=PlotRoutingPolicy(simple:preferences.object(forKey:"plot-simple-threshold") as? Int ?? 40,complex:preferences.object(forKey:"plot-complex-threshold") as? Int ?? 70)
   let requested=explicitlyCloud || (mode == .smart && policy.wantsCloud(score,localQuality:localGood))
   if requested {
    if let cached=state.reusable(at:snapshot.position),matchesSelection(cached) {
     complete(cached,reason:"复用该片段已完成的 ChatGPT 问题，没有再次消耗额度",frame:snapshot,token:token);return
    }
    // Explicit model choice is itself a manual request. The automatic-call
    // toggle must only control automatic smart routing, not manual selection.
    // With no subtitles, never send invented film details; ask a general
    // question using the actual ChatGPT model.
    let allowed=consent && creditsDisabled && auth.integrationReady && !auth.usagePaused && !auth.working &&
       (context.sufficient || explicitlyCloud) && (explicitlyCloud || automaticAllowed)
    if allowed {
     if try await memory.reserve(key:snapshot.key,segment:Int(snapshot.position/180),manual:explicitlyCloud,limit:limit,interval:180) {
      let current=await memory.load(snapshot.key);requests=current.budget.total;automaticRequests=current.budget.automatic
      do {
       guard valid(snapshot,token:token) else {cancel();return}
       let instruction=context.sufficient ? PlotLocalAI.questionInstructions : PlotLocalAI.noEvidenceInstructions
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
    } else if !context.sufficient && !explicitlyCloud {
     explanation="没有足够的已观看字幕，智能模式不自动消耗 ChatGPT 额度"
    } else {
     explanation="当前云端调用暂不可用，请稍后再试"
    }
   }
   guard valid(snapshot,token:token) else {cancel();return}
   // A user's explicit model selection is NOT the 'free template' mode.
   // Display the real failure instead of silently substituting a template.
   if (explicitlyCloud && chosen?.source != "ChatGPT") || (explicitlyLocal && chosen?.source != "Apple 设备端 AI") {
    selectedModel=explicitlyCloud ? "ChatGPT 未出题" : "苹果本地 AI 未出题"
    reason=explanation;working=false;deadline?.cancel();deadline=nil;return
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
 deinit {timer?.invalidate();operation?.cancel();deadline?.cancel()}
}
