import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

struct PlotQuestion {
 let text:String
 let choices:[String]
 let source:String
}

@MainActor enum PlotPromptMaker {
 // This source never reads future subtitles: caller supplies only the excerpt
 // that precedes the synchronized playback position.
 static func create(excerpt:String) async -> PlotQuestion {
  let safe=String(excerpt.suffix(1700))
  #if canImport(FoundationModels)
  if #available(iOS 26.0, *) {
   if SystemLanguageModel.default.isAvailable && !safe.isEmpty {
    do {
     let session=LanguageModelSession(instructions:"你是双人电影观影助手。只能根据用户已经看过的台词提出一个开放式悬疑/人物动机/后续发展的问题，不能使用外部电影知识，不能透露未播放剧情，不要断定真凶。不认识人物时使用‘这个人’。输出严格的JSON对象，字段question为中文问题，options为2至4项简短中文候选答案。每项不要超过35字，问题不超过90字；选项要中性，允许不知道。")
     let response=try await session.respond(to:"以下是当前进度之前的字幕（未必完整，可能存在误差）：\n\(safe)\n请提出一个观众尚不能确定答案的问题。")
     if let parsed=parse(response.content){return parsed}
    } catch { /* No paid API: simply fall back to a local generic prompt. */ }
   }
  }
  #endif
  return PlotQuestion(text:safe.isEmpty ? "看到这里，你觉得接下来会发生什么？" : "根据刚才已经发生的剧情，你现在最怀疑哪种可能？",
   choices:["有人刻意隐瞒","可能只是误会","还有尚未出现的线索","暂时无法判断"],source:"免费本地题库")
 }
 static func parse(_ source:String)->PlotQuestion? {
  guard let start=source.firstIndex(of:"{"),let end=source.lastIndex(of:"}") else {return nil}
  let segment=String(source[start...end])
  guard let obj=(try? JSONSerialization.jsonObject(with:Data(segment.utf8))) as? [String:Any],
    let question=obj["question"] as? String,
    let raw=obj["options"] as? [String] else {return nil}
  let text=question.trimmingCharacters(in:.whitespacesAndNewlines)
  let choices=Array(raw.map{$0.trimmingCharacters(in:.whitespacesAndNewlines)}.filter{!$0.isEmpty && $0.count<=80}.prefix(4))
  guard text.count>=5 && text.count<=200 && choices.count>=2 else {return nil}
  return PlotQuestion(text:text,choices:choices,source:"Apple 设备端 AI")
 }
}
