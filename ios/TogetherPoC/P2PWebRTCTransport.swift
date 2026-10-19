import Foundation
import WebKit
import SwiftUI

// WKUserContentController retains its handlers. Forward through a weak owner
// so a closed player/window can release the transport and WebKit resources.
@MainActor private final class WeakP2PScriptHandler:NSObject,WKScriptMessageHandler {
 weak var owner:P2PWebRTCTransport?
 init(_ owner:P2PWebRTCTransport){self.owner=owner;super.init()}
 func userContentController(_ userContentController:WKUserContentController,didReceive message:WKScriptMessage) {
  owner?.userContentController(userContentController,didReceive:message)
 }
}

/// Embedded transport engine for authenticated Muse P2P signaling.
/// The HTML is included in the signed app bundle. No remote script,
/// film, room token or user-supplied URL is evaluated here.
@MainActor final class P2PWebRTCTransport: NSObject, WKScriptMessageHandler {
 var onSignal: ((String,[String:Any])->Void)?
 var onState: ((String)->Void)?
 var onControl: (([String:Any])->Void)?
 private(set) var ready=false
 private var pending:[String]=[]
 let webView:WKWebView

 override init() {
  let config=WKWebViewConfiguration()
  config.websiteDataStore = .nonPersistent()
  config.allowsInlineMediaPlayback=true
  config.defaultWebpagePreferences.allowsContentJavaScript=true
  webView=WKWebView(frame:.zero,configuration:config)
  super.init()
  // WebKit's configuration is immutable for replacement after creation,
  // register the handler on its existing controller.
  webView.configuration.userContentController.add(WeakP2PScriptHandler(self),name:"togetherP2P")
  webView.isOpaque=false
  webView.backgroundColor = .clear
  if let url=Bundle.main.url(forResource:"P2PTransport",withExtension:"html"),
     let html=try? String(contentsOf:url,encoding:.utf8) {
   webView.loadHTMLString(html,baseURL:URL(string:"https://appassets.androidplatform.net"))
  } else {
   onState?("transport_asset_missing")
  }
 }
 func userContentController(_ userContentController: WKUserContentController,didReceive message: WKScriptMessage) {
  guard message.name=="togetherP2P",let body=message.body as? [String:Any],
        let event=body["event"] as? String else{return}
  switch event {
  case "ready":
   ready=true
   let queue=pending;pending.removeAll()
   queue.forEach(execute)
  case "signal":
   guard let kind=body["kind"] as? String,
         ["offer","answer","candidate","reset"].contains(kind),
         let payload=body["payload"] as? [String:Any] else{return}
   onSignal?(kind,payload)
  case "status":
   if let state=body["state"] as? String{onState?(state)}
  case "hint":
   if let hint=body["data"] as? [String:Any]{onControl?(hint)}
  case "error":
   onState?(body["reason"] as? String ?? "webrtc_error")
  default:break
  }
 }
 private func call(_ fn:String,_ args:[Any]) {
  guard let value=try? JSONSerialization.data(withJSONObject:args,options:[.fragmentsAllowed]),
        let json=String(data:value,encoding:.utf8) else{return}
  let inside=String(json.dropFirst().dropLast())
  let javascript="window.TogetherRTC && window.TogetherRTC.\(fn)(\(inside));"
  if ready{execute(javascript)}else if pending.count<64{pending.append(javascript)}
 }
 private func execute(_ script:String){webView.evaluateJavaScript(script,completionHandler:nil)}
 func start(host:Bool,peerUserID:String) {
  call("start",[["role":host ? "host" : "guest","peerId":peerUserID]])
 }
 func receiveSignal(kind:String,payload:[String:Any]) {call("signal",[kind,payload])}
 func sendControl(_ value:[String:Any]) {call("send",[value])}
 func close() {if ready {call("close",[])}}
 func dispose() {
  close()
  webView.stopLoading()
  webView.configuration.userContentController.removeScriptMessageHandler(forName:"togetherP2P")
  onSignal=nil;onState=nil;onControl=nil
 }
}

/// Attach the tiny WebKit view so WebRTC stays active in the foreground.
/// The view never intercepts touches or handles browser navigation.
struct P2PWebRTCSurface: UIViewRepresentable {
 let transport:P2PWebRTCTransport
 func makeUIView(context:Context)->WKWebView {transport.webView}
 func updateUIView(_ view:WKWebView,context:Context){}
}
