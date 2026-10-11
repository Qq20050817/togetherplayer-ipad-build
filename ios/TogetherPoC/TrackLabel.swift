import Foundation

// Language tags and explicit titles identify Chinese script; track order does not.
enum TrackLabel {
 static let chinese=Locale(identifier:"zh-Hans")
 static func localized(_ name:String,language:String?=nil,subtitle:Bool=false)->String {
  let normalized=(language ?? "").replacingOccurrences(of:"_",with:"-").lowercased()
  let hint=(normalized+" "+name).lowercased()
  let simplified=["hans","simplified","简体","簡體","chs","zh-cn","zh-sg"].contains {hint.contains($0)}
  let traditional=["hant","traditional","繁体","繁體","cht","zh-tw","zh-hk","zh-mo"].contains {hint.contains($0)}
  var result=name
  let words=["English":"英语","Chinese":"中文","Arabic":"阿拉伯语","Danish":"丹麦语","Dutch":"荷兰语","Finnish":"芬兰语","French":"法语","Greek":"希腊语","Hindi":"印地语","Indonesian":"印度尼西亚语","Italian":"意大利语","Japanese":"日语","Korean":"韩语","Norwegian":"挪威语","Polish":"波兰语","Portuguese":"葡萄牙语","Romanian":"罗马尼亚语","Russian":"俄语","Spanish":"西班牙语","German":"德语","Swedish":"瑞典语","Thai":"泰语","Turkish":"土耳其语","Vietnamese":"越南语","SDH":"听障字幕","Forced":"强制字幕","Signs & Songs":"标牌与歌曲","Commentary":"评论音轨"]
  for (a,b) in words {result=result.replacingOccurrences(of:a,with:b,options:.caseInsensitive)}
  if let code=AudioTrackDetail.languageKey(language),code != "und",let label=chinese.localizedString(forLanguageCode:code) {
   if result.isEmpty || result.lowercased()==code {result=label}
   else if !result.contains(label) {result=label+" · "+result}
  }
  if simplified && !traditional {result="简体中文"+(result.isEmpty ? "" : " · "+result)}
  else if traditional && !simplified {result="繁体中文"+(result.isEmpty ? "" : " · "+result)}
  else if subtitle && (AudioTrackDetail.languageKey(language)=="zh" || result.contains("中文")) {result += "（简繁未标明）"}
  return result.isEmpty ? "未标明语言" : result
 }
}
