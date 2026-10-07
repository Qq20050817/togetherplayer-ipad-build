import Foundation

// Empty AVMediaSelectionOption.mediaSubTypes is common in HLS. Use track
// descriptions only when they identify the option without ambiguity.
struct AudioTrackDetail: Equatable {
 let language:String?
 let codecs:[String]
 let channels:UInt32?
 static func languageKey(_ value:String?) -> String? {
  guard let value=value,!value.isEmpty else {return nil}
  let key=value.lowercased().replacingOccurrences(of:"_",with:"-").split(separator:"-").first.map(String.init) ?? value
  return ["eng":"en","jpn":"ja","zho":"zh","chi":"zh","fra":"fr","fre":"fr","deu":"de","ger":"de" ][key] ?? key
 }
 static func label(name:String,index:Int,language:String?,subtypes:[String],tracks:[AudioTrackDetail],optionCount:Int)->String {
  let matches=tracks.filter {languageKey(language) != nil && languageKey($0.language)==languageKey(language)}
  let unique=Array(Set(matches.map {detail in description(detail.codecs,detail.channels)})).filter {!$0.isEmpty}
  let detail: String
  if !subtypes.isEmpty {detail=description(subtypes,nil)}
  else if unique.count==1 {detail=unique[0]}
  else if optionCount==1,tracks.count==1 {detail=description(tracks[0].codecs,tracks[0].channels)}
  else {detail=""}
  let title=name.isEmpty ? "音轨 \(index+1)" : name
  return detail.isEmpty ? title+" · 音轨 \(index+1)" : title+" ["+detail+"]"
 }
 static func description(_ codecs:[String],_ channels:UInt32?)->String {
  let names=["mp4a":"AAC","ec-3":"Dolby Digital Plus","ac-3":"Dolby Digital","alac":"ALAC","lpcm":"PCM"]
  let codec=codecs.map {names[$0] ?? $0.uppercased()}.joined(separator:" / ")
  guard !codec.isEmpty else {return ""}
  return codec+(channels.map {" · \($0)声道"} ?? "")
 }
}
