import Foundation
import Combine

// iPad is the sole keeper of imported question-bank answer keys. Android and
// the server only see normal PLOT_POLL_CREATE payloads at the approved time.
@MainActor final class FilmQuestionBankRuntime:ObservableObject {
 @Published private(set) var active:FilmQuestionBank?
 @Published private(set) var status="当前影片未导入题库"
 @Published private(set) var revealedAnswer=""
 private let store=FilmQuestionBankStore()
 private var key=""
 private var sourceURL:URL?
 private var generation=0
 private var restoring:Task<Void,Never>?
 private var lastPositionMs:Double?
 private var published=Set<String>()
 private var revealed=Set<String>()
 var publishedCount:Int {published.count}

 func restore(filmKey:String,source:URL,durationMs:Double) {
  let newFilm=key != filmKey || sourceURL != source
  // Never run a previously approved bank against a new decoder source before
  // its independent fingerprint and duration checks have completed.
  active=nil
  if newFilm {published=[];revealed=[];revealedAnswer=""}
  key=filmKey;sourceURL=source;lastPositionMs=nil
  generation += 1
  let token=generation
  restoring?.cancel()
  restoring=Task {[weak self] in
   guard let self else{return}
   guard let bank=await store.load(filmKey:filmKey) else {
    if generation==token {active=nil;status="当前电影尚无已导入题库"}
    return
   }
   guard let expected=bank.sourceFingerprint,!expected.isEmpty,source.isFileURL else {
    if generation==token {active=nil;status="无法校验原片指纹，已禁用自动出题"}
    return
   }
   let current=try? await Task.detached(priority:.utility){() throws->String in
    let access=source.startAccessingSecurityScopedResource()
    defer {if access {source.stopAccessingSecurityScopedResource()}}
    return try FilmMaterialFingerprint.source(source)
   }.value
   guard !Task.isCancelled,generation==token else{return}
   guard current?.lowercased()==expected.lowercased() else {
    active=nil;status="题库与当前影片文件不匹配，已禁用自动出题";return
   }
   if durationMs>0 && !FilmBankCodec.matches(bank,playbackDuration:durationMs) {
    active=nil;status="题库与影片时长不匹配，已禁用自动出题";return
   }
   active=bank;status="已自动读取 \(bank.questions.count) 道题；播放时无需调用 AI"
  }
 }

 func importFile(_ url:URL,filmKey:String?,source:URL?,durationMs:Double) async {
  guard let filmKey,!filmKey.isEmpty,let source,source.isFileURL else {
   status="请先加载本地原片，再导入题库";return
  }
  status="正在校验 JSON、原片指纹和影片时长…"
  do {
   let (bank,actual)=try await Task.detached(priority:.userInitiated){() throws->(FilmQuestionBank,String) in
    let access=url.startAccessingSecurityScopedResource()
    defer {if access {url.stopAccessingSecurityScopedResource()}}
    let handle=try FileHandle(forReadingFrom:url)
    defer {try? handle.close()}
    let data=try handle.read(upToCount:FilmBankCodec.maxBytes+1) ?? Data()
    let parsed=try FilmBankCodec.decode(data)
    let scope=source.startAccessingSecurityScopedResource()
    defer {if scope {source.stopAccessingSecurityScopedResource()}}
    return (parsed,try FilmMaterialFingerprint.source(source))
   }.value
   guard key==filmKey,sourceURL==source else {
    status="导入时切换了电影，请重新导入当前电影题库";return
   }
   guard let expected=bank.sourceFingerprint,!expected.isEmpty,expected.lowercased()==actual.lowercased() else {
    status="题库指纹与当前原片不符；必须使用这部电影导出的素材生成题库";return
   }
   guard durationMs>0,FilmBankCodec.matches(bank,playbackDuration:durationMs) else {
    status="题库时长或剪辑版本不匹配，请核对完整原片";return
   }
   try await store.save(bank,filmKey:filmKey)
   generation+=1;restoring?.cancel()
   active=bank;published=[];revealed=[];lastPositionMs=nil;revealedAnswer=""
   status="题库已保存：\(bank.questions.count) 道题。播放到节点时自动提问。"
  } catch {status="导入失败："+error.localizedDescription}
 }

 func tick(filmKey:String?,positionMs:Double,durationMs:Double,canPublish:Bool,publish:(PlotQuestion)->Void,reveal:(String)->Void={_ in}) {
  guard let bank=active,key==filmKey,
   FilmBankCodec.matches(bank,playbackDuration:durationMs),
   positionMs.isFinite,positionMs>=0 else {lastPositionMs=nil;return}
  defer {lastPositionMs=positionMs}
  // Reveal only previously posted questions and only after proof time.
  for q in bank.questions where published.contains(q.id) && !revealed.contains(q.id) {
   guard let when=q.revealAtMs,positionMs>=Double(when) else{continue}
   revealed.insert(q.id)
   if let index=q.answerIndex,q.options.indices.contains(index) {
    revealedAnswer="\(q.question)\n正确答案：\(q.options[index])\n\(q.explanation)"
    reveal(String(("剧情题库答案揭晓："+revealedAnswer).prefix(490)))
   }
  }
  // Skipped sections, seeks and reconnect jumps must NOT inject stale polls.
  guard let previous=lastPositionMs,positionMs>previous,positionMs-previous<=3500,
    canPublish else{return}
  guard let next=bank.questions.first(where:{
   !published.contains($0.id) && Double($0.triggerAtMs)>previous && Double($0.triggerAtMs)<=positionMs
  }) else{return}
  published.insert(next.id)
  publish(FilmBankCodec.question(next,blocking:true))
  status="已推送 \(published.count)/\(bank.questions.count) 道题；双方回答后继续观影"
 }
}
