import Foundation

// Read at most one64KiB range. Reject HTTP200 before reading its body.
// Sampling runs off the UI thread and never involves Together Backend.
final class BaiduRangeReader: NSObject,URLSessionDataDelegate {
 struct Slice {let total: Int64;let data: Data;let url: URL}
 private let offset: Int64
 private let count: Int
 private var expected=0
 private var total: Int64=0
 private var finalURL: URL?
 private var bytes=Data()
 private var redirects=0
 private var session: URLSession?
 private var continuation: CheckedContinuation<Slice,Error>?
 private let lock=NSLock()
 init(offset: Int64,count: Int) {self.offset=offset;self.count=count}
 static func read(_ url: URL,offset: Int64,count: Int,configuration: URLSessionConfiguration?=nil) async throws -> Slice {
  guard BaiduSourceAdapter.allowedURL(url),offset>=0,(1...65536).contains(count) else {throw BaiduProbeFailure(message:"文件片段请求无效")}
  let reader=BaiduRangeReader(offset:offset,count:count)
  return try await withCheckedThrowingContinuation {c in
   reader.continuation=c
   let config=configuration ?? URLSessionConfiguration.ephemeral
   config.httpShouldSetCookies=false;config.urlCache=nil;config.timeoutIntervalForRequest=20;config.timeoutIntervalForResource=30
   let session=URLSession(configuration:config,delegate:reader,delegateQueue:nil);reader.session=session
   var request=URLRequest(url:url);request.setValue("pan.baidu.com",forHTTPHeaderField:"User-Agent");request.setValue("bytes=\(offset)-\(offset+Int64(count)-1)",forHTTPHeaderField:"Range")
   session.dataTask(with:request).resume()
  }
 }
 private func finish(_ result: Result<Slice,Error>) {
  lock.lock();let c=continuation;continuation=nil;lock.unlock()
  guard let c=c else {return};session?.invalidateAndCancel();session=nil;c.resume(with:result)
 }
 private func fail(_ message: String) {finish(.failure(BaiduProbeFailure(message:message)))}
 func urlSession(_ session: URLSession,dataTask: URLSessionDataTask,didReceive response: URLResponse,completionHandler: @escaping (URLSession.ResponseDisposition)->Void) {
  guard BaiduSourceAdapter.allowedURL(response.url),let http=response as? HTTPURLResponse,http.statusCode==206,let range=http.value(forHTTPHeaderField:"Content-Range"),range.hasPrefix("bytes ") else {completionHandler(.cancel);fail("百度直链不支持分段读取，已停止；没有下载完整影片。");return}
  let parts=range.dropFirst(6).split(separator:"/");let limits=parts.first?.split(separator:"-") ?? []
  guard parts.count==2,limits.count==2,let start=Int64(limits[0]),let end=Int64(limits[1]),let size=Int64(parts[1]),size>0,size<=9007199254740991,start==offset,end==min(offset+Int64(count)-1,size-1),end>=start else {completionHandler(.cancel);fail("文件分段范围无效，请重新选择");return}
  finalURL=response.url;total=size;expected=Int(end-start+1);completionHandler(.allow)
 }
 func urlSession(_ session: URLSession,dataTask: URLSessionDataTask,didReceive data: Data) {
  guard expected>0,bytes.count+data.count<=expected else {fail("文件片段超过请求范围，已停止读取");return}
  bytes.append(data)
 }
 func urlSession(_ session: URLSession,task: URLSessionTask,didCompleteWithError error: Error?) {
  if error==nil,expected>0,bytes.count==expected,let url=finalURL {finish(.success(Slice(total:total,data:bytes,url:url)))}
  else {fail("文件片段读取未完成，请检查本人授权与网络")}
 }
 func urlSession(_ session: URLSession,task: URLSessionTask,willPerformHTTPRedirection response: HTTPURLResponse,newRequest request: URLRequest,completionHandler: @escaping (URLRequest?)->Void) {
  redirects += 1
  guard redirects<=5,BaiduSourceAdapter.allowedURL(request.url) else {completionHandler(nil);fail("文件源跳转无效，已停止读取");return}
  var next=request;next.setValue("pan.baidu.com",forHTTPHeaderField:"User-Agent");next.setValue("bytes=\(offset)-\(offset+Int64(count)-1)",forHTTPHeaderField:"Range");completionHandler(next)
 }
}
