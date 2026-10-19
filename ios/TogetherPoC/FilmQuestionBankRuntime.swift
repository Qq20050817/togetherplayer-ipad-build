import Foundation
import Combine

// Host-only bank and answer keys. Existing server polls contain public fields
// only; delayed, idempotent chat messages carry answers after the reveal time.
@MainActor final class FilmQuestionBankRuntime:ObservableObject {
 @Published private(set) var active:FilmQuestionBank?
 @Published private(set) var status="当前影片未导入题库"
 @Published private(set) var revealedAnswer=""
 @Published private(set) var finalReport=""
 @Published private(set) var recapReopenToken=UUID()
 @Published private(set) var publishedCount=0
 @Published private(set) var completedCount=0
 @Published private(set) var importing=false
 var onBankReady:(()->Void)?
 #if DEBUG
 var onFullFingerprint:(()->Void)?
 var onCandidateFingerprint:(()->Void)?
 #endif
 private let store:FilmQuestionBankStore
 private let progressStore:FilmBankProgressStore
 private let uptimeNow:()->TimeInterval
 init(store:FilmQuestionBankStore=FilmQuestionBankStore(),progressStore:FilmBankProgressStore=FilmBankProgressStore(),uptimeNow:@escaping()->TimeInterval={ProcessInfo.processInfo.systemUptime}) {self.store=store;self.progressStore=progressStore;self.uptimeNow=uptimeNow}
 private var key="",progressKey=""
 private var sourceURL:URL?
 private var generation=0
 private var restoring:Task<Void,Never>?
 private var fingerprinting:Task<String,Error>?
 private var importWorker:Task<(FilmQuestionBank,String,String),Error>?
 private var lastPositionMs:Double?
 private var progress=FilmBankProgress()
 private var pendingQuestion:FilmBankQuestion?
 private var sendingParts=Set<String>()
 private var pendingSubtitleSequence:Int?
 private var progressWrite:Task<Void,Error>?
 private var publishing:Task<Void,Never>?
 private var continuousPlaybackSince:TimeInterval?
 private var narrativeEndArmed=false
 private var nativeEndArmed=false
 private var narrativePauseRequested=false
 private var continuousPlaybackProven=false
 var storyEndAtMs:Int? {progress.storyEndOverrideMs ?? active?.storyEndMs}
 func playbackJumped() {continuousPlaybackSince=nil;continuousPlaybackProven=false;narrativeEndArmed=false;nativeEndArmed=false;if progress.finalText==nil {narrativePauseRequested=false}}
 func reopenFinalReport() {if !finalReport.isEmpty {recapReopenToken=UUID()}}
 func setStoryEnd(at positionMs:Double) {
  guard let bank=active,positionMs.isFinite else{return}
  let value=Int(positionMs.rounded())
  let lastReveal=bank.questions.map{max($0.triggerAtMs,$0.revealAtMs ?? 0)}.max() ?? 0
  guard value>=max(60_000,lastReveal),value<=bank.durationMs else {
   status="剧情结束点必须在全部题目揭晓之后，且不得超过原片时长。";return
  }
  progress.storyEndOverrideMs=value
  playbackJumped();narrativePauseRequested=false
  let write=persist();Task {try? await write.value}
  status="当前片源剧情结束点：\(FilmStoryEndTime.display(value))。\(progress.finalText == nil ? "正常播放至此自动结算。" : "下轮观影将使用此时间。")"
 }
 // Explicit recovery for someone who has already watched the ending. This is
 // strictly local; answers still wait for a verified guest-safe timeline.
 func finishAlreadyViewed(filmKey:String?,positionMs:Double,durationMs:Double,participantNames:[String:String]=[:]) {
  guard let bank=active,key==filmKey,FilmBankCodec.matches(bank,playbackDuration:durationMs),
   positionMs.isFinite else {status="当前片源与题库尚未完成核对，无法补结算";return}
  let threshold=Double(storyEndAtMs ?? bank.durationMs)-2500
  guard positionMs>=threshold else {status="请先播放至剧情结尾点，再手动补结算";return}
  guard !progress.published.isEmpty || bank.filmReview != nil else {status="本题库缺少已发布题目及全片复盘，无法生成结算";return}
  if progress.finalText==nil {
   let text=completedReport(bank,names:participantNames)
   progress.finalText=text;finalReport=text
   let write=persist();Task {try? await write.value}
   status="已在本机补生成片尾分析；等双方进度同步后再向好友公布答案"
  } else {reopenFinalReport()}
 }
 func restoreStoryEndSuggestion() {
  guard active != nil else{return}
  progress.storyEndOverrideMs=nil;playbackJumped();narrativePauseRequested=false
  let write=persist();Task {try? await write.value}
  status=storyEndAtMs == nil ? "已使用影片实际播放结束点" : "已恢复题库剧情结束点"
 }

 private func activate(_ bank:FilmQuestionBank,token:Int) async {
  let identity=FilmBankCodec.identity(bank)
  try? await progressWrite?.value
  let saved=await progressStore.load(identity)
  guard generation==token,!Task.isCancelled else{return}
  progressKey=identity;progress=saved;publishedCount=saved.published.count;completedCount=saved.answered.count
  finalReport=saved.finalText ?? ""
  active=bank;onBankReady?()
  status="已加载 \(bank.questions.count) 道题 · 本轮已发布 \(publishedCount) 道 · 播放时不请求 AI"
  if bank.filmReview == nil {status += " · ⚠️ 旧题库缺少片尾全片解读，建议重新制作含 filmReview 的题库"}
 }
 func restore(filmKey:String,source:URL,durationMs:Double) {
  if key==filmKey,sourceURL==source,(active != nil || restoring != nil) {return}
  importWorker?.cancel();importWorker=nil;importing=false
  active=nil;playbackJumped();narrativePauseRequested=false;key=filmKey;sourceURL=source;lastPositionMs=nil;pendingQuestion=nil;pendingSubtitleSequence=nil;sendingParts=[];revealedAnswer="";finalReport=""
  generation+=1;let token=generation
  restoring?.cancel();fingerprinting?.cancel();publishing?.cancel()
  guard source.isFileURL || ["http","https"].contains(source.scheme?.lowercased() ?? "") else {status="无法校验当前片源，题库自动提问未启用";return}
  status=source.isFileURL ? "正在校验本地原片指纹和已保存题库…" : "正在分段校验 U 盘 HTTP 原片和已保存题库…"
  #if DEBUG
  onCandidateFingerprint?()
  #endif
  let job=Task.detached(priority:.utility){() async throws->String in
   let access=source.startAccessingSecurityScopedResource();defer{if access {source.stopAccessingSecurityScopedResource()}}
   return source.isFileURL ? try FilmMaterialFingerprint.candidate(source) : try await FilmMaterialFingerprint.remoteAsync(source)
  }
  fingerprinting=job
  restoring=Task {[weak self] in
   guard let self else{return}
   defer{if generation==token {restoring=nil;fingerprinting=nil}}
   do {
    let candidate=try await job.value
    guard generation==token,!Task.isCancelled else{return}
    let indexed=await store.loadCandidate(candidate)
    let legacy:FilmQuestionBank?
    if indexed==nil {legacy=await store.load(filmKey:filmKey)} else {legacy=nil}
    guard generation==token,!Task.isCancelled else{return}
    guard let bank=indexed ?? legacy else{status="当前原片尚无题库；可制作素材或导入 JSON";return}
    guard generation==token,!Task.isCancelled else{return}
    #if DEBUG
    onFullFingerprint?()
    #endif
    let full=Task.detached(priority:.utility){() async throws->String in
     let access=source.startAccessingSecurityScopedResource();defer{if access {source.stopAccessingSecurityScopedResource()}}
     return source.isFileURL ? try FilmMaterialFingerprint.source(source) : try await FilmMaterialFingerprint.remoteAsync(source)
    }
    fingerprinting=full
    let fingerprint=try await full.value
    guard generation==token,!Task.isCancelled else{return}
    guard bank.sourceFingerprint?.lowercased()==fingerprint.lowercased() else{status="旧题库原片指纹不匹配，请重新导出素材制作题库";return}
    guard durationMs<=0 || FilmBankCodec.matches(bank,playbackDuration:durationMs) else{status="题库与电影时长不匹配，自动提问未启用";return}
    if indexed==nil {try await store.saveForSource(bank,candidate:candidate)}
    await activate(bank,token:token)
   } catch {if generation==token {status="原片校验失败："+error.localizedDescription}}
  }
 }

 func importFile(_ url:URL,filmKey:String?,source:URL?,durationMs:Double) async {
  await importPrepared(filmKey:filmKey,source:source,durationMs:durationMs,read:{try FilmBankDocumentReader.read(url)})
 }
 func importDocument(_ document:SelectedFilmBankDocument,filmKey:String?,source:URL?,durationMs:Double) async {
  await importPrepared(filmKey:filmKey,source:source,durationMs:durationMs,read:{document.data})
 }
 private func importPrepared(filmKey:String?,source:URL?,durationMs:Double,read:@escaping()throws->Data) async {
  guard let filmKey,!filmKey.isEmpty,let source,(source.isFileURL || ["http","https"].contains(source.scheme?.lowercased() ?? "")),key==filmKey,sourceURL==source else {status="请先加载本地或 U 盘 HTTP 原片，再导入题库";return}
  guard !importing else{return}
  importing=true;let token=generation
  defer{if generation==token {importing=false;importWorker=nil}}
  status=source.isFileURL ? "正在校验 Schema、完整原片 SHA256 与时间轴…" : "正在校验 Schema、U 盘分段指纹与时间轴…"
  do {
   let worker=Task.detached(priority:.utility){() async throws->(FilmQuestionBank,String,String) in
    let data=try read(),bank=try FilmBankCodec.decode(data)
    try FilmBankCodec.requireCompleteReviewForImport(bank)
    let scoped=source.startAccessingSecurityScopedResource();defer{if scoped {source.stopAccessingSecurityScopedResource()}}
    let report:(Double)->Void={[weak self] value in
     Task {@MainActor in
      guard let self,self.generation==token,self.importing else{return}
      self.status="JSON 已读取，正在核对原片 \(Int(value*100))%…"
     }
    }
    let fingerprint:String,candidate:String
    if source.isFileURL {
     fingerprint=try FilmMaterialFingerprint.source(source,progress:report)
     candidate=try FilmMaterialFingerprint.candidate(source)
    } else {
     fingerprint=try await FilmMaterialFingerprint.remoteAsync(source,progress:report)
     candidate=fingerprint // Remote candidate and strict-range identity are identical.
    }
    return (bank,fingerprint,candidate)
   }
   importWorker=worker
   let result=try await worker.value
   guard generation==token,key==filmKey,sourceURL==source else{return}
   let (bank,fingerprint,candidate)=result
   guard bank.sourceFingerprint?.lowercased()==fingerprint.lowercased() else{status="原片指纹不匹配，未加载。请用当前原片导出的素材制作题库。";return}
   guard FilmBankCodec.matches(bank,playbackDuration:durationMs) else{status="影片时长/剪辑版本不匹配，未加载题库。";return}
   try await store.saveForSource(bank,candidate:candidate)
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
  guard active != nil,!importing else{return}
  generation+=1;publishing?.cancel()
  let savedStoryEnd=progress.storyEndOverrideMs
  progress=FilmBankProgress(revision:progress.revision+1);progress.storyEndOverrideMs=savedStoryEnd
  playbackJumped();narrativePauseRequested=false;publishedCount=0;completedCount=0;revealedAnswer="";finalReport="";lastPositionMs=nil;pendingQuestion=nil;sendingParts=[]
  let write=persist();Task {do{try await write.value}catch{self.status="本轮记录保存失败："+error.localizedDescription}}
  status="已开始新一轮，题库保留；从实际播放进度触发"
 }
 func observePoll(_ poll:[String:Any]?) {
  guard let bank=active,let poll,let publicID=poll["id"] as? String,
   let text=poll["question"] as? String,let options=poll["options"] as? [String],
   let q=bank.questions.first(where:{$0.question==text && $0.options==options}),
   progress.published.contains(q.id) else{return}
  if poll["revealed"] as? Bool != true {
   // Bind only a fresh unanswered poll. A replayed completed snapshot from
   // the previous viewing round must not complete the new round's question.
   guard progress.publicPollIDs[q.id]==nil else{return}
   progress.publicPollIDs[q.id]=publicID
  } else {
   guard progress.publicPollIDs[q.id]==publicID else{return}
   if progress.answered.contains(q.id) && progress.votes[q.id] != nil {return}
   progress.answered.insert(q.id);completedCount=progress.answered.count
   if let answers=poll["answers"] as? [String:String] {progress.votes[q.id]=answers}
  }
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

 private func completedReport(_ bank:FilmQuestionBank,names:[String:String])->String {
  let ordered=bank.questions.filter{progress.published.contains($0.id)}.sorted{$0.triggerAtMs<$1.triggerAtMs}
  var lines=["🎬 电影观影结算 · "+bank.title,
   "本轮发题 \(ordered.count) 道，完成 \(progress.answered.count) 道。"]
  var scores:[String:(right:Int,graded:Int)]=[:]
  for (number,q) in ordered.enumerated() {
   lines.append("\n第\(number+1)题："+q.question)
   let answers=progress.votes[q.id] ?? [:]
   if answers.isEmpty {lines.append("本题没有保存到双方的提交内容。")}
   for user in answers.keys.sorted() {
    let submitted=answers[user] ?? ""
    let player=names[user] ?? "玩家 "+String(user.prefix(6))
    var verdict=""
    if let correct=q.answerIndex,q.options.indices.contains(correct) {
     if q.options.contains(where:{PlotQuality.normalized($0)==PlotQuality.normalized(submitted)}) {
      var tally=scores[user] ?? (right:0,graded:0);tally.graded+=1
      if PlotQuality.normalized(submitted)==PlotQuality.normalized(q.options[correct]) {tally.right+=1;verdict=" ✓"} else {verdict=" ✗"}
      scores[user]=tally
     } else {verdict="（自由回答，不自动评分）"}
    }
    lines.append(player+"："+submitted+verdict)
   }
   if let correct=q.answerIndex,q.options.indices.contains(correct) {
    lines.append("正确答案："+q.options[correct])
   } else {lines.append("开放讨论题，无唯一标准答案。")}
   for item in q.revealEvidence.prefix(3) {
    lines.append("关键证据："+String(item.text.prefix(180)))
   }
   if !q.explanation.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {
    lines.append("剧情解析："+q.explanation)
   }
  }
  if !scores.isEmpty {
   lines.insert("成绩："+scores.keys.sorted().map{user in
    let score=scores[user]!
    return (names[user] ?? "玩家 "+String(user.prefix(6)))+" \(score.right)/\(score.graded)"
   }.joined(separator:" · "),at:2)
  }
  lines.append("\n本轮答案与解析已统一公布，回看进度不会重新结算。")
  if let review=bank.filmReview {
   lines.append("\n🎞 全片复盘")
   for (number,beat) in review.plotBeats.enumerated() {
    lines.append("剧情节点：\(number+1)｜"+beat.title+"｜"+beat.detail)
   }
   for character in review.characters {lines.append("人物关系："+character.name+"｜"+character.role)}
   lines.append("主题解读："+review.theme)
   lines.append("观后讨论："+review.discussion)
  }
  return lines.joined(separator:"\n")
 }
 private func finalParts(_ text:String)->[FilmBankRevealPart] {
  var rest=text,sections:[String]=[]
  while !rest.isEmpty {
   let section=String(rest.prefix(700));sections.append(section);rest=String(rest.dropFirst(section.count))
  }
  let prefix="bank-final:"+String(PlotMemoryStore.key(progressKey+progress.roundID).prefix(32))+":"
  return sections.enumerated().map{FilmBankRevealPart(id:prefix+String($0.offset),text:"🎬 片尾结算（\($0.offset+1)/\(sections.count)）\n"+$0.element)}
 }

 func acknowledgeReveal(_ id:String) {
  guard let bank=active else{return}
  if let text=progress.finalText {
   let messages=finalParts(text)
   if messages.contains(where:{$0.id==id}) {
    progress.delivered.insert(id);sendingParts.remove(id)
    if messages.allSatisfy({progress.delivered.contains($0.id)}) {progress.finalDelivered=true}
    let write=persist();Task {try? await write.value}
    return
   }
  }
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
 func tick(filmKey:String?,positionMs:Double,durationMs:Double,canPublish:Bool,canReveal:Bool=true,revealPositionMs:Double?=nil,naturalEnd:Bool=false,canFinish:Bool=false,pauseAtStoryEnd:@escaping()->Void={},participantNames:[String:String]=[:],subtitleShown:Bool=false,captionSequence:Int=0,publish:@escaping(PlotQuestion)->Void,reveal:(FilmBankRevealPart)->Void={_ in}) {
  guard let bank=active,key==filmKey,positionMs.isFinite,positionMs>=0 else{lastPositionMs=nil;return}
  guard durationMs.isFinite,durationMs>0 else{lastPositionMs=nil;return}
  guard FilmBankCodec.matches(bank,playbackDuration:durationMs) else{active=nil;pendingQuestion=nil;lastPositionMs=nil;status="题库与播放器确认的原片时长不匹配，自动提问已停止";return}
  defer{lastPositionMs=positionMs}
  // A verified story-end timestamp allows recap before credits. Require
  // sustained natural playback to prevent a SEEK to the finale from leaking
  // spoiler answers. A real native playback end remains the legacy fallback.
  let uptime=uptimeNow()
  let continuity=lastPositionMs.map{positionMs>=$0 && positionMs-$0<=3500} ?? false
  // A time jump invalidates proof of naturally watching the ending. Ordinary
  // socket/VM reconnects must not erase proof already earned while playing.
  if lastPositionMs != nil && !continuity &&
      (positionMs < (lastPositionMs ?? 0) || positionMs - (lastPositionMs ?? 0) > 3500) {
   continuousPlaybackSince=nil;continuousPlaybackProven=false
   narrativeEndArmed=false;nativeEndArmed=false
  }
  let nativeHadContinuousPlayback=continuousPlaybackProven || continuousPlaybackSince.map{uptime-$0>=8} == true
  if naturalEnd && nativeHadContinuousPlayback {nativeEndArmed=true}
  if canFinish && continuity {
   if continuousPlaybackSince==nil {continuousPlaybackSince=uptime}
   if uptime-(continuousPlaybackSince ?? uptime)>=8 {continuousPlaybackProven=true}
  } else {continuousPlaybackSince=nil}
  if let end=storyEndAtMs,
     canFinish,continuity,let previous=lastPositionMs,
     previous<Double(end),positionMs>=Double(end),
     uptime-(continuousPlaybackSince ?? .infinity)>=8 {
   narrativeEndArmed=true
  }
  let endMs=Double(storyEndAtMs ?? bank.durationMs)
  let nearEnding=min(positionMs,revealPositionMs ?? 0)>=endMs-2500
  // A confirmed native end is local evidence even when a restarted server
  // still reports an old room anchor. Keep guest answers hidden until the
  // canonical room/peer timeline catches up.
  let naturalLocalFinish=(nativeEndArmed ||
    (continuousPlaybackProven && canFinish && continuity && positionMs>=Double(bank.durationMs)-500)) &&
    positionMs>=Double(bank.durationMs)-2500
  let narrativeLocalFinish=narrativeEndArmed && storyEndAtMs != nil && positionMs>=endMs-2500
  let narrativeFinished=narrativeLocalFinish && nearEnding
  if narrativeFinished && !narrativePauseRequested && canReveal {
   narrativePauseRequested=true
   pauseAtStoryEnd()
  }
  if (naturalLocalFinish || narrativeLocalFinish) && (!progress.published.isEmpty || bank.filmReview != nil) {
   if progress.finalText==nil {
    let text=completedReport(bank,names:participantNames)
    progress.finalText=text
    finalReport=text
    let write=persist()
    Task {try? await write.value}
   }
  }
  // Delivery retries are independent from playback. If the app was killed or
  // the socket dropped after the finale, restore and send missing segments
  // without forcing viewers to watch the final scene again.
  if canReveal,nearEnding,let text=progress.finalText,!progress.finalDelivered {
   // Keep the socket outbox small for full-length explanations. Each ack
   // frees a slot for more sections on the next playback/connection tick.
   for message in finalParts(text) where !progress.delivered.contains(message.id) && !sendingParts.contains(message.id) {
    if sendingParts.count>=8 {break}
    sendingParts.insert(message.id);reveal(message)
   }
  }
  // Individual answer keys remain on the host until the final narrative
  // recap. Intermediate room poll state can reveal players' guesses only.
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
 deinit {restoring?.cancel();fingerprinting?.cancel();importWorker?.cancel()}
}

// Bank-provided storyEndMs is only a suggestion. A film-specific user correction
// is stored with the verified bank identity and can be entered as HH:MM:SS.
enum FilmStoryEndTime {
 static func parse(_ input:String)->Double? {
  let fields=input.trimmingCharacters(in:.whitespacesAndNewlines).split(separator:":",omittingEmptySubsequences:false)
  let parts=fields.compactMap{Int($0)}
  guard fields.count==2 || fields.count==3,
   fields.allSatisfy({!$0.isEmpty && $0.allSatisfy({$0 >= "0" && $0 <= "9"})}),
   parts.count==fields.count,
   let seconds=parts.last,seconds<60 else{return nil}
  if fields.count==3 && parts[1]>=60 {return nil}
  let total=fields.count==3 ? (Double(parts[0])*3600+Double(parts[1])*60+Double(seconds)) : (Double(parts[0])*60+Double(seconds))
  return total.isFinite && total>0 && total<=43200 ? total*1000 : nil
 }
 static func display(_ value:Int)->String {
  let sec=value/1000
  return String(format:"%02d:%02d:%02d",sec/3600,(sec/60)%60,sec%60)
 }
}
