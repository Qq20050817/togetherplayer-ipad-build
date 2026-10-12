import Foundation
import CryptoKit

struct PlotEvidence:Codable,Equatable,Identifiable {
 let id:String
 let start:Double
 let end:Double
 let text:String
 let source:String
 var confidence:Double=1
 static func cue(start:Double,end:Double,text:String,source:String)->PlotEvidence {
  let fingerprint="\(start)|\(end)|\(text)|\(source)"
  return PlotEvidence(id:SHA256.hash(data:Data(fingerprint.utf8)).map{String(format:"%02x",$0)}.joined(),start:start,end:end,text:String(text.prefix(600)),source:source)
 }
}
struct PlotClue:Codable,Equatable,Identifiable {
 let id:String
 let kind:String // quote, event, relationship, contradiction, question, inference
 let text:String
 let evidenceIDs:[String]
 let end:Double
 let confidence:Double
}
struct PlotPrediction:Codable,Equatable {
 let id:String
 let end:Double
 let question:String
 let answers:[String:String]
}
struct PlotContext:Codable,Equatable {
 let cutoff:Double
 let recent:[PlotEvidence]
 let earlier:[PlotClue]
 let predictions:[PlotPrediction]
 var sufficient:Bool {recent.count>=3 || earlier.count>=2}
 var evidenceIDs:Set<String> {Set(recent.map(\.id)+earlier.flatMap(\.evidenceIDs))}
 var input:String {
  let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
  return String(data:(try? encoder.encode(self)) ?? Data(),encoding:.utf8) ?? "{}"
 }
}
struct PlotBudget:Codable,Equatable {
 var automatic=0
 var manual=0
 var lastRequest:Double=0
 var failedSegments:Set<Int>=[]
 var total:Int {automatic+manual}
 // Count dispatched requests, including failures, before doing network I/O.
 mutating func reserve(segment:Int,now:Double,manualRequest:Bool,limit:Int=10,interval:Double=180)->Bool {
  guard now-lastRequest>=interval else {return false}
  // A failed automatic attempt must not permanently block an explicit user
  // retry; the shared request interval still prevents rapid repeated calls.
  if !manualRequest && failedSegments.contains(segment) {return false}
  if manualRequest {manual+=1} else {guard automatic<max(0,limit) else {return false};automatic+=1}
  lastRequest=now;return true
 }
}
struct PlotCacheEntry:Codable {
 let segment:Int
 let cutoff:Double
 let question:PlotQuestion
}
struct PlotDecision:Codable {
 let timestamp:Double
 let position:Double
 let mode:String
 let selectedModel:String
 let reason:String
 let complexityScore:Int
 let confidence:Double
 let requests:Int
 let quality:String
 let misjudgmentReview:String
}
struct PlotMemoryState:Codable {
 var evidence:[PlotEvidence]=[]
 var clues:[PlotClue]=[]
 var predictions:[PlotPrediction]=[]
 var budget=PlotBudget()
 var cache:[PlotCacheEntry]=[]
 var questions:[PlotCacheEntry]=[]
 var decisions:[PlotDecision]=[]
 mutating func ingest(_ values:[PlotEvidence],cutoff:Double) {
  guard cutoff.isFinite,cutoff>=0 else {return}
  var seen=Set(evidence.map(\.id))
  for value in values where value.start>=0 && value.end>=value.start && value.end<=cutoff && value.end.isFinite && !value.text.isEmpty {
   if seen.insert(value.id).inserted {evidence.append(value)}
  }
  evidence.sort{$0.end<$1.end};evidence=Array(evidence.suffix(10000))
 }
 func context(at cutoff:Double,recentSeconds:Double=600)->PlotContext {
  guard cutoff.isFinite,cutoff>=0 else {return PlotContext(cutoff:0,recent:[],earlier:[],predictions:[])}
  let allowed=evidence.filter{$0.end<=cutoff}
  let ids=Set(allowed.map(\.id))
  let recent=Array(allowed.filter{$0.end>=cutoff-recentSeconds}.suffix(35))
  let structured=Array(clues.filter{$0.end<=cutoff && Set($0.evidenceIDs).isSubset(of:ids)}.suffix(18))
  // Old dialogue is quoted and attributed, never promoted to established truth.
  let covered=Set(structured.flatMap(\.evidenceIDs))
  let older=Array(allowed.filter{$0.end<cutoff-recentSeconds && !covered.contains($0.id)}.suffix(8)).map {
   PlotClue(id:$0.id,kind:"quote",text:String($0.text.prefix(180)),evidenceIDs:[$0.id],end:$0.end,confidence:1)
  }
  return PlotContext(cutoff:cutoff,recent:recent,earlier:structured+older,predictions:Array(predictions.filter{$0.end<=cutoff}.suffix(5)))
 }
 mutating func addClues(_ new:[PlotClue],context:PlotContext) {
  let ids=context.evidenceIDs
  for clue in new where !clue.evidenceIDs.isEmpty && Set(clue.evidenceIDs).isSubset(of:ids) && clue.end<=context.cutoff && clue.confidence.isFinite && (0...1).contains(clue.confidence) {
   if !clues.contains(where:{$0.id==clue.id}) {clues.append(clue)}
  }
  clues=Array(clues.suffix(120))
 }
 func reusable(at cutoff:Double)->PlotQuestion? {
  cache.last(where:{$0.segment==Int(cutoff/180) && $0.cutoff<=cutoff})?.question
 }
 mutating func remember(_ question:PlotQuestion,at cutoff:Double) {
  let item=PlotCacheEntry(segment:Int(cutoff/180),cutoff:cutoff,question:question)
  cache.removeAll{$0.segment==item.segment};cache.append(item);cache=Array(cache.suffix(100))
  questions.append(item);questions=Array(questions.suffix(100))
 }
}

// Dedicated actor: bounded local storage and snapshots never run on the decoder
// callback or main/UI queue. Hash film identity; do not persist signed URLs.
actor PlotMemoryStore {
 private let directory:URL?
 private var states:[String:PlotMemoryState]=[:]
 init(directory:URL? = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask).first?.appendingPathComponent("PlotMemory")) {self.directory=directory}
 static func key(_ identity:String)->String {SHA256.hash(data:Data(identity.utf8)).map{String(format:"%02x",$0)}.joined()}
 func load(_ key:String)->PlotMemoryState {
  if let state=states[key] {return state}
  let data=directory.flatMap{try? Data(contentsOf:$0.appendingPathComponent(key+".json"))}
  let state=data.flatMap{try? JSONDecoder().decode(PlotMemoryState.self,from:$0)} ?? PlotMemoryState()
  states[key]=state;return state
 }
 func save(_ state:PlotMemoryState,key:String) throws {
  guard let directory else {states[key]=state;return}
  try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
  var protected=directory;var values=URLResourceValues();values.isExcludedFromBackup=true;try? protected.setResourceValues(values)
  let url=directory.appendingPathComponent(key+".json")
  try JSONEncoder().encode(state).write(to:url,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
  states[key]=state
 }
 func ingest(_ evidence:[PlotEvidence],cutoff:Double,key:String,prediction:PlotPrediction?=nil) throws -> PlotMemoryState {
  var state=load(key);state.ingest(evidence,cutoff:cutoff)
  if let prediction,prediction.end<=cutoff {
   if let index=state.predictions.firstIndex(where:{$0.id==prediction.id}) {
    if prediction.end>=state.predictions[index].end {state.predictions[index]=prediction}
   } else {state.predictions.append(prediction)}
   state.predictions=Array(state.predictions.suffix(100))
  }
  try save(state,key:key);return state
 }
 func reserve(key:String,segment:Int,manual:Bool,limit:Int,interval:Double,now:Double=Date().timeIntervalSince1970) throws -> Bool {
  var state=load(key)
  guard state.budget.reserve(segment:segment,now:now,manualRequest:manual,limit:limit,interval:interval) else {return false}
  try save(state,key:key);return true
 }
 func finish(key:String,question:PlotQuestion,cutoff:Double,clues:[PlotClue],context:PlotContext) throws {
  var state=load(key);state.addClues(clues,context:context);state.remember(question,at:cutoff);try save(state,key:key)
 }
 func fail(key:String,segment:Int) throws {var state=load(key);state.budget.failedSegments.insert(segment);try save(state,key:key)}
 func record(key:String,decision:PlotDecision) throws {var state=load(key);state.decisions.append(decision);state.decisions=Array(state.decisions.suffix(200));try save(state,key:key)}
}
