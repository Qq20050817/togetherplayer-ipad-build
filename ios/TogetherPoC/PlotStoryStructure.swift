import Foundation

/// A local, timestamped interpretation of a subtitle section. All text is
/// uncertain until corroborated by actual watched evidence.
struct PlotStoryNode:Codable,Equatable {
 let start:Double
 let end:Double
 let summary:String
 let characters:[String]
 let events:[String]
 let motivations:[String]
 let relationships:[String]
 let unresolved:[String]
 let causalLinks:[String]
 let evidenceIDs:[String]
 let confidence:Double
 var recap:String {
  let segments=[summary]+Array(events.prefix(2))+Array(relationships.prefix(1))+Array(unresolved.prefix(1))
  return String(segments.joined(separator:"；").prefix(320))
 }
}

struct PlotStoryWindow {
 let start:Double
 let end:Double
 let cues:[SubtitleCue]
}

enum PlotStoryStructure {
 static func transcriptFingerprint(_ document:SubtitleDocument)->String {
  let cues=document.cues
  guard !cues.isEmpty else{return ""}
  let step=max(1,cues.count/32)
  let selected=stride(from:0,to:cues.count,by:step).map {index in
   let cue=cues[index]
   return "\(cue.start):\(cue.end):\(cue.text)"
  }
  return PlotMemoryStore.key(selected.joined(separator:"\n"))
 }
 static func windows(_ document:SubtitleDocument)->[PlotStoryWindow] {
  let valid=document.cues.filter{$0.start.isFinite && $0.end.isFinite && $0.start>=0 && $0.end>$0.start}
  guard valid.count>=6,let duration=valid.last?.end,duration>=240 else{return []}
  // Twelve approximately ten-minute segments for a feature film. Bound model
  // calls and resource usage independently of the number of subtitle cues.
  let target=duration>9000 ? 18.0 : 12.0
  let interval=max(240,duration/target)
  let count=min(18,Int(ceil(duration/interval)))
  return (0..<count).compactMap {index in
   let start=Double(index)*interval,end=min(duration,start+interval)
   let cues=valid.filter{$0.end>start && $0.end<=end}
   guard cues.count>=3 else{return nil}
   return PlotStoryWindow(start:start,end:end,cues:cues)
  }
 }
 static func context(_ window:PlotStoryWindow,source:String)->PlotContext {
  // Sample across the section to include the opening and turning point,
  // keeping input bounded for Apple's small on-device model.
  let cues=window.cues
  var selected:[SubtitleCue]=[]
  let step=max(1,Int(ceil(Double(cues.count)/18)))
  for index in stride(from:0,to:cues.count,by:step) {selected.append(cues[index])}
  selected.append(contentsOf:cues.suffix(5))
  let unique=Dictionary(grouping:selected,by:{$0.start}).values.compactMap{$0.first}
   .sorted{$0.start<$1.start}
  let evidence=unique.map{PlotEvidence.cue(start:$0.start,end:$0.end,text:$0.text,source:source)}
  return PlotContext(cutoff:window.end,recent:evidence,earlier:[],predictions:[])
 }
 static func parse(_ answer:String,window:PlotStoryWindow,context:PlotContext)->PlotStoryNode? {
  guard let data=PlotJSON.object(answer),
   let object=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any],
   let summary=object["summary"] as? String,
   (8...220).contains(summary.count),
   let ids=object["evidenceIDs"] as? [String],
   !ids.isEmpty,Set(ids).isSubset(of:context.evidenceIDs) else{return nil}
  let confidence=(object["confidence"] as? Double) ?? 0.6
  guard confidence.isFinite,(0...1).contains(confidence) else{return nil}
  func strings(_ name:String,limit:Int=5)->[String] {
   ((object[name] as? [String]) ?? []).prefix(limit)
    .map{String($0.trimmingCharacters(in:.whitespacesAndNewlines).prefix(110))}
    .filter{!$0.isEmpty}
  }
  return PlotStoryNode(start:window.start,end:window.end,summary:String(summary.prefix(220)),
   characters:strings("characters"),events:strings("events"),
   motivations:strings("motivations"),relationships:strings("relationships"),
   unresolved:strings("unresolved"),causalLinks:strings("causalLinks"),
   evidenceIDs:ids,confidence:confidence)
 }
 static func observedClues(_ nodes:[PlotStoryNode],watched:[PlotEvidence],at cutoff:Double)->[PlotClue] {
  let past=watched.filter{$0.end<=cutoff}
  let ids=Set(past.map(\.id))
  let available=nodes.filter {node in
   guard node.end<=cutoff,!node.evidenceIDs.isEmpty,
    Set(node.evidenceIDs).isSubset(of:ids) else{return false}
   // Jumping into the middle of a movie must not expose the segment recap.
   // Long story sections need evidence distributed across their duration.
   let duration=node.end-node.start
   if duration<=120 {return true}
   let seen=past.filter{$0.start>=node.start && $0.end<=node.end}
   guard seen.count>=3,let first=seen.first,let last=seen.last else{return false}
   return last.end-first.start>=duration*0.45
  }
  // Recover an early foreshadowing scene even when it is much older than the
  // latest five scenes. Rank by overlap with actually watched recent dialogue.
  let current=past.filter{$0.end>=cutoff-240}.suffix(16).map(\.text).joined(separator:"")
  func triples(_ text:String)->Set<String> {
   let chars=Array(text.lowercased().filter{$0.isLetter || $0.isNumber})
   guard chars.count>=3 else{return []}
   return Set((0..<(chars.count-2)).map{String(chars[$0...($0+2)])})
  }
  let reference=triples(current)
  let ranked=available.sorted {a,b in
   let aMatch=triples(a.recap).intersection(reference).count
   let bMatch=triples(b.recap).intersection(reference).count
   return aMatch==bMatch ? a.end>b.end : aMatch>bMatch
  }
  return Array(ranked.prefix(5)).sorted{$0.end<$1.end}.map {node in
   PlotClue(id:PlotMemoryStore.key("story-node:\(node.start):\(node.end)"),
    kind:"inference",text:"AI 分段剧情推测："+node.recap,
    evidenceIDs:node.evidenceIDs,end:node.end,confidence:node.confidence)
  }
 }
 static func prompt(_ context:PlotContext,previous:[PlotStoryNode])->String {
  // Resume may restore later nodes before a missing earlier window is rebuilt.
  // Filter by the current window start so future nodes NEVER enter its prompt.
  let start=context.recent.map(\.start).min() ?? context.cutoff
  let history=previous.filter{$0.end<=start}.suffix(3).map{String($0.recap.prefix(200))}
  return "仅此前已分析的剧情推测："+history.joined(separator:"\n")+
   "\n当前分段的有时间标记的字幕证据："+context.localInput
 }
}

/// Stored only on device, keyed by a digest of the movie identity, not a URL.
/// A reconnect can reuse the film map without replaying expensive model calls.
actor PlotStoryArchive {
 private let directory:URL?
 init(directory:URL?=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)
      .first?.appendingPathComponent("PlotStoryStructure")) {
  self.directory=directory
 }
 func read(key:String)->[PlotStoryNode] {
  guard let directory else{return []}
  let url=directory.appendingPathComponent(key+".json")
  guard let data=try? Data(contentsOf:url),
        let nodes=try? JSONDecoder().decode([PlotStoryNode].self,from:data) else{return []}
  return Array(nodes.prefix(18))
 }
 func write(_ nodes:[PlotStoryNode],key:String) throws {
  guard let directory else{return}
  try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
  var protected=directory;var values=URLResourceValues();values.isExcludedFromBackup=true
  try? protected.setResourceValues(values)
  let target=directory.appendingPathComponent(key+".json")
  try JSONEncoder().encode(Array(nodes.prefix(18)))
   .write(to:target,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
 }
}
