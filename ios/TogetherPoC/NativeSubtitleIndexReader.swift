import Foundation

/// Reads only a selected HLS WebVTT subtitle rendition. Never downloads movie
/// segments or sends an ahead-of-playback transcript to a generative model.
enum NativeSubtitleIndexReader {
 struct Segment {
  let url:URL
  let start:Double
  let duration:Double
 }
 enum Failure:Error {case unsupported,tooLarge,noText}
 static let maxSegments=3000
 static let maxBytes=5*1024*1024

 static func isDemandDrivenLocal(master:URL)->Bool {
  let host=master.host?.lowercased() ?? ""
  return master.pathExtension.lowercased()=="m3u8" &&
   ["127.0.0.1","localhost","::1","[::1]"].contains(host)
 }
 static func subtitleURL(master:String,base:URL,track:Int)->URL? {
  guard track>=0 else{return nil}
  let options=master.components(separatedBy:.newlines).filter {
   $0.hasPrefix("#EXT-X-MEDIA:") && $0.contains("TYPE=SUBTITLES")
  }
  guard options.indices.contains(track),let value=attribute("URI",from:options[track]) else{return nil}
  return safeURL(value,relativeTo:base)
 }
 private static func attribute(_ name:String,from line:String)->String? {
  guard let range=line.range(of:name+"=\"") else{return nil}
  let value=line[range.upperBound...]
  return value.prefix(while:{$0 != "\""}).description
 }
 static func segments(playlist:String,base:URL)->[Segment]? {
  guard playlist.contains("#EXTM3U") else{return nil}
  var result:[Segment]=[];var position=0.0;var pending:Double?
  for raw in playlist.components(separatedBy:.newlines) {
   let line=raw.trimmingCharacters(in:.whitespacesAndNewlines)
   if line.hasPrefix("#EXTINF:") {
    pending=Double(line.dropFirst(8).split(separator:",").first ?? "")
   } else if !line.isEmpty && !line.hasPrefix("#") {
    guard let duration=pending,duration.isFinite,duration>=0,
          let url=safeURL(line,relativeTo:base) else{return nil}
    guard result.count<maxSegments else{return nil}
    result.append(Segment(url:url,start:position,duration:duration))
    position+=duration;pending=nil
   }
  }
  return result.isEmpty ? nil : result
 }
 private static func safeURL(_ source:String,relativeTo base:URL)->URL? {
  guard let url=URL(string:source,relativeTo:base)?.absoluteURL,
   ["http","https"].contains(url.scheme ?? ""),url.scheme==base.scheme,
   url.host==base.host,url.port==base.port else{return nil}
  return url
 }
 static func parseSegment(_ text:String,segment:Segment)->[SubtitleCue] {
  guard let document=try? SubtitleParser.parse(Data(text.utf8),extension:"vtt") else{return []}
  let mapOffset:Double?={
   guard let line=text.components(separatedBy:.newlines).first(where:{$0.hasPrefix("X-TIMESTAMP-MAP=")}),
    let pts=line.range(of:"MPEGTS:"),let value=Double(line[pts.upperBound...].prefix(while:{$0.isNumber})),
    let local=line.range(of:"LOCAL:") else{return nil}
   let localTime=String(line[local.upperBound...].prefix(while:{$0 != ","}))
   guard let localSeconds=SubtitleParser.timestamp(localTime) else{return nil}
   return value/90000-localSeconds
  }()
  let largest=document.cues.map(\.end).max() ?? .infinity
  let relative=mapOffset==nil && segment.start>0.01 && largest<=segment.duration+0.75
  let shift=mapOffset ?? (relative ? segment.start : 0)
  return document.cues.compactMap {cue in
   let start=cue.start+shift,end=cue.end+shift
   guard start.isFinite,end.isFinite,start>=0,end>start else{return nil}
   return SubtitleCue(start:start,end:end,text:cue.text)
  }
 }
 static func merge(_ values:[SubtitleCue])->SubtitleDocument? {
  let sorted=values.sorted{$0.start<$1.start}
  var result:[SubtitleCue]=[]
  for cue in sorted {
   guard cue.end>cue.start,!cue.text.isEmpty else{continue}
   if let last=result.last,abs(last.start-cue.start)<0.08 &&
       abs(last.end-cue.end)<0.08 && last.text==cue.text {continue}
   result.append(cue)
  }
  return result.isEmpty ? nil : SubtitleDocument(result)
 }
 /// Repair reads only the selected rendition's current segment. Fetching
 /// planned future VTT files can reposition the local producer and stall video.
 static func currentSegments(_ parts:[Segment],at position:Double)->[Segment] {
  guard position.isFinite,position>=0 else{return []}
  return Array(parts.filter{$0.start<=position && $0.start+$0.duration>position}.prefix(1))
 }
 static func fetchCurrentWindow(master:URL,track:Int,at position:Double,session:URLSession?=nil) async -> SubtitleDocument? {
  guard isDemandDrivenLocal(master:master),track>=0,position.isFinite,position>=0 else{return nil}
  let configuration=URLSessionConfiguration.ephemeral
  configuration.timeoutIntervalForRequest=3;configuration.timeoutIntervalForResource=6
  let client=session ?? URLSession(configuration:configuration)
  defer{if session==nil {client.invalidateAndCancel()}}
  func load(_ url:URL) async throws->Data {
   try Task.checkCancellation()
   let (data,response)=try await client.data(for:URLRequest(url:url,cachePolicy:.reloadIgnoringLocalCacheData,timeoutInterval:3))
   guard data.count<=maxBytes,let http=response as? HTTPURLResponse,(200...206).contains(http.statusCode) else{throw Failure.noText}
   return data
  }
  do {
   let masterData=try await load(master)
   guard let manifest=String(data:masterData,encoding:.utf8),let selected=subtitleURL(master:manifest,base:master,track:track) else{return nil}
   let playlistData=try await load(selected)
   guard let playlist=String(data:playlistData,encoding:.utf8) else{return nil}
   if selected.pathExtension.lowercased()=="vtt" {let document=try SubtitleParser.parse(playlistData,extension:"vtt");return merge(Array(document.cues.filter{$0.end>position-10 && $0.start<position+2}.prefix(64)))}
   guard let parts=segments(playlist:playlist,base:selected) else{return nil}
   var cues:[SubtitleCue]=[]
   for part in currentSegments(parts,at:position) {
    let data=try await load(part.url)
    guard let text=String(data:data,encoding:.utf8) else{continue}
    cues.append(contentsOf:parseSegment(text,segment:part))
   }
   try Task.checkCancellation()
   return merge(Array(cues.filter{$0.end>position-10 && $0.start<position+2}.prefix(64)))
  } catch {return nil}
 }
 static func fetch(master:URL,track:Int) async -> SubtitleDocument? {
  guard master.pathExtension.lowercased()=="m3u8",track>=0,
   ["http","https"].contains(master.scheme ?? "") else{return nil}
  do {
   let (manifestData,_)=try await URLSession.shared.data(from:master)
   guard manifestData.count<maxBytes,let manifest=String(data:manifestData,encoding:.utf8),
         let sub=subtitleURL(master:manifest,base:master,track:track) else{return nil}
   let (renditionData,_)=try await URLSession.shared.data(from:sub)
   guard renditionData.count<maxBytes,let playlist=String(data:renditionData,encoding:.utf8) else{return nil}
   if sub.pathExtension.lowercased()=="vtt" {
    return try? SubtitleParser.parse(renditionData,extension:"vtt")
   }
   guard let parts=segments(playlist:playlist,base:sub) else{return nil}
   var results:[SubtitleCue]=[];var byteCount=manifestData.count+renditionData.count
   // Keep subtitle reads bounded. Failure of one segment does not erase
   // the verified text from the others.
   for offset in stride(from:0,to:parts.count,by:8) {
    try Task.checkCancellation()
    let batch=Array(parts[offset..<min(offset+8,parts.count)])
    let received=await withTaskGroup(of:(Int,Data?).self) {group -> [(Int,Data?)] in
     for (i,part) in batch.enumerated() {
      group.addTask {
       let response=try? await URLSession.shared.data(from:part.url)
        let data=response?.0
       return (i,data)
      }
     }
     var items:[(Int,Data?)]=[]
     for await result in group {items.append(result)}
     return items.sorted{$0.0<$1.0}
    }
    for (i,data) in received {
     guard let data else{continue}
     byteCount+=data.count
     guard byteCount<=maxBytes else{return nil}
     guard let text=String(data:data,encoding:.utf8) else{continue}
     results.append(contentsOf:parseSegment(text,segment:batch[i]))
    }
   }
   return merge(results)
  }catch{return nil}
 }
}
