import Foundation

// Only official account-owner READ APIs. No room backend, sharing, upload,
// delete, account cookie, refresh token or credential persistence.
struct BaiduFile: Identifiable {
 let id: Int64
 let name: String
 let path: String
 let size: Int64
 let fingerprint: String
 let isDirectory: Bool
}
struct BaiduProbeFailure: LocalizedError {
 let message: String
 var errorDescription: String? {message}
}
final class BaiduSourceAdapter {
 private let session: URLSession
 init() {
  let c=URLSessionConfiguration.ephemeral
  c.httpShouldSetCookies=false;c.urlCache=nil
  c.requestCachePolicy = .reloadIgnoringLocalCacheData
  c.timeoutIntervalForRequest=20
  session=URLSession(configuration:c)
 }
 func listFiles(token: String,directory: String,page: Int) async throws -> [BaiduFile] {
  let v=try await read(path:"/rest/2.0/xpan/file",token:token,query:["method":"list","dir":directory,"start":String(page*100),"limit":"100","order":"name","desc":"0"])
  guard let list=v["list"] as? [[String:Any]] else {throw BaiduProbeFailure(message:"百度未返回文件列表")}
  return list.compactMap { item -> BaiduFile? in
   guard let id=item["fs_id"] as? NSNumber,let path=item["path"] as? String else {return nil}
   return BaiduFile(id:id.int64Value,name:(item["server_filename"] ?? item["filename"]) as? String ?? path,path:path,size:BaiduFileIdentity.size(item["size"]) ?? 0,fingerprint:BaiduFileIdentity.provider(item["md5"]) ?? "",isDirectory:(item["isdir"] as? NSNumber)?.intValue == 1)
  }
 }
 func requestPlayableSource(token: String,file: BaiduFile) async throws -> (URL,BaiduFile) {
  let fsids=String(data:try JSONSerialization.data(withJSONObject:[file.id]),encoding:.utf8)!
  let v=try await read(path:"/rest/2.0/xpan/multimedia",token:token,query:["method":"filemetas","dlink":"1","fsids":fsids])
  guard let list=v["list"] as? [[String:Any]],let info=list.first,
   (info["fs_id"] as? NSNumber)?.int64Value == file.id,
   let link=info["dlink"] as? String,var parts=URLComponents(string:link),Self.allowedURL(parts.url) else {throw BaiduProbeFailure(message:"没有取得允许的百度 HTTPS 文件源；不放宽权限或使用其他账号")}
  var query=parts.queryItems ?? [];query.removeAll {$0.name.lowercased()=="access_token"}
  query.append(URLQueryItem(name:"access_token",value:token));parts.queryItems=query
  guard let url=parts.url else {throw BaiduProbeFailure(message:"百度文件源格式无效")}
  let merged=BaiduFileIdentity.merge(info:info,file:file)
  var size=merged.size;var fingerprint=merged.fingerprint
  var playbackURL=url
  // Always use the same sampled-byte identity on both accounts; API fields may differ.
  do {
   let first=try await BaiduRangeReader.read(url,offset:0,count:65536)
   size=first.total
   // PrismCore deliberately refuses redirects. Reuse the verified final origin,
   // rather than handing its reader the API redirect URL. This stays local.
   playbackURL=first.url
   var samples=[(Int64(0),first.data)]
   for offset in BaiduFileIdentity.offsets(size:size).dropFirst() {
    let part=try await BaiduRangeReader.read(playbackURL,offset:offset,count:Int(min(65536,size-offset)))
    guard part.total==size else {throw BaiduProbeFailure(message:"文件大小在读取过程中发生变化，请重新选择")}
    samples.append((offset,part.data))
   }
   fingerprint=BaiduFileIdentity.sample(size:size,samples:samples)
  }
  let selected=BaiduFile(id:file.id,name:file.name,path:file.path,size:size,fingerprint:fingerprint,isDirectory:false)
  return (playbackURL,selected)
 }
 static func allowedURL(_ url: URL?) -> Bool {
  guard let url=url,url.scheme=="https",url.user==nil,url.password==nil,let host=url.host?.lowercased() else {return false}
  return ["baidu.com","baidupcs.com","bcebos.com"].contains {host==$0 || host.hasSuffix("."+$0)}
 }
 private func read(path: String,token: String,query: [String:String]) async throws -> [String:Any] {
  guard !token.isEmpty else {throw BaiduProbeFailure(message:"请先输入官方体验授权信息")}
  var u=URLComponents();u.scheme="https";u.host="pan.baidu.com";u.path=path
  u.queryItems=(query.merging(["access_token":token]) {_,new in new}).map {URLQueryItem(name:$0.key,value:$0.value)}
  var request=URLRequest(url:u.url!);request.httpMethod="GET"
  request.setValue("pan.baidu.com",forHTTPHeaderField:"User-Agent")
  let (data,response)=try await session.data(for:request)
  guard let http=response as? HTTPURLResponse,http.statusCode==200,data.count<=2_000_000 else {throw BaiduProbeFailure(message:"百度接口请求失败，请检查网络与授权")}
  guard let v=try JSONSerialization.jsonObject(with:data) as? [String:Any] else {throw BaiduProbeFailure(message:"百度接口返回格式无法解析")}
  if let errno=(v["errno"] ?? v["error_code"]) as? NSNumber,errno.intValue != 0 {throw BaiduProbeFailure(message:"百度接口拒绝请求，错误码 \(errno.intValue)。体验授权可能失效或不允许该接口。")}
  return v
 }
}

// Bounded 64 KiB GET Range diagnostic. A server that ignores Range is cancelled
// before reading its whole movie. Credentials never appear in the result.
final class RangeProbe: NSObject,URLSessionDataDelegate {
 private var continuation: CheckedContinuation<String,Error>?
 private var session: URLSession?
 private var remaining=65536
 private var received=0
 private var range=""
 private let lock=NSLock()
 static func run(_ url: URL) async throws -> String {
  let probe=RangeProbe()
  return try await withCheckedThrowingContinuation {c in
   probe.continuation=c
   let config=URLSessionConfiguration.ephemeral;config.httpShouldSetCookies=false;config.urlCache=nil;config.timeoutIntervalForRequest=20
   let session=URLSession(configuration:config,delegate:probe,delegateQueue:nil);probe.session=session
   var r=URLRequest(url:url);r.setValue("bytes=0-65535",forHTTPHeaderField:"Range");r.setValue("pan.baidu.com",forHTTPHeaderField:"User-Agent")
   session.dataTask(with:r).resume()
  }
 }
 private func finish(_ result: Result<String,Error>) {
  lock.lock();let c=continuation;continuation=nil;lock.unlock()
  guard let c=c else {return};session?.invalidateAndCancel();session=nil;c.resume(with:result)
 }
 func urlSession(_ session: URLSession,dataTask: URLSessionDataTask,didReceive response: URLResponse,completionHandler: @escaping (URLSession.ResponseDisposition)->Void) {
  guard let http=response as? HTTPURLResponse else {completionHandler(.cancel);finish(.failure(BaiduProbeFailure(message:"文件源没有HTTP响应")));return}
  guard http.statusCode==206,let value=http.value(forHTTPHeaderField:"Content-Range"),value.hasPrefix("bytes 0-") else {
   completionHandler(.cancel);finish(.success("Range未通过：HTTP \(http.statusCode)；没有下载整部影片。"));return
  }
  range=value;completionHandler(.allow)
 }
 func urlSession(_ session: URLSession,dataTask: URLSessionDataTask,didReceive data: Data) {
  received += min(remaining,data.count);remaining=max(0,remaining-data.count)
  if remaining==0 {finish(.success("Range通过：\(range)，读取\(received)字节。这不等于解码或Seek已通过。"))}
 }
 func urlSession(_ session: URLSession,task: URLSessionTask,didCompleteWithError error: Error?) {
  if received>0 && error==nil {finish(.success("Range通过：\(range)，读取\(received)字节。"))}
  else {finish(.failure(BaiduProbeFailure(message:"Range读取未完成，请检查授权与网络")))}
 }
 func urlSession(_ session: URLSession,task: URLSessionTask,willPerformHTTPRedirection response: HTTPURLResponse,newRequest request: URLRequest,completionHandler: @escaping (URLRequest?)->Void) {
  guard BaiduSourceAdapter.allowedURL(request.url) else {completionHandler(nil);finish(.failure(BaiduProbeFailure(message:"文件源跳转到允许范围以外，已停止")));return}
  completionHandler(request)
 }
}
