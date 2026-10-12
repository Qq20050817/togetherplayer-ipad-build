import SwiftUI
import SafariServices

// System browser inside the app, not an embedded WKWebView. We never inspect
// cookies, credentials or page content. Keeping the app foreground also keeps
// its authenticated loopback callback alive during first sign-in.
struct PlotSignInBrowser:UIViewControllerRepresentable {
 let url:URL
 let cancelled:()->Void
 func makeCoordinator()->Coordinator {Coordinator(cancelled:cancelled)}
 func makeUIViewController(context:Context)->SFSafariViewController {
  let browser=SFSafariViewController(url:url);browser.delegate=context.coordinator;return browser
 }
 func updateUIViewController(_ controller:SFSafariViewController,context:Context) {}
 final class Coordinator:NSObject,SFSafariViewControllerDelegate {
  let cancelled:()->Void
  init(cancelled:@escaping()->Void) {self.cancelled=cancelled}
  func safariViewControllerDidFinish(_ controller:SFSafariViewController) {cancelled()}
 }
}
