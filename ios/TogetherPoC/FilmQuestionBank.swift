import Foundation
import CryptoKit

// TogetherPlayer question-bank v1. Correct answers and future scene details
// are private local data and MUST NOT be sent in PLOT_POLL_CREATE.
struct FilmBankEvidence:Codable,Equatable {
 let kind:String
 let startMs:Int
 let endMs:Int
 let text:String
}

struct FilmBankQuestion:Codable,Equatable,Identifiable {
 let id:String
 let triggerAtMs:Int
 let revealAtMs:Int?
 let type:String
 let question:String
 let options:[String]
 let answerIndex:Int?
 let evidence:[FilmBankEvidence]
 let revealEvidence:[FilmBankEvidence]
 let explanation:String
 let confidence:Double
 let qualityScore:Int
}

struct FilmQuestionBank:Codable,Equatable {
 let schemaVersion:Int
 let title:String
 let year:Int?
 let edition:String?
 let durationMs:Int
 let sourceFingerprint:String?
 let subtitleFingerprint:String?
 let questions:[FilmBankQuestion]
}

enum FilmBankValidation:LocalizedError {
 case invalidFormat,unsupportedVersion,missingIdentity,invalidTime,invalidQuestion,spoilerUnsafe,duplicate
 case detail(String)
 var errorDescription:String? {switch self {
  case .invalidFormat:return "题库 JSON 无效或文件超过 2MB。"
  case .unsupportedVersion:return "题库格式版本不受支持，当前需要 schemaVersion=1。"
  case .missingIdentity:return "题库未提供足够的影片身份信息。"
  case .invalidTime:return "题库触发/揭晓时间与电影时长不一致。"
  case .invalidQuestion:return "题目、选项、答案或剧情证据格式无效。"
  case .spoilerUnsafe:return "题目包含尚未播放的证据，可能提前剧透。"
  case .duplicate:return "题目编号、内容或触发时间重复。"
  case .detail(let text):return text
 }}
}

enum FilmBankCodec {
 static let maxBytes=2*1024*1024
 static func decode(_ data:Data)throws->FilmQuestionBank {
  guard data.count>0,data.count<=maxBytes,
   let bank=try? JSONDecoder().decode(FilmQuestionBank.self,from:data) else {throw FilmBankValidation.invalidFormat}
  try shape(data)
  try validate(bank)
  return bank
 }
 static func shape(_ data:Data)throws {
  func keys(_ object:[String:Any],required:Set<String>,allowed:Set<String>,path:String)throws {
   let fields=Set(object.keys)
   if let missing=required.subtracting(fields).sorted().first {throw FilmBankValidation.detail(path+" 缺少字段："+missing)}
   if let unknown=fields.subtracting(allowed).sorted().first {throw FilmBankValidation.detail(path+" 存在 Schema 未定义字段："+unknown)}
  }
  guard let root=try JSONSerialization.jsonObject(with:data) as? [String:Any] else{throw FilmBankValidation.invalidFormat}
  try keys(root,required:["schemaVersion","title","durationMs","sourceFingerprint","subtitleFingerprint","questions"],allowed:["schemaVersion","title","year","edition","durationMs","sourceFingerprint","subtitleFingerprint","questions"],path:"题库")
  for (index,q) in ((root["questions"] as? [[String:Any]]) ?? []).enumerated() {
   let fields:Set<String>=["id","triggerAtMs","revealAtMs","type","question","options","answerIndex","evidence","revealEvidence","explanation","confidence","qualityScore"]
   try keys(q,required:fields,allowed:fields,path:"第\(index+1)题")
   for key in ["evidence","revealEvidence"] {
    for evidence in (q[key] as? [[String:Any]]) ?? [] {try keys(evidence,required:["kind","startMs","endMs","text"],allowed:["kind","startMs","endMs","text"],path:"第\(index+1)题 \(key)")}
   }
  }
 }
 static func fingerprintValid(_ text:String?)->Bool {
  guard let text,text.count==64 else{return false}
  return text.allSatisfy{"0123456789abcdefABCDEF".contains($0)}
 }
 static func validate(_ bank:FilmQuestionBank)throws {
  guard bank.schemaVersion==1 else {throw FilmBankValidation.unsupportedVersion}
  guard (1...180).contains(bank.title.count),bank.durationMs>=60_000,
   bank.durationMs<=43_200_000,!bank.questions.isEmpty,bank.questions.count<=30 else {throw FilmBankValidation.missingIdentity}
  guard fingerprintValid(bank.sourceFingerprint),bank.subtitleFingerprint==nil || fingerprintValid(bank.subtitleFingerprint) else{throw FilmBankValidation.detail("sourceFingerprint/subtitleFingerprint 必须是导出素材中的64位SHA256指纹。 ")}
  var ids=Set<String>();var triggers=Set<Int>();var texts=Set<String>()
  for q in bank.questions {
   guard (1...100).contains(q.id.count),ids.insert(q.id).inserted,triggers.insert(q.triggerAtMs).inserted,texts.insert(PlotQuality.normalized(q.question)).inserted else {throw FilmBankValidation.duplicate}
   guard q.triggerAtMs>=0,q.triggerAtMs<bank.durationMs,
    q.revealAtMs == nil || (q.revealAtMs! > q.triggerAtMs && q.revealAtMs! <= bank.durationMs) else {throw FilmBankValidation.invalidTime}
   guard ["prediction","motive","mystery","foreshadowing","twist","timeline","discussion"].contains(q.type),
    (5...200).contains(q.question.trimmingCharacters(in:.whitespacesAndNewlines).count),(2...4).contains(q.options.count),
    q.options.allSatisfy({!$0.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && $0.count<=80}),
    Set(q.options.map{PlotQuality.normalized($0)}).count==q.options.count,q.explanation.count<=1500,
    (0...100).contains(q.qualityScore),q.confidence.isFinite,(0...1).contains(q.confidence),
    q.evidence.count>0,q.evidence.count<=16,q.revealEvidence.count<=16 else {throw FilmBankValidation.invalidQuestion}
   if let index=q.answerIndex {
    guard q.options.indices.contains(index),q.revealAtMs != nil,!q.revealEvidence.isEmpty else {throw FilmBankValidation.invalidQuestion}
   } else if q.revealAtMs != nil || q.type != "discussion" || !q.revealEvidence.isEmpty {throw FilmBankValidation.invalidQuestion}
   for evidence in q.evidence {
    guard evidence.startMs>=0,evidence.endMs>=evidence.startMs,
     evidence.endMs<=q.triggerAtMs,
     (1...350).contains(evidence.text.count),["subtitle","frame"].contains(evidence.kind) else {throw FilmBankValidation.spoilerUnsafe}
   }
   for evidence in q.revealEvidence {
    guard let reveal=q.revealAtMs,evidence.startMs>=q.triggerAtMs,
     evidence.endMs<=reveal,evidence.endMs>=evidence.startMs,
     (1...350).contains(evidence.text.count),["subtitle","frame"].contains(evidence.kind) else {throw FilmBankValidation.spoilerUnsafe}
   }
  }
 }
 static func identity(_ bank:FilmQuestionBank)->String {
  let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
  return PlotMemoryStore.key(String(decoding:(try? encoder.encode(bank)) ?? Data(),as:UTF8.self))
 }
 static func matches(_ bank:FilmQuestionBank,playbackDuration:Double)->Bool {
  guard playbackDuration.isFinite,playbackDuration>0 else{return false}
  // Avoid automatic questions on director's cuts / mismatched subtitle timelines.
  return abs(Double(bank.durationMs)-playbackDuration)<=5000
 }
 static func question(_ entry:FilmBankQuestion,blocking:Bool)->PlotQuestion {
  let kinds:[String:String]=["prediction":"prediction","motive":"motive","mystery":"discussion","foreshadowing":"prediction","twist":"prediction","timeline":"timeline","discussion":"discussion"]
  return PlotQuestion(text:entry.question,choices:entry.options,source:"已导入电影题库",
   evidenceIDs:[],kind:kinds[entry.type] ?? "discussion",blocking:blocking,planningScope:"imported-bank")
 }
}

actor FilmQuestionBankStore {
 private let directory:URL
 init(directory:URL?=nil) {
  let base=directory ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("AIQuestionBanks",isDirectory:true)
  self.directory=base
 }
 private func file(_ key:String)->URL {
  let name=SHA256.hash(data:Data(key.utf8)).map{String(format:"%02x",$0)}.joined()
  return directory.appendingPathComponent(name+".json")
 }
 func load(filmKey:String)->FilmQuestionBank? {
  let url=file(filmKey)
  guard let data=try? Data(contentsOf:url),data.count<=FilmBankCodec.maxBytes else{return nil}
  return try? FilmBankCodec.decode(data)
 }
 func save(_ bank:FilmQuestionBank,filmKey:String)throws {
  try FilmBankCodec.validate(bank)
  try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
  let data=try JSONEncoder().encode(bank)
  guard data.count<=FilmBankCodec.maxBytes else{throw FilmBankValidation.invalidFormat}
  var folder=directory;var attributes=URLResourceValues();attributes.isExcludedFromBackup=true;try? folder.setResourceValues(attributes)
  try data.write(to:file(filmKey),options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
 }
}

extension FilmQuestionBank {
 enum CodingKeys:String,CodingKey {case schemaVersion,title,year,edition,durationMs,sourceFingerprint,subtitleFingerprint,questions}
 func encode(to encoder:Encoder)throws {
  var c=encoder.container(keyedBy:CodingKeys.self)
  try c.encode(schemaVersion,forKey:.schemaVersion);try c.encode(title,forKey:.title)
  try c.encodeIfPresent(year,forKey:.year);try c.encodeIfPresent(edition,forKey:.edition)
  try c.encode(durationMs,forKey:.durationMs);try c.encode(sourceFingerprint,forKey:.sourceFingerprint)
  try c.encode(subtitleFingerprint,forKey:.subtitleFingerprint);try c.encode(questions,forKey:.questions)
 }
}
extension FilmBankQuestion {
 enum CodingKeys:String,CodingKey {case id,triggerAtMs,revealAtMs,type,question,options,answerIndex,evidence,revealEvidence,explanation,confidence,qualityScore}
 func encode(to encoder:Encoder)throws {
  var c=encoder.container(keyedBy:CodingKeys.self)
  try c.encode(id,forKey:.id);try c.encode(triggerAtMs,forKey:.triggerAtMs);try c.encode(revealAtMs,forKey:.revealAtMs)
  try c.encode(type,forKey:.type);try c.encode(question,forKey:.question);try c.encode(options,forKey:.options)
  try c.encode(answerIndex,forKey:.answerIndex);try c.encode(evidence,forKey:.evidence);try c.encode(revealEvidence,forKey:.revealEvidence)
  try c.encode(explanation,forKey:.explanation);try c.encode(confidence,forKey:.confidence);try c.encode(qualityScore,forKey:.qualityScore)
 }
}
