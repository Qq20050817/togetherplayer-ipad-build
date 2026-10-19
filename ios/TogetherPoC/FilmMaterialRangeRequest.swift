import Foundation

// Bounded HTTP HEAD/Range probe for USB-hosted originals. Refuse a server
// that ignores Range before its 20–50 GB response reaches the app's memory.
final class FilmMaterialRangeRequest:NSObject,URLSessionDataDelegate {
 private let limit:Int
 private let expectedStatus:Int
 private let followRedirects:Bool
 private var received=Data()
 private var http:HTTPURLResponse?
 private var failed=false
 private let finished=DispatchSemaphore(value:0)
 private var asyncCompletion:((Data,HTTPURLResponse)?)->Void = {_ in}
 private let cancellation=RangeRequestCancellation()

 init(limit:Int,expectedStatus:Int,followRedirects:Bool=true) {
  self.limit=limit;self.expectedStatus=expectedStatus;self.followRedirects=followRedirects;super.init()
 }
 func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,newRequest:URLRequest,completionHandler:@escaping(URLRequest?)->Void) {
  completionHandler(followRedirects ? newRequest : nil)
 }
 func urlSession(_ session:URLSession,dataTask:URLSessionDataTask,didReceive response:URLResponse,completionHandler:@escaping (URLSession.ResponseDisposition)->Void) {
  guard let response=response as? HTTPURLResponse,response.statusCode==expectedStatus else {
   failed=true;completionHandler(.cancel);return
  }
  http=response;completionHandler(.allow)
 }
 func urlSession(_ session:URLSession,dataTask:URLSessionDataTask,didReceive data:Data) {
  guard received.count+data.count<=limit else {
   failed=true;dataTask.cancel();return
  }
  received.append(data)
 }
 func urlSession(_ session:URLSession,task:URLSessionTask,didCompleteWithError error:Error?) {
  if error != nil {failed=true}
  finished.signal()
  let completion=asyncCompletion;asyncCompletion={_ in}
  cancellation.clear()
  completion(!failed ? http.map{(received,$0)} : nil)
 }
 // Automatic bank restoration must suspend the Swift task, not occupy a
 // cooperative worker while URLSession's delegate is waiting for a worker.
 func fetchAsync(request:URLRequest,configuration:URLSessionConfiguration) async throws->(Data,HTTPURLResponse)? {
  let result=try await withTaskCancellationHandler(operation:{
   try Task.checkCancellation()
   return await withCheckedContinuation {continuation in
    let settings=configuration.copy() as? URLSessionConfiguration ?? .ephemeral
    settings.urlCache=nil;settings.requestCachePolicy = .reloadIgnoringLocalCacheData
    settings.timeoutIntervalForRequest=45;settings.timeoutIntervalForResource=60
    let queue=OperationQueue();queue.maxConcurrentOperationCount=1
    let session=URLSession(configuration:settings,delegate:self,delegateQueue:queue)
    asyncCompletion={value in session.finishTasksAndInvalidate();continuation.resume(returning:value)}
    let task=session.dataTask(with:request)
    cancellation.install(task);task.resume()
   }
  },onCancel:{self.cancellation.cancel()})
  try Task.checkCancellation()
  return result
 }
 func fetch(request:URLRequest,configuration:URLSessionConfiguration)->(Data,HTTPURLResponse)? {
  let settings=configuration.copy() as? URLSessionConfiguration ?? .ephemeral
  settings.urlCache=nil
  settings.requestCachePolicy = .reloadIgnoringLocalCacheData
  settings.timeoutIntervalForRequest=45
  settings.timeoutIntervalForResource=60
  let queue=OperationQueue();queue.maxConcurrentOperationCount=1
  let session=URLSession(configuration:settings,delegate:self,delegateQueue:queue)
  let task=session.dataTask(with:request)
  task.resume()
  while finished.wait(timeout:.now()+0.2) == .timedOut {
   if Task.isCancelled {session.invalidateAndCancel();return nil}
  }
  session.finishTasksAndInvalidate()
  guard !Task.isCancelled,!failed,let http else{return nil}
  return (received,http)
 }
}

// Cancellation may arrive before the continuation has installed its task.
private final class RangeRequestCancellation:@unchecked Sendable {
 private let lock=NSLock()
 private var cancelled=false
 private var task:URLSessionTask?
 func install(_ next:URLSessionTask) {
  lock.lock();task=next;let stop=cancelled;lock.unlock()
  if stop {next.cancel()}
 }
 func cancel() {
  lock.lock();cancelled=true;let current=task;lock.unlock()
  current?.cancel()
 }
 func clear() {lock.lock();task=nil;lock.unlock()}
}
