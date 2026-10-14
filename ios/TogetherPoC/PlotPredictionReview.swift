import Foundation

// No predicted "correct answer" is stored when creating a question. The
// adjudicator receives ONLY dialogue actually observed after the poll, and
// abstains unless cited future evidence decisively supports one choice.
enum PlotPredictionQuality {
 static let vague=["无法判断","暂时不知道","信息不足","可能误会","有人隐瞒","还有线索","不确定","不清楚","无法确定","都有可能"]
 static func isVague(_ text:String)->Bool {vague.contains(where:text.contains)}
}
struct PlotPendingReview {
 let id:String
 let roomId:String
 let mediaId:String
 let at:Double
 let question:String
 let choices:[String]
 let answers:[String:String]
 var isReady:Bool {choices.count>=2 && choices.count<=4 && !answers.isEmpty && at.isFinite && at>=0}
 func canReview(position:Double)->Bool {isReady && position>=at+180 && position<=at+480}
 func observed(_ values:[PlotEvidence],position:Double)->[PlotEvidence] {
  Array(values.filter{$0.source != "ondevice-vision" && $0.start>=at && $0.end<=position && $0.end<=at+480}.suffix(25))
 }
}
struct PlotPredictionVerdict {
 let index:Int
 let evidenceID:String
 let confidence:Double
 static func parse(_ text:String,choices:[String],observed:[PlotEvidence])->Self? {
  guard let data=PlotJSON.object(text),
   let object=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any],
   let index=object["index"] as? Int,index>=0,index<choices.count,
   let confidence=object["confidence"] as? Double,confidence>=0.8,confidence<=1,
   let id=object["evidenceID"] as? String,observed.contains(where:{$0.id==id}) else{return nil}
  return Self(index:index,evidenceID:id,confidence:confidence)
 }
 static func message(_ verdict:Self,review:PlotPendingReview,members:[RoomMember])->String {
  let correct=review.choices[verdict.index]
  let votes=review.answers.sorted{$0.key<$1.key}.map {id,vote in
   let name=members.first(where:{$0.userId==id})?.name ?? "观众"
   let selected=vote.trimmingCharacters(in:.whitespacesAndNewlines)
   return "\(name)：\(selected == correct ? "🎯 猜中" : "🔎 未猜中")（\(String(selected.prefix(22)))）"
  }
  return "🎬 剧情预测回顾：\(String(review.question.prefix(60)))\n已播放的后续字幕支持：\(correct)\n\(votes.joined(separator:"；"))\n仅依据已观看字幕核对，未揭晓更后面的剧情。"
 }
}
@MainActor enum PlotFutureJudge {
 static func evaluate(_ review:PlotPendingReview,evidence:[PlotEvidence]) async -> PlotPredictionVerdict? {
  guard PlotLocalAI.available,evidence.count>=3 else{return nil}
  let ids=Set(evidence.map(\.id))
  guard ids.count>=3 else{return nil}
  let data:[String:Any]=[
   "question":review.question,"options":review.choices,
   "alreadyWatchedAfterPrediction":evidence.suffix(20).map{["id":$0.id,"text":String($0.text.prefix(160))]}
  ]
  guard let json=try? JSONSerialization.data(withJSONObject:data),let input=String(data:json,encoding:.utf8) else{return nil}
  let prompt=#"你只负责预测题的赛后裁判。问题和选项由过去的观众预测产生，输入只有此刻已经实际观看过的后续字幕。不得使用外部电影知识或更后面的剧情。只有当提供的已播放字幕【明确证实】恰好某一个候选走向，而且能引用证明它的原始字幕id时，返回JSON {index:选项的0起始下标,confidence:0到1,evidenceID:真实字幕id}。只有疑似、间接猜测、多项都可能或没有充分证据，则必须输出 {index:-1,confidence:0,evidenceID:""}。不能依据选项写入剧情，不可剧透。"#
  guard let text=try? await PlotLocalAI.respond(instructions:prompt,input:input) else{return nil}
  return PlotPredictionVerdict.parse(text,choices:review.choices,observed:evidence)
 }
}
