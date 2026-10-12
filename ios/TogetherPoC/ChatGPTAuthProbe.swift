import Foundation
import SwiftUI
import Network
import CryptoKit

/// Independent diagnostic. Nothing is sent to TogetherPlayer's room server.
/// User must explicitly tap Continue with ChatGPT to begin sign-in.
@MainActor final class ChatGPTAuthProbe: ObservableObject {
 @Published private(set) var status="尚未连接 ChatGPT"
 @Published private(set) var connected=false
 @Published private(set) var testText=""
 @Published private(set) var working=false
 private struct Attempt {
  let state:String
  let nonce:String
  let verifier:String
  let redirect:String
  let clientID:String
  let start:Date
 }
 private var pending:Attempt?
 private var listener:NWListener?
 private static let resource="https://api.openai.com/v1"
 private static let authorize="https://auth.openai.com/api/accounts/authorize"
 private static let token="https://auth.openai.com/api/accounts/oauth/token"
 private let launchID=UUID().uuidString
 @Published private(set) var integrationReady=false
 @Published private(set) var usagePaused=false
 @Published private(set) var verificationStatus="需验证首次授权、连续两次调用和重启后调用"
 private var inferenceActive=false
 private func invalidateUsage() {
  integrationReady=false;UserDefaults.standard.set(false,forKey:verificationKey+"-restart")
  verificationStatus="授权失效，需要重新授权并验收"
 }
 private var authorizationTimeout:Task<Void,Never>?
 private var verificationKey:String {guard let c=ChatGPTLocalKeychain.read() else {return "plot-auth-unconnected"};return "plot-auth-check-"+PlotMemoryStore.key(c.clientID+c.subject)}
 init() {
  connected=ChatGPTLocalKeychain.read()?.scopes.split(separator:" ").contains("chatgpt.tokens.use.direct")==true
  status=connected ? "已保存授权，可直接测试 ChatGPT，不用再跳转" : "尚未授权，需要首次登录"
  integrationReady=connected && UserDefaults.standard.bool(forKey:verificationKey+"-restart")
  if integrationReady {verificationStatus="本机连续调用和重启后调用已验证"}
  diagnosticRequests=UserDefaults.standard.integer(forKey:verificationKey+"-diagnostics")
  usagePaused=UserDefaults.standard.bool(forKey:verificationKey+"-usage-paused")
 }
 static func random()->String {UUID().uuidString.replacingOccurrences(of:"-",with:"")+UUID().uuidString.replacingOccurrences(of:"-",with:"")}
 static func authURL(for attempt:[String:String])->URL? {
  var c=URLComponents(string:authorize)!
  c.queryItems=attempt.sorted{$0.key<$1.key}.map{URLQueryItem(name:$0.key,value:$0.value)}
  return c.url
 }
 private func hostID()->String {
  let key="together-chatgpt-host-identifier"
  if let saved=UserDefaults.standard.string(forKey:key){return saved}
  let value="urn:uuid:"+UUID().uuidString.lowercased()
  UserDefaults.standard.set(value,forKey:key)
  return value
 }
 func connect() {
  guard !working,!inferenceActive else{return}
  integrationReady=false
  working=true;status="正在启动 iPad 本地授权回调…";testText=""
  authorizationTimeout?.cancel()
  authorizationTimeout=Task {[weak self] in
   try? await Task.sleep(nanoseconds:600_000_000_000)
   guard !Task.isCancelled,let self,self.pending != nil else {return}
   self.listener?.cancel();self.listener=nil;self.pending=nil;self.working=false;self.status="授权等待超时，可重新开始"
  }
  let params=NWParameters.tcp
  params.requiredLocalEndpoint = .hostPort(host:NWEndpoint.Host("127.0.0.1"),port:.any)
  do {
   let l=try NWListener(using:params,on:.any)
   listener=l
   l.newConnectionHandler={[weak self] connection in
    Task{@MainActor in self?.receive(connection)}
   }
   l.stateUpdateHandler={[weak self] state in
    Task{@MainActor in
     guard let self else{return}
     switch state {
     case .ready:
      guard let port=self.listener?.port?.rawValue else{self.status="本地回调没有可用端口";self.working=false;return}
      self.openBrowser(port:port)
     case .failed:
      self.status="无法在 iPad 绑定 127.0.0.1；这个授权方案可能不适用"
      self.working=false;self.listener?.cancel();self.listener=nil
     default:break
     }
    }
   }
   l.start(queue:.global(qos:.userInitiated))
  }catch {
   status="启动本地回调失败：\(error.localizedDescription)"
   working=false
  }
 }
 private func openBrowser(port:UInt16) {
  let verifier=Self.random()
  let state=Self.random(),nonce=Self.random()
  let redirect="http://127.0.0.1:\(port)/auth/callback"
  let clientID=ChatGPTLocalKeychain.read()?.clientID ?? UserDefaults.standard.string(forKey:"plot-chatgpt-client-id") ?? "dynamic_agent_client"
  pending=Attempt(state:state,nonce:nonce,verifier:verifier,redirect:redirect,clientID:clientID,start:Date())
  let hash=SHA256.hash(data:Data(verifier.utf8))
  let challenge=Data(hash).base64EncodedString().replacingOccurrences(of:"+",with:"-").replacingOccurrences(of:"/",with:"_").replacingOccurrences(of:"=",with:"")
  var args=[
   "client_id":clientID,"redirect_uri":redirect,"response_type":"code",
   "scope":"openid profile email offline_access resource.invoke chatgpt.tokens.use.direct",
   "resource":Self.resource,"state":state,"nonce":nonce,"code_challenge_method":"S256",
   "code_challenge":challenge,"ext_agent_host_id":hostID()
  ]
  if clientID=="dynamic_agent_client" {args["agent_name_hint"]="TogetherPlayer"}
  else if let old=ChatGPTLocalKeychain.read() {args["id_token_hint"]=old.idToken}
  guard let url=Self.authURL(for:args) else{status="授权地址无效";working=false;return}
  status="授权页面已打开。请在苹果浏览器中确认；完成后若停在成功页面，手动返回 TogetherPlayer。"
  UIApplication.shared.open(url,options:[:]) {[weak self] success in
   Task{@MainActor in if !success {self?.status="iPad 未能打开官方授权页面";self?.working=false}}
  }
 }
 private func receive(_ connection:NWConnection) {
  connection.start(queue:.global(qos:.userInitiated))
  func read(_ previous:Data) {
   connection.receive(minimumIncompleteLength:1,maximumLength:4096){[weak self] data,_,_,error in
    var all=previous
    if let data{all.append(data)}
    if all.count>8192 || error != nil {connection.cancel();return}
    if all.range(of:Data("\r\n\r\n".utf8)) == nil {
     read(all);return
    }
    guard let text=String(data:all,encoding:.utf8),
     let first=text.components(separatedBy:"\r\n").first,
     first.hasPrefix("GET /auth/callback?"),
     let host=text.components(separatedBy:"\r\n").first(where:{$0.lowercased().hasPrefix("host: ")}),
     host.lowercased().contains("127.0.0.1:") else {
      connection.cancel();return
    }
    let target=first.split(separator:" ").dropFirst().first.map(String.init) ?? ""
    let url=URL(string:"http://127.0.0.1"+target)
    let fields=URLComponents(url:url ?? URL(string:"http://127.0.0.1/")!,resolvingAgainstBaseURL:false)?.queryItems ?? []
    let params=Dictionary(fields.map{($0.name,$0.value ?? "")},uniquingKeysWith:{first,_ in first})
    let result=Data("HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n<html><meta name=\"viewport\" content=\"width=device-width\"><body style=\"font-family:-apple-system;padding:35px\"><h3>TogetherPlayer 授权回调已收到</h3><p>请返回 TogetherPlayer 查看授权验证结果。</p></body></html>".utf8)
    connection.send(content:result,completion:.contentProcessed{_ in connection.cancel()})
    Task{@MainActor in self?.handleCallback(params)}
   }
  }
  read(Data())
 }
 private func handleCallback(_ params:[String:String]) {
  guard let attempt=pending,Date().timeIntervalSince(attempt.start)<600,
   params["state"]==attempt.state else {
   status="授权状态校验失败（防止错误或伪造回调）";working=false;return
  }
  pending=nil;listener?.cancel();listener=nil;authorizationTimeout?.cancel()
  if let err=params["error"] {status="ChatGPT 授权未完成：\(err)";working=false;return}
  guard let code=params["code"],!code.isEmpty else {status="回调已到达但没有授权码";working=false;return}
  let issued=params["client_id"] ?? attempt.clientID
  guard issued.hasPrefix("oaiapp_") else{status="未收到官方签发的客户端 ID";working=false;return}
  status="✅ 已收到 localhost 回调；正在交换授权码并验证账号身份…"
  Task {
   do {
    try await exchange(code:code,issued:issued,attempt:attempt)
   }catch {
    status="回调成功，但令牌验证失败：\(error.localizedDescription)"
   }
   working=false
  }
 }
 private func requestForm(_ fields:[String:String]) async throws -> [String:Any] {
  var url=URLComponents()
  url.queryItems=fields.map{URLQueryItem(name:$0.key,value:$0.value)}
  let body=(url.percentEncodedQuery ?? "").replacingOccurrences(of:"%20",with:"+")
  var request=URLRequest(url:URL(string:Self.token)!)
  request.httpMethod="POST";request.timeoutInterval=25
  request.setValue("application/x-www-form-urlencoded",forHTTPHeaderField:"Content-Type")
  request.httpBody=Data(body.utf8)
  let (data,response)=try await URLSession.shared.data(for:request)
  let code=(response as? HTTPURLResponse)?.statusCode ?? 0
  guard (200..<300).contains(code),
   let result=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any] else {
    if [400,401,403].contains(code) {invalidateUsage()}
    throw NSError(domain:"ChatGPTAuth",code:code,userInfo:[NSLocalizedDescriptionKey:"OpenAI 返回 HTTP \(code)"])
  }
  return result
 }
 private func exchange(code:String,issued:String,attempt:Attempt) async throws {
  let result=try await requestForm([
   "grant_type":"authorization_code","client_id":issued,
   "code":code,"code_verifier":attempt.verifier,
   "redirect_uri":attempt.redirect,"resource":Self.resource
  ])
  guard let idToken=result["id_token"] as? String,
   let access=result["access_token"] as? String,
   let refresh=result["refresh_token"] as? String,
   let scopes=result["scope"] as? String else{
    throw NSError(domain:"ChatGPTAuth",code:1,userInfo:[NSLocalizedDescriptionKey:"OpenAI 未提供完整授权信息"])
  }
  let subject=try await ChatGPTIdentityVerifier.signedIdentity(idToken,clientID:issued,nonce:attempt.nonce)
  guard scopes.split(separator:" ").contains("chatgpt.tokens.use.direct") else{
   throw NSError(domain:"ChatGPTAuth",code:2,userInfo:[NSLocalizedDescriptionKey:"账号已经登录，但未同意使用 ChatGPT 订阅额度"])
  }
  let validity=(result["expires_in"] as? NSNumber)?.doubleValue ?? 3600
  let cred=ChatGPTLocalCredentials(clientID:issued,subject:subject,idToken:idToken,
   accessToken:access,refreshToken:refresh,scopes:scopes,expiresAt:Date().timeIntervalSince1970+validity)
  guard ChatGPTLocalKeychain.save(cred) else {
   throw NSError(domain:"ChatGPTAuth",code:3,userInfo:[NSLocalizedDescriptionKey:"iPad Keychain 无法保存授权"])
  }
  UserDefaults.standard.set(issued,forKey:"plot-chatgpt-client-id")
  connected=true;integrationReady=false
  UserDefaults.standard.removeObject(forKey:verificationKey+"-acceptance")
  UserDefaults.standard.removeObject(forKey:verificationKey+"-diagnostics");diagnosticRequests=0
  UserDefaults.standard.removeObject(forKey:verificationKey+"-run")
  UserDefaults.standard.removeObject(forKey:verificationKey+"-calls")
  UserDefaults.standard.removeObject(forKey:verificationKey+"-restart")
  status="身份和权限已验证；还需连续两次与重启后的真实调用检查"
 }
 private func credentials() async throws -> ChatGPTLocalCredentials {
  guard var current=ChatGPTLocalKeychain.read(),current.scopes.split(separator:" ").contains("chatgpt.tokens.use.direct") else {
   throw NSError(domain:"ChatGPTAuth",code:4,userInfo:[NSLocalizedDescriptionKey:"尚未授权"])
  }
  if current.expiresAt>Date().timeIntervalSince1970+90{return current}
  let renewed=try await requestForm(["grant_type":"refresh_token","client_id":current.clientID,
    "refresh_token":current.refreshToken,"resource":Self.resource])
  guard let access=renewed["access_token"] as? String else {
   throw NSError(domain:"ChatGPTAuth",code:5,userInfo:[NSLocalizedDescriptionKey:"授权已过期，请重新登录"])
  }
  current.accessToken=access
  if let rotated=renewed["refresh_token"] as? String{current.refreshToken=rotated}
  current.expiresAt=Date().timeIntervalSince1970+((renewed["expires_in"] as? NSNumber)?.doubleValue ?? 3600)
  guard ChatGPTLocalKeychain.save(current) else {
   throw NSError(domain:"ChatGPTAuth",code:6,userInfo:[NSLocalizedDescriptionKey:"无法保存刷新后的授权"])
  }
  return current
 }
 func performInference(instructions:String,input:String,canSend:()->Bool={true}) async throws -> String {
  guard integrationReady,!usagePaused else {throw NSError(domain:"ChatGPTAuth",code:13,userInfo:[NSLocalizedDescriptionKey:"尚未完成本机真实授权验收或额度暂停"])}
  return try await requestInference(instructions:instructions,input:input,canSend:canSend)
 }
 private func requestInference(instructions:String,input:String,canSend:()->Bool={true}) async throws -> String {
  guard !inferenceActive else {throw CancellationError()}
  inferenceActive=true;defer {inferenceActive=false}
  try Task.checkCancellation()
  let c=try await credentials()
  var models=URLRequest(url:URL(string:"https://api.openai.com/v1/models")!);models.timeoutInterval=20
  models.setValue("Bearer "+c.accessToken,forHTTPHeaderField:"Authorization")
  let (data,response)=try await URLSession.shared.data(for:models)
  let modelCode=(response as? HTTPURLResponse)?.statusCode ?? 0
  if modelCode==401 || modelCode==403 {invalidateUsage()}
  if modelCode==429 {pauseUsage()}
  guard modelCode==200,let body=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any],let items=body["models"] as? [[String:Any]],let selected=items.first(where:{$0["visibility"] as? String=="list"})?["slug"] as? String else {
   throw NSError(domain:"ChatGPTAuth",code:7,userInfo:[NSLocalizedDescriptionKey:"模型列表不可用"])
  }
  guard canSend() else {throw CancellationError()}
  var req=URLRequest(url:URL(string:"https://api.openai.com/v1/responses")!);req.timeoutInterval=40
  req.httpMethod="POST";req.setValue("Bearer "+c.accessToken,forHTTPHeaderField:"Authorization");req.setValue("application/json",forHTTPHeaderField:"Content-Type")
  req.httpBody=try JSONSerialization.data(withJSONObject:["model":selected,"instructions":instructions,"input":[["role":"user","content":input]],"store":false,"stream":true] as [String:Any])
  let (bytes,res)=try await URLSession.shared.bytes(for:req)
  let code=(res as? HTTPURLResponse)?.statusCode ?? 0
  guard code==200 else {
   if code==401 || code==403 {invalidateUsage()}
   if code==429 {pauseUsage()}
   throw NSError(domain:"ChatGPTAuth",code:code,userInfo:[NSLocalizedDescriptionKey:"授权或额度不可用（HTTP \(code)），不会更换付费渠道"])
  }
  var answer="",completed=false
  for try await line in bytes.lines {
   try Task.checkCancellation()
   guard line.hasPrefix("data: "),let data=String(line.dropFirst(6)).data(using:.utf8),let event=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any] else {continue}
   switch event["type"] as? String {
   case "response.output_text.delta":answer+=event["delta"] as? String ?? "";if answer.count>6000 {throw CancellationError()}
   case "response.completed":completed=true
   case "response.failed","response.incomplete","error":
    let responseError=(event["response"] as? [String:Any])?["error"] as? [String:Any] ?? event["error"] as? [String:Any]
    if responseError?["code"] as? String=="subscription_sharing_usage_limit_exceeded" {pauseUsage()}
    throw NSError(domain:"ChatGPTAuth",code:11,userInfo:[NSLocalizedDescriptionKey:"请求未完成或额度受限，已停止"])
   default:break
   }
  }
  guard completed,!answer.isEmpty else {throw NSError(domain:"ChatGPTAuth",code:12,userInfo:[NSLocalizedDescriptionKey:"未收到完整结果"])}
  return answer
 }
 private func pauseUsage() {usagePaused=true;UserDefaults.standard.set(true,forKey:verificationKey+"-usage-paused");status="ChatGPT 额度受限，已暂停云端调用；可在官方用量设置查看"}
 @Published private(set) var diagnosticRequests=0
 func testRepeatedCall() {
  guard !working,connected,!inferenceActive else {return}
  let key=verificationKey
  let used=UserDefaults.standard.integer(forKey:key+"-diagnostics")
  guard used<6 else {status="授权验证已达6次上限，请先排查失败原因";return}
  diagnosticRequests=used+1;UserDefaults.standard.set(diagnosticRequests,forKey:key+"-diagnostics")
  working=true;testText="";status="使用本机授权执行一次真实调用…"
  Task {
   do {
    let answer=try await requestInference(instructions:"这是用户主动发起的授权验证。",input:"只回复：授权调用成功")
    testText=answer
    let data=UserDefaults.standard.data(forKey:key+"-acceptance")
    var check=data.flatMap{try? JSONDecoder().decode(PlotAuthAcceptance.self,from:$0)} ?? PlotAuthAcceptance()
    check.success(run:launchID)
    UserDefaults.standard.set(try? JSONEncoder().encode(check),forKey:key+"-acceptance")
    UserDefaults.standard.set(check.ready,forKey:key+"-restart")
    integrationReady=check.ready
    usagePaused=false;UserDefaults.standard.set(false,forKey:key+"-usage-paused")
    verificationStatus=check.ready ? "本机连续调用和重启后调用已验证" : check.calls>=2 ? "两次连续调用成功；请彻底退出并重开 App 后再测试一次" : "第一次调用成功，请再测试一次"
    status="真实调用成功；"+verificationStatus
   } catch {status="真实调用尚未成功：\(error.localizedDescription)"}
   working=false
  }
 }
 func disconnect() {
  listener?.cancel();listener=nil;pending=nil
  authorizationTimeout?.cancel();ChatGPTLocalKeychain.delete();connected=false;integrationReady=false;working=false;testText=""
  status="已清除本机授权。若需要取消远端授权，请到 ChatGPT 设置中断开 TogetherPlayer。"
 }
}
