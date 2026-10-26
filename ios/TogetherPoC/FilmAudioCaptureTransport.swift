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
  settings.timeoutIntervalForRequest=25
  settings.timeoutIntervalForResource=90
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
  var request=URLRequest(url:url,cachePolicy:.reloadIgnoringLocalCacheData,timeoutInterval:60)
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
             audioStartSeconds:Double) async throws {
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
   receipt.status=="received",receipt.count==index,
   receipt.audio_persisted==false else {throw FilmAudioCaptureError.invalidReceipt}
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
