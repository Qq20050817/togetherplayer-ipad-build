import Foundation
import Security

/// Device-local pairing configuration. Tokens never enter app bundle,
/// UserDefaults, movie URLs, subtitles or logging.
struct FilmAudioCaptureConfiguration: Codable, Equatable {
 let baseURL: URL
 let pairingSecret: String

 init(endpoint: String, secret: String) throws {
  let address=endpoint.trimmingCharacters(in:.whitespacesAndNewlines)
  guard let components=URLComponents(string:address),
   components.scheme?.lowercased()=="https",
   let host=components.host,!host.isEmpty,
   components.user==nil,components.password==nil,
   components.query==nil,components.fragment==nil,
   ["","/","/v1/audio-capture-asr"].contains(components.path) else {
    throw FilmAudioCaptureError.configuration("接收地址须为 HTTPS 域名，测试版可使用 /v1/audio-capture-asr 路径")
  }
  let cleanSecret=secret.trimmingCharacters(in:.whitespacesAndNewlines)
  guard cleanSecret.count>=32 && cleanSecret.count<=256 else {
   throw FilmAudioCaptureError.configuration("授权码长度应为 32 至 256 个字符")
  }
  guard let url=components.url else {throw FilmAudioCaptureError.configuration("无效的服务器地址")}
  baseURL=url
  pairingSecret=cleanSecret
 }

 func resourceURL(_ segments:[String])->URL {
  let suffix=baseURL.path=="/v1/audio-capture-asr" ? Array(segments.dropFirst(2)) : segments
  return suffix.reduce(baseURL) {url,part in url.appendingPathComponent(part)}
 }
}

enum FilmAudioCaptureError: LocalizedError {
 case configuration(String)
 case network(String)
 case rejected(Int)
 case invalidReceipt
 var errorDescription:String? {
  switch self {
  case .configuration(let reason):return reason
  case .network(let reason):return reason
  case .rejected(let status):return "新加坡服务器拒绝了请求（HTTP \(status)），请检查授权和服务状态"
  case .invalidReceipt:return "服务器返回的数据不完整，上传结果未被确认"
  }
 }
}

enum FilmAudioCaptureKeychain {
 private static let service="dev.together.poc.audio-capture.asr-test"
 private static let account="singapore-asr-test"

 static func load()->FilmAudioCaptureConfiguration? {
  let query:[String:Any]=[
   kSecClass as String:kSecClassGenericPassword,
   kSecAttrService as String:service,
   kSecAttrAccount as String:account,
   kSecReturnData as String:true,
   kSecMatchLimit as String:kSecMatchLimitOne
  ]
  var item:CFTypeRef?
  guard SecItemCopyMatching(query as CFDictionary,&item)==errSecSuccess,
   let bytes=item as? Data,
   let config=try? JSONDecoder().decode(FilmAudioCaptureConfiguration.self,from:bytes),
   (try? FilmAudioCaptureConfiguration(endpoint:config.baseURL.absoluteString,
                                      secret:config.pairingSecret)) != nil else {return nil}
  return config
 }

 static func save(endpoint:String,secret:String) throws {
  let config=try FilmAudioCaptureConfiguration(endpoint:endpoint,secret:secret)
  let encoded=try JSONEncoder().encode(config)
  let key:[String:Any]=[
   kSecClass as String:kSecClassGenericPassword,
   kSecAttrService as String:service,
   kSecAttrAccount as String:account
  ]
  var item=key
  item[kSecValueData as String]=encoded
  item[kSecAttrAccessible as String]=kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
  SecItemDelete(key as CFDictionary)
  guard SecItemAdd(item as CFDictionary,nil)==errSecSuccess else {
   throw FilmAudioCaptureError.configuration("iPad 钥匙串无法保存接收端授权")
  }
 }

 static func clear() {
  let query:[String:Any]=[
   kSecClass as String:kSecClassGenericPassword,
   kSecAttrService as String:service,
   kSecAttrAccount as String:account
  ]
  SecItemDelete(query as CFDictionary)
 }
}

private final class FilmAudioCaptureRedirectGuard:NSObject,URLSessionTaskDelegate {
 func urlSession(_ session:URLSession,task:URLSessionTask,
                 willPerformHTTPRedirection response:HTTPURLResponse,
                 newRequest request:URLRequest,
                 completionHandler:@escaping (URLRequest?)->Void) {
  completionHandler(nil) // Never forward either token to another host.
 }
}

/// A nine-clip in-memory upload to a dedicated HTTPS endpoint.
/// Xunlei credentials, original media URLs and whole films are never sent.
final class FilmAudioCaptureTransport {
 struct Grant:Decodable {
  let job_id:String
  let upload_grant:String
  let expires_in_seconds:Int
  let required_samples:Int
 }
 struct Receipt:Decodable {
  let status:String
  let count:Int?
  let received:Int?
  let audio_persisted:Bool
  let asr_status:String?
  let recognized_samples:Int?
  let matched_anchors:Int?
  let reason:String?
  let auto_correct:Bool?
  let offset_at_start_seconds:Double?
  let linear_drift_seconds_per_hour:Double?
 }
 private let config:FilmAudioCaptureConfiguration
 private let redirectGuard=FilmAudioCaptureRedirectGuard()
 private let session:URLSession

 init(configuration:FilmAudioCaptureConfiguration) {
  self.config=configuration
  let settings=URLSessionConfiguration.ephemeral
  settings.httpShouldSetCookies=false
  settings.httpCookieStorage=nil
  settings.urlCredentialStorage=nil
  settings.urlCache=nil
  settings.timeoutIntervalForRequest=90
  settings.timeoutIntervalForResource=180
  session=URLSession(configuration:settings,delegate:redirectGuard,delegateQueue:nil)
 }
 deinit {session.invalidateAndCancel()}

 private func endpoint(_ segments:[String])->URL {
  config.resourceURL(segments)
 }

 private func post(_ url:URL,token:String,body:Data?,
                   headers:[String:String]=[:]) async throws ->Data {
  guard url.scheme?.lowercased()=="https",url.host==config.baseURL.host else {
   throw FilmAudioCaptureError.network("接收端地址发生变化，已停止上传")
  }
  var request=URLRequest(url:url,cachePolicy:.reloadIgnoringLocalCacheData,timeoutInterval:120)
  request.httpMethod="POST"
  request.httpBody=body ?? Data()
  request.setValue("Bearer "+token,forHTTPHeaderField:"Authorization")
  request.setValue("no-store",forHTTPHeaderField:"Cache-Control")
  for (key,value) in headers {request.setValue(value,forHTTPHeaderField:key)}
  let (data,response)=try await session.data(for:request)
  guard let http=response as? HTTPURLResponse else {
   throw FilmAudioCaptureError.network("服务器未返回有效 HTTP 响应")
  }
  guard (200...299).contains(http.statusCode) else {
   throw FilmAudioCaptureError.rejected(http.statusCode)
  }
  guard data.count<=16384 else {throw FilmAudioCaptureError.invalidReceipt}
  return data
 }

 func start() async throws ->Grant {
  let data=try await post(endpoint(["v1","audio-capture","sessions"]),
                           token:config.pairingSecret,body:nil)
  guard let grant=try? JSONDecoder().decode(Grant.self,from:data),
   grant.required_samples==9,grant.expires_in_seconds>0,
   (16...64).contains(grant.job_id.count),
   !grant.upload_grant.isEmpty else {throw FilmAudioCaptureError.invalidReceipt}
  return grant
 }

 func upload(grant:Grant,index:Int,pcm:Data,subtitleSeconds:Double,
             audioStartSeconds:Double) async throws ->Receipt {
  guard (1...9).contains(index),pcm.count>=8*16000*2,pcm.count<=12*16000*2,
   subtitleSeconds.isFinite,audioStartSeconds.isFinite,
   subtitleSeconds>=0,audioStartSeconds>=0 else {
    throw FilmAudioCaptureError.configuration("采集片段时间或大小异常")
  }
  let data=try await post(endpoint(["v1","audio-capture","sessions",grant.job_id,
                                     "clips",String(index)]),
    token:grant.upload_grant,body:pcm,
    headers:["Content-Type":"application/octet-stream",
             "X-Audio-Sample-Rate":"16000",
             "X-Audio-Channels":"1",
             "X-Subtitle-Seconds":String(subtitleSeconds),
             "X-Audio-Start-Seconds":String(audioStartSeconds)])
  guard let receipt=try? JSONDecoder().decode(Receipt.self,from:data),
   receipt.audio_persisted==false,
   (receipt.status=="received" && receipt.count==index ||
    receipt.status=="retry_needed" && receipt.count==index-1) else {
     throw FilmAudioCaptureError.invalidReceipt
   }
  return receipt
 }

 static func subtitlePayload(document:SubtitleDocument,duration:Double) throws ->Data {
  struct Cue:Encodable {let start:Double;let end:Double;let text:String}
  struct Payload:Encodable {let film_duration_seconds:Double;let cues:[Cue]}
  guard duration.isFinite,(90...21600).contains(duration),
   (9...3500).contains(document.cues.count) else {
    throw FilmAudioCaptureError.configuration("字幕条数或影片时长不适合九段比对")
  }
  var cues:[Cue]=[]
  for cue in document.cues {
   let text=cue.text.trimmingCharacters(in:.whitespacesAndNewlines)
   guard cue.start.isFinite,cue.end.isFinite,cue.start>=0,cue.end>cue.start,
    cue.end-cue.start<=40,cue.start<=duration+300,text.count<=220 else {
     throw FilmAudioCaptureError.configuration("字幕时间或单条文字超出比对限制")
   }
   if !text.isEmpty {cues.append(Cue(start:cue.start,end:cue.end,text:text))}
  }
  guard cues.count>=9 else {throw FilmAudioCaptureError.configuration("有效字幕少于九条")}
  let data=try JSONEncoder().encode(Payload(film_duration_seconds:duration,cues:cues))
  guard data.count<=512*1024 else {throw FilmAudioCaptureError.configuration("字幕数据超过比对服务限制")}
  return data
 }

 func uploadSubtitles(grant:Grant,document:SubtitleDocument,duration:Double) async throws {
  let body=try Self.subtitlePayload(document:document,duration:duration)
  let data=try await post(endpoint(["v1","audio-capture","sessions",grant.job_id,"subtitles"]),
   token:grant.upload_grant,body:body,headers:["Content-Type":"application/json"])
  struct Confirmation:Decodable {let status:String;let cue_count:Int;let subtitles_persisted:Bool}
  guard let receipt=try? JSONDecoder().decode(Confirmation.self,from:data),
   receipt.status=="subtitles_received",receipt.cue_count>=9,!receipt.subtitles_persisted else {
    throw FilmAudioCaptureError.invalidReceipt
  }
 }

 static func resultMessage(_ result:Receipt,hasSubtitles:Bool)->String {
  let recognized=result.recognized_samples ?? 0
  guard hasSubtitles else {return "已识别 \(recognized)/9 段音轨；未提供字幕，尚未比对时间轴"}
  let matched=result.matched_anchors ?? 0
  if result.status=="verified",matched>=7 {
   return "字幕抽样比对通过（\(matched)/9 段）；时间轴未修改"
  }
  if result.status=="offset_detected",matched>=7,
   let offset=result.offset_at_start_seconds,offset.isFinite {
   return String(format:"抽样发现可能偏移 %+.2f 秒（%d/9 段）；请核对，未自动修改",offset,matched)
  }
  if result.status=="drift_detected",matched>=7,
   let drift=result.linear_drift_seconds_per_hour,drift.isFinite {
   return String(format:"抽样发现可能漂移 %+.2f 秒/小时；请核对，未自动修改",drift)
  }
  if result.status=="version_might_differ" {
   return "片段时间证据不一致，需要人工核对；未修改字幕"
  }
  return "音轨已识别 \(recognized)/9；字幕比对证据不足（\(matched)/9），不能判断是否错位；时间轴未修改"
 }

 func finish(grant:Grant) async throws ->Receipt {
  let data=try await post(endpoint(["v1","audio-capture","sessions",grant.job_id,"finish"]),
                           token:grant.upload_grant,body:nil)
  guard let receipt=try? JSONDecoder().decode(Receipt.self,from:data),
   receipt.received==9,receipt.audio_persisted==false else {
    throw FilmAudioCaptureError.invalidReceipt
  }
  return receipt
 }
}
