import SwiftUI
import WebKit

/// Experimental WebRTC *diagnostic* transport embedded in the iPad app.
///
/// This browser instance is isolated from the authenticated Muse room,
/// playback controls and movie files. P2P peer proof and server ACK handling
/// must be implemented before routing actual commands through it.
@MainActor enum P2PDiagnostics {
 static let endpoint = URL(string:"https://latency.xiaokai123.de5.net/p2p")!
 static let allowedHost = "latency.xiaokai123.de5.net"
 static func isAllowed(_ url: URL) -> Bool {
  url.scheme == "https" && url.host == allowedHost &&
  (url.path == "/p2p" || url.path == "/p2p/")
 }
}

struct P2PDiagnosticsView: View {
 @Environment(\.dismiss) private var dismiss
 var body: some View {
  NavigationStack {
   VStack(spacing:0) {
    Text("实验连接仅用于测试 P2P 线路，不会操作电影播放器、读取账号令牌或代替 Muse 房间。")
     .font(.caption).foregroundStyle(.secondary).padding(.horizontal,14).padding(.vertical,8)
    P2PDiagnosticsWebView()
   }
   .navigationTitle("P2P 直连测试")
   .navigationBarTitleDisplayMode(.inline)
   .toolbar {ToolbarItem(placement:.confirmationAction) {Button("关闭") {dismiss()}}}
  }
 }
}

struct P2PDiagnosticsWebView: UIViewRepresentable {
 func makeCoordinator() -> Coordinator {Coordinator()}
 func makeUIView(context: Context) -> WKWebView {
  let cfg=WKWebViewConfiguration()
  cfg.websiteDataStore = .nonPersistent()
  cfg.allowsInlineMediaPlayback=true
  let view=WKWebView(frame:.zero,configuration:cfg)
  view.navigationDelegate=context.coordinator
  view.isOpaque=false
  view.backgroundColor=UIColor(red:0.03,green:0.06,blue:0.12,alpha:1)
  view.scrollView.contentInsetAdjustmentBehavior = .never
  view.load(URLRequest(url:P2PDiagnostics.endpoint,cachePolicy:.reloadIgnoringLocalCacheData))
  return view
 }
 func updateUIView(_ uiView:WKWebView,context:Context) {}
 static func dismantleUIView(_ uiView:WKWebView,coordinator:Coordinator) {
  uiView.stopLoading()
  uiView.loadHTMLString("",baseURL:nil)
  uiView.navigationDelegate=nil
 }
 final class Coordinator: NSObject, WKNavigationDelegate {
  func webView(_ webView:WKWebView,decidePolicyFor action:WKNavigationAction,
               decisionHandler:@escaping (WKNavigationActionPolicy)->Void) {
   guard let url=action.request.url else {decisionHandler(.cancel);return}
   decisionHandler(P2PDiagnostics.isAllowed(url) ? .allow : .cancel)
  }
 }
}
