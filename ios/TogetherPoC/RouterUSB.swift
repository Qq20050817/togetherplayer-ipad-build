import Foundation
import Combine

// LAN-only management. Password and cookies stay in this ephemeral session.
final class RouterNoRedirect: NSObject, URLSessionTaskDelegate {
 func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {completionHandler(nil)}
}
@MainActor final class RouterUSB: ObservableObject {
 @Published private(set) var working=false
 @Published private(set) var status="连接家里的 Wi-Fi，使用 U 盘影片管理密码。"
 @Published private(set) var safeToRemove=false
 private let session: URLSession
 private var sessionCookie: String?
 private let base=URL(string:"http://192.168.31.1:49186")!
 init(session: URLSession? = nil) {
  if let session {self.session=session}
  else {let c=URLSessionConfiguration.ephemeral;c.timeoutIntervalForRequest=90;c.timeoutIntervalForResource=120;self.session=URLSession(configuration:c,delegate:RouterNoRedirect(),delegateQueue:nil)}
 }
 private func request(_ path:String,body:[String:Any]?=nil,csrf:String="") async throws -> [String:Any] {
  var request=URLRequest(url:base.appendingPathComponent(path));request.timeoutInterval=90
  if let sessionCookie {request.setValue(sessionCookie,forHTTPHeaderField:"Cookie")}
  if let body {
   request.httpMethod="POST";request.httpBody=try JSONSerialization.data(withJSONObject:body)
   request.setValue("application/json",forHTTPHeaderField:"Content-Type")
   request.setValue(base.absoluteString,forHTTPHeaderField:"Origin")
   request.setValue(csrf,forHTTPHeaderField:"X-CSRF-Token")
  }
  let (data,response)=try await session.data(for:request)
  guard let response=response as? HTTPURLResponse,let value=try JSONSerialization.jsonObject(with:data) as? [String:Any] else {throw USBError.message("管理服务没有返回有效结果。")}
  if let fields=response.allHeaderFields as? [String:String],let cookie=HTTPCookie.cookies(withResponseHeaderFields:fields,for:base).first(where:{$0.name=="sid"}) {sessionCookie="sid=\(cookie.value)"}
  guard (200..<300).contains(response.statusCode) else {
   let code=value["error"] as? String ?? "unknown"
   let messages=["authentication_failed":"U 盘管理密码不正确。","login_required":"请重新输入 U 盘管理密码。","usb_busy_or_unmount_failed":"U 盘仍被占用或卸载失败。","usb_still_mounted":"U 盘仍挂载。","usb_not_mounted":"U 盘尚未挂载。","usb_identity_mismatch":"不是已登记的 U 盘。","eject_in_progress":"安全弹出正在进行，请等待。","eject_not_enabled":"路由器尚未启用安全弹出。","too_many_attempts":"密码尝试过多，请稍后再试。"]
   throw USBError.message(messages[code] ?? "路由器未完成安全弹出。")
  }
  return value
 }
 func eject(password:String) async {
  guard !working else {return};working=true;safeToRemove=false
  status="正在停止影片读取、写回缓存并安全卸载，请勿拔出…"
  defer {working=false}
  do {
   let state=try await request("api/session")
   guard state["safeEjectAvailable"] as? Bool == true else {throw USBError.message("路由器尚未启用安全弹出。")}
   guard state["needsSetup"] as? Bool != true else {throw USBError.message("请先设置 U 盘影片管理密码。")}
   guard var csrf=state["csrf"] as? String,!csrf.isEmpty else {throw USBError.message("管理会话无效。")}
   if state["authenticated"] as? Bool != true {
    guard !password.isEmpty else {throw USBError.message("请输入 U 盘影片管理密码。")}
    let login=try await request("api/login",body:["password":password],csrf:csrf)
    guard login["authenticated"] as? Bool == true,let next=login["csrf"] as? String,!next.isEmpty else {throw USBError.message("登录未成功。")}
    csrf=next
   }
   let result=try await request("api/eject",body:[:],csrf:csrf)
   guard result["safeToRemove"] as? Bool == true else {throw USBError.message("未确认卸载成功。")}
   safeToRemove=true
   status="U 盘已安全卸载，可以拔出。重新插回后等待挂载，再恢复影片。"
   if result["mediaServiceRestartRequested"] as? Bool == false {status += "影片服务启动失败，需要维护。"}
  } catch {
   let reason=(error as? USBError)?.text ?? "无法连接管理服务，请确认家里 Wi-Fi 和本地网络权限。"
   status=reason+" 未确认安全卸载，请勿拔出。"
  }
 }
 private enum USBError: Error {
  case message(String)
  var text:String {switch self {case .message(let text):return text}}
 }
}
