import Foundation

enum ChatGPTRequestStage:String {
 case authorization,models,response,stream
 var title:String {
  switch self {
  case .authorization:return "刷新授权"
  case .models:return "获取订阅模型"
  case .response:return "等待 ChatGPT 回应"
  case .stream:return "接收生成结果"
  }
 }
 var host:String {self == .authorization ? "auth.openai.com" : "api.openai.com"}
}

struct ChatGPTRequestFailure:LocalizedError {
 let stage:ChatGPTRequestStage
 var networkCode:Int?
 var httpCode:Int?
 var serviceCode:String?
 var errorDescription:String? {
  let detail:String
  if let networkCode {
   switch networkCode {
   case NSURLErrorTimedOut:detail="请求超时，请检查 iPad 到 \(stage.host) 的连接"
   case NSURLErrorNotConnectedToInternet:detail="设备没有网络连接"
   case NSURLErrorNetworkConnectionLost:detail="网络连接中断"
   case NSURLErrorCannotConnectToHost,NSURLErrorCannotFindHost:detail="无法连接 \(stage.host)"
   case NSURLErrorSecureConnectionFailed,NSURLErrorServerCertificateUntrusted:detail="安全连接或证书验证失败"
   default:detail="网络请求未完成（代码 \(networkCode)）"
   }
  } else if serviceCode=="unsupported_country_region_territory" {
   detail="OpenAI 拒绝当前检测到的国家或地区；请确认支持地区及系统授权浏览器的网络路径"
  } else if let httpCode {
   switch httpCode {
   case 401:detail="授权未被接口接受（HTTP 401），请检查授权"
   case 403:detail="接口拒绝访问（HTTP 403），可能涉及权限或访问地区"
   case 429:detail="请求受限（HTTP 429），请查看官方用量设置"
   case 500...599:detail="OpenAI 服务暂不可用（HTTP \(httpCode)）"
   default:detail="接口返回 HTTP \(httpCode)"
   }
  } else if serviceCode=="selected_model_not_available" {detail="指定模型不在当前账号的可用列表中，请重新获取列表并选择"}
  else if serviceCode=="unsupported_subscription_catalog" {detail="没有获取到可用的订阅模型"}
  else {detail="没有收到完整的有效结果"}
  let code=serviceCode.map {"；服务代码 \($0)"} ?? ""
  let caution=stage == .stream ? "；已开始的请求可能计入用量，不会自动重发" : "；不会自动重试或更换付费渠道"
  return "\(stage.title)：\(detail)\(code)\(caution)"
 }
 static func network(_ error:Error,stage:ChatGPTRequestStage)->Error {
  let raw=error as NSError
  if error is CancellationError || (raw.domain==NSURLErrorDomain && raw.code==NSURLErrorCancelled) {return CancellationError()}
  if error is ChatGPTRequestFailure {return error}
  return Self(stage:stage,networkCode:raw.domain==NSURLErrorDomain ? raw.code : nil)
 }
 static func code(in body:[String:Any])->String? {
  let error=body["error"] as? [String:Any]
  guard let code=error?["code"] as? String ?? body["error"] as? String,
        !code.isEmpty,code.count<=80,code.allSatisfy({$0.isASCII && ($0.isLetter || $0.isNumber || $0=="_")}) else{return nil}
  return code
 }
 static func unusableRefresh(_ code:String?)->Bool {
  ["invalid_grant","invalid_refresh_token","token_expired","refresh_token_expired","refresh_token_invalidated","refresh_token_reused"].contains(code ?? "")
 }
}

struct ChatGPTAvailableModel:Equatable {let id:String;let name:String}
struct ChatGPTModelCache {
 private var account=""
 private var models:[ChatGPTAvailableModel]=[]
 private var expiresAt=0.0
 mutating func clear() {account="";models=[];expiresAt=0}
 func catalog(account:String,now:Double)->[ChatGPTAvailableModel]? {self.account==account && now<expiresAt && !models.isEmpty ? models : nil}
 func value(account:String,now:Double)->ChatGPTAvailableModel? {catalog(account:account,now:now)?.first}
 mutating func store(_ model:ChatGPTAvailableModel,account:String,now:Double) {store([model],account:account,now:now)}
 mutating func store(_ models:[ChatGPTAvailableModel],account:String,now:Double) {self.models=models;self.account=account;expiresAt=now+300}
 static func parse(_ body:[String:Any])->[ChatGPTAvailableModel] {
  // This is the documented ChatGPT PLAN catalog, not the API-key catalog.
  // Keep the server's ordering and never silently switch billing paths.
  guard let models=body["models"] as? [[String:Any]] else{return []}
  var seen=Set<String>()
  return models.compactMap {item in
   guard item["visibility"] as? String=="list",let id=item["slug"] as? String,!id.isEmpty,id.count<=160,seen.insert(id).inserted else{return nil}
   return ChatGPTAvailableModel(id:id,name:item["display_name"] as? String ?? id)
  }
 }
 static func select(_ body:[String:Any])->ChatGPTAvailableModel? {parse(body).first}
 static func resolve(_ models:[ChatGPTAvailableModel],preferred:String)->ChatGPTAvailableModel? {preferred.isEmpty ? models.first : models.first(where:{$0.id==preferred})}
}

struct ChatGPTConnectivityResult:Equatable {
 let host:String
 let reachable:Bool
 let message:String
}
enum ChatGPTConnectivity {
 static func check(session:URLSession) async ->[ChatGPTConnectivityResult] {
  var results:[ChatGPTConnectivityResult]=[]
  for (host,path,expected) in [("auth.openai.com","/.well-known/openid-configuration",200),("api.openai.com","/v1/models",401)] {
   if Task.isCancelled {break}
   var request=URLRequest(url:URL(string:"https://"+host+path)!,cachePolicy:.reloadIgnoringLocalCacheData,timeoutInterval:12)
   request.httpMethod="GET"
   request.setValue("TogetherPlayer-Connectivity/0.6.23",forHTTPHeaderField:"User-Agent")
   // No bearer token, cookies, movie text or inference request is attached.
   do {
    let (_,response)=try await session.data(for:request)
    let code=(response as? HTTPURLResponse)?.statusCode ?? 0
    results.append(.init(host:host,reachable:code==expected,message:code==expected ? "\(host)：网络可达（仅连通性检查）" : "\(host)：返回 HTTP \(code)，请检查网络或访问限制"))
   } catch {
    if Task.isCancelled {break}
    let stage:ChatGPTRequestStage=host=="auth.openai.com" ? .authorization : .models
    let failure=ChatGPTRequestFailure.network(error,stage:stage)
    results.append(.init(host:host,reachable:false,message:failure.localizedDescription))
   }
  }
  return results
 }
}
