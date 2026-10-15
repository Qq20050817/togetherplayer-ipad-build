import Foundation
import Combine

// Host-only bank and answer keys. Existing server polls contain public fields
// only; delayed, idempotent chat messages carry answers after the reveal time.
@MainActor final class FilmQuestionBankRuntime:ObservableObject {
 @Published private(set) var active:FilmQuestionBank?
 @Published private(set) var status="当前影片未导入题库"
 @Published private(set) var revealedAnswer=""
 @Published private(set) var publishedCount=0
 @Published private(set) var completedCount=0
 var onBankReady:(()->Void)?
 private let store:FilmQuestionBankStore
 private let progressStore:FilmBankProgressStore
 init(store:FilmQuestionBankStore=FilmQuestionBankStore(),progressStore:FilmBankProgressStore=FilmBankProgressStore()){self.store=store;self.progressStore=progressStore}
 private var key="",progressKey=""
 private var sourceURL:URL?
 private var generation=0
 private var restoring:Task<Void,Never>?
 private var fingerprinting:Task<String,Error>?
 private var lastPositionMs:Double?
 private var progress=FilmBankProgress()
 private var pendingQuestion:FilmBankQuestion?
 private var sendingParts=Set<String>()
 private var pendingSubtitleSequence:Int?
 private var progressWrite:Task<Void,Error>?
 private var publishing:Task<Void,Never>?

 private func activate(_ bank:FilmQuestionBank,token:Int) async {
  let identity=FilmBankCodec.identity(bank)
  try? await progressWrite?.value
  let saved=await progressStore.load(identity)
  guard generation==token,!Task.isCancelled else{return}
  progressKey=identity;progress=saved;publishedCount=saved.published.count;completedCount=saved.answered.count
  active=bank;onBankReady?();status="已加载 \(bank.questions.count) 道题 · 本轮已发布 \(publishedCount) 道 · 播放时不请求 AI"
 }
 func restore(filmKey:String,source:URL,durationMs:Double) {
  if key==filmKey,sourceURL==source,active != nil {return}
  active=nil;key=filmKey;sourceURL=source;lastPositionMs=nil;pendingQuestion=nil;pendingSubtitleSequence=nil;sendingParts=[];revealedAnswer=""
  generation+=1;let token=generation
  restoring?.cancel();fingerprinting?.cancel();publishing?.cancel()
  guard source.isFileURL else {status="远程片源无法严格校验，题库自动提问未启用";return}
  status="正在校验本地原片指纹和已保存题库…"
  let job=Task.detached(priority:.utility){() throws->String in
   let access=source.startAccessingSecurityScopedResource();defer{if access {source.stopAccessingSecurityScopedResource()}}
   return try FilmMaterialFingerprint.source(source)
  }
  fingerprinting=job
  restoring=Task {[weak self] in
   guard let self else{return}
   do {
    let fingerprint=try await job.value
    guard generation==token,!Task.isCancelled else{return}
    // Migrate a matching prior room-keyed bank without discarding it.
    let cached=await store.loadForSource(fingerprint)
    let legacy:FilmQuestionBank?
    if cached==nil {legacy=await store.load(filmKey:filmKey)} else {legacy=nil}
    guard let bank=cached ?? legacy else {status="当前原片尚无题库；可制作素材或导入 JSON";return}
    guard bank.sourceFingerprint?.lowercased()==fingerprint.lowercased() else {status="旧题库原片指纹不匹配，请重新导出素材制作题库";return}
    guard durationMs<=0 || FilmBankCodec.matches(bank,playbackDuration:durationMs) else {status="题库与电影时长不匹配，自动提问未启用";return}
    if cached==nil {try await store.saveForSource(bank)}
    await activate(bank,token:token)
   } catch {if generation==token {status="原片校验失败："+error.localizedDescription}}
  }
 }
 func importFile(_ url:URL,filmKey:String?,source:URL?,durationMs:Double) async {
  guard let filmKey,!filmKey.isEmpty,let source,source.isFileURL,key==filmKey,sourceURL==source else {status="请先加载本地原片，再导入题库";return}
  let token=generation
  status="正在校验 Schema、完整原片 SHA256 与时间轴…"
  do {
   let result=try await Task.detached(priority:.utility){() throws->(FilmQuestionBank,String) in
    let access=url.startAccessingSecurityScopedResource();defer{if access {url.stopAccessingSecurityScopedResource()}}
    let handle=try FileHandle(forReadingFrom:url);defer{try? handle.close()}
    let data=try handle.read(upToCount:FilmBankCodec.maxBytes+1) ?? Data(),bank=try FilmBankCodec.decode(data)
    let scoped=source.startAccessingSecurityScopedResource();defer{if scoped {source.stopAccessingSecurityScopedResource()}}
    return (bank,try FilmMaterialFingerprint.source(source))
   }.value
   guard generation==token,key==filmKey,sourceURL==source else{return}
   let (bank,fingerprint)=result
   guard bank.sourceFingerprint?.lowercased()==fingerprint.lowercased() else{status="原片指纹不匹配，未加载。请用当前原片导出的素材制作题库。";return}
   guard FilmBankCodec.matches(bank,playbackDuration:durationMs) else{status="影片时长/剪辑版本不匹配，未加载题库。";return}
   try await store.saveForSource(bank)
   guard generation==token else{return}
   restoring?.cancel();fingerprinting?.cancel();publishing?.cancel();lastPositionMs=nil;pendingQuestion=nil
   await activate(bank,token:token)
  } catch {if generation==token {status="导入失败："+error.localizedDescription}}
 }
 func ownsQuestion(_ text:String,options:[String])->Bool {active?.questions.contains{$0.question==text && $0.options==options} == true}
 private func persist()->Task<Void,Error> {
  progress.revision+=1
  let snapshot=progress,identity=progressKey,store=progressStore,previous=progressWrite
  let task=Task {try? await previous?.value;try await store.save(snapshot,key:identity)}
  progressWrite=task;return task
 }
 /// Explicit new viewing round; seeking backwards never resets these records.
 func startNewRound() {
  guard active != nil else{return}
  generation+=1;publishing?.cancel()
  progress=FilmBankProgress(revision:progress.revision+1);publishedCount=0;completedCount=0;revealedAnswer="";lastPositionMs=nil;pendingQuestion=nil;sendingParts=[]
  let write=persist();Task {do{try await write.value}catch{self.status="本轮记录保存失败："+error.localizedDescription}}
  status="已开始新一轮，题库保留；从实际播放进度触发"
 }
 func observePoll(_ poll:[String:Any]?) {
  guard let bank=active,let poll,poll["revealed"] as? Bool==true,
   let text=poll["question"] as? String,let options=poll["options"] as? [String],
   let q=bank.questions.first(where:{$0.question==text && $0.options==options}),
   progress.published.contains(q.id),!progress.answered.contains(q.id) else{return}
  progress.answered.insert(q.id);completedCount=progress.answered.count
  let write=persist();Task {do{try await write.value}catch{self.status="答题进度未能保存；题库本身仍保留"}}
 }
 private func parts(_ q:FilmBankQuestion)->[FilmBankRevealPart] {
  guard active != nil,let index=q.answerIndex,q.options.indices.contains(index) else{return []}
  var remainder="\(q.question)\n正确答案：\(q.options[index])\n\(q.explanation)"
  var texts:[String]=[]
  while !remainder.isEmpty {let piece=String(remainder.prefix(750));texts.append(piece);remainder=String(remainder.dropFirst(piece.count))}
  let prefix="bank:"+String(PlotMemoryStore.key(progressKey+progress.roundID+q.id).prefix(32))+":"
  return texts.enumerated().map{FilmBankRevealPart(id:prefix+String($0.offset),text:"剧情题库揭晓（\($0.offset+1)/\(texts.count)）\n"+$0.element)}
 }
 func acknowledgeReveal(_ id:String) {
  guard let bank=active else{return}
  for q in bank.questions where progress.published.contains(q.id) && !progress.revealed.contains(q.id) {
   let messages=parts(q)
   guard messages.contains(where:{$0.id==id}) else{continue}
   progress.delivered.insert(id);sendingParts.remove(id)
   if messages.allSatisfy({progress.delivered.contains($0.id)}) {progress.revealed.insert(q.id)}
   let write=persist();Task {do{try await write.value}catch{self.status="揭晓记录保存失败；下次连接会使用相同消息ID安全重试"}}
   break
  }
 }
 func reconnected() {sendingParts.removeAll()}
 func tick(filmKey:String?,positionMs:Double,durationMs:Double,canPublish:Bool,canReveal:Bool=true,revealPositionMs:Double?=nil,subtitleShown:Bool=false,captionSequence:Int=0,publish:@escaping(PlotQuestion)->Void,reveal:(FilmBankRevealPart)->Void={_ in}) {
  guard let bank=active,key==filmKey,FilmBankCodec.matches(bank,playbackDuration:durationMs),positionMs.isFinite,positionMs>=0 else{lastPositionMs=nil;return}
  defer{lastPositionMs=positionMs}
  if canReveal {
   for q in bank.questions where progress.published.contains(q.id) && !progress.revealed.contains(q.id) {
    guard let when=q.revealAtMs,min(positionMs,revealPositionMs ?? positionMs)>=Double(when),let index=q.answerIndex else{continue}
    let description="\(q.question)\n正确答案：\(q.options[index])\n\(q.explanation)"
    if revealedAnswer != description {revealedAnswer=description}
    for message in parts(q) where !progress.delivered.contains(message.id) && !sendingParts.contains(message.id) {
     sendingParts.insert(message.id);reveal(message)
    }
   }
  }
  guard let previous=lastPositionMs else{return}
  if positionMs<previous || positionMs-previous>3500 {pendingQuestion=nil;pendingSubtitleSequence=nil;return}
  if pendingQuestion==nil,positionMs>previous {
   // At most the newest crossed question; never batch skipped old questions.
   pendingQuestion=bank.questions.filter{!progress.published.contains($0.id) && Double($0.triggerAtMs)>previous && Double($0.triggerAtMs)<=positionMs}.max{$0.triggerAtMs<$1.triggerAtMs}
   pendingSubtitleSequence=subtitleShown ? captionSequence : nil
  }
  guard let next=pendingQuestion else{return}
  guard positionMs-Double(next.triggerAtMs)<=20_000, next.revealAtMs.map({positionMs<Double($0)}) ?? true else{pendingQuestion=nil;pendingSubtitleSequence=nil;status="该题时机已过，已跳过旧题";return}
  let sentenceEnded=pendingSubtitleSequence.map{$0 != captionSequence || !subtitleShown} ?? !subtitleShown
  guard canPublish,sentenceEnded else{return}
  pendingQuestion=nil;pendingSubtitleSequence=nil;progress.published.insert(next.id);publishedCount=progress.published.count
  let token=generation,write=persist()
  publishing=Task {[weak self] in
   do {
    try await write.value
    guard let self,self.generation==token,self.active != nil else{return}
    publish(FilmBankCodec.question(next,blocking:true));self.status="已推送 \(self.publishedCount)/\(bank.questions.count) 道题；答完后继续"
   } catch {self?.status="题目进度保存失败，未自动发布："+error.localizedDescription}
  }
 }
 #if DEBUG
 func waitForRestore() async {await restoring?.value}
 func waitForProgress() async {await publishing?.value;try? await progressWrite?.value}
 #endif
 deinit {restoring?.cancel();fingerprinting?.cancel()}
}
