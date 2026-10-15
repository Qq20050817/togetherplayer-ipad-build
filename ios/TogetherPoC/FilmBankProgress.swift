import Foundation

struct FilmBankProgress:Codable {
 var roundID=UUID().uuidString
 var published:Set<String>=[]
 var revealed:Set<String>=[]
 var answered:Set<String>=[]
 var delivered:Set<String>=[]
 var revision=0
}
struct FilmBankRevealPart:Equatable {
 let id:String
 let text:String
}

extension FilmQuestionBankStore {
 // Source fingerprint keys survive moving/reimporting the same movie or
 // joining another room. Answers stay in the local bank, never in progress.
 func loadForSource(_ fingerprint:String)->FilmQuestionBank? {load(filmKey:"source:"+fingerprint.lowercased())}
 func saveForSource(_ bank:FilmQuestionBank)throws {try save(bank,filmKey:"source:"+(bank.sourceFingerprint ?? "").lowercased())}
}

actor FilmBankProgressStore {
 private let directory:URL
 init(directory:URL?=nil) {self.directory=directory ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("AIQuestionBankProgress",isDirectory:true)}
 private func file(_ key:String)->URL {directory.appendingPathComponent(PlotMemoryStore.key(key)+".json")}
 func load(_ key:String)->FilmBankProgress {
  guard let data=try? Data(contentsOf:file(key)),data.count<100_000,let progress=try? JSONDecoder().decode(FilmBankProgress.self,from:data) else{return FilmBankProgress()}
  return progress
 }
 func save(_ progress:FilmBankProgress,key:String)throws {
  try Task.checkCancellation()
  // Tasks can enqueue actor writes out of order. Never resurrect older sets.
  guard progress.revision>=load(key).revision else{return}
  try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
  var folder=directory;var attributes=URLResourceValues();attributes.isExcludedFromBackup=true;try? folder.setResourceValues(attributes)
  try JSONEncoder().encode(progress).write(to:file(key),options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
 }
}

// Bank timestamps use the host file timeline; room and peer positions are
// canonical. Apply calibration exactly once when gating delayed answers.
enum FilmBankTimeline {
 static func safeReveal(playerMs:Double,roomMs:Double,hostOffset:Double,peers:[Double])->Double {
  let values=[playerMs,roomMs+hostOffset]+peers.map{$0+hostOffset}
  guard values.allSatisfy({$0.isFinite}) else{return 0}
  return max(0,values.min() ?? 0)
 }
}

extension FilmBankProgress {
 enum CodingKeys:String,CodingKey {case roundID,published,revealed,answered,delivered,revision}
 init(from decoder:Decoder)throws {
  let c=try decoder.container(keyedBy:CodingKeys.self)
  roundID=try c.decodeIfPresent(String.self,forKey:.roundID) ?? "legacy-round"
  published=try c.decodeIfPresent(Set<String>.self,forKey:.published) ?? []
  revealed=try c.decodeIfPresent(Set<String>.self,forKey:.revealed) ?? []
  answered=try c.decodeIfPresent(Set<String>.self,forKey:.answered) ?? []
  delivered=try c.decodeIfPresent(Set<String>.self,forKey:.delivered) ?? []
  revision=try c.decodeIfPresent(Int.self,forKey:.revision) ?? 0
 }
}
