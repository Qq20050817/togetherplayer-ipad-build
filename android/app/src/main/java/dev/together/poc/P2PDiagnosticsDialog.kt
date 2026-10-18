package dev.together.poc

import android.app.Activity
import android.app.AlertDialog
import android.graphics.Color
import android.net.Uri
import android.webkit.WebView
import android.webkit.WebViewClient
import android.webkit.WebResourceRequest
import android.webkit.WebChromeClient
import android.view.WindowManager

/**
 * Explicit opt-in WebRTC DataChannel diagnostic in the Android app.
 *
 * Does not receive Muse tokens, room credentials or playback objects. Never
 * handles PLAY, PAUSE, SEEK or messages from the existing player. The remote
 * diagnostic service is an untrusted webpage; keep JavaScriptInterface off.
 */
object P2PDiagnosticsDialog {
 private const val HOST = "latency.xiaokai123.de5.net"
 private const val URL = "https://latency.xiaokai123.de5.net/p2p"

 fun allowed(uri: Uri): Boolean =
  uri.scheme == "https" && uri.host == HOST &&
   (uri.path == "/p2p" || uri.path == "/p2p/")

 fun show(activity: Activity) {
  if (activity.isFinishing || activity.isDestroyed) return
  val browser=WebView(activity)
  browser.setBackgroundColor(Color.rgb(8, 15, 30))
  browser.settings.apply {
   javaScriptEnabled=true
   domStorageEnabled=true
   allowFileAccess=false
   allowContentAccess=false
   javaScriptCanOpenWindowsAutomatically=false
   setSupportMultipleWindows(false)
   mixedContentMode=android.webkit.WebSettings.MIXED_CONTENT_NEVER_ALLOW
  }
  browser.webViewClient=object: WebViewClient() {
   override fun shouldOverrideUrlLoading(view:WebView,request:WebResourceRequest):Boolean =
    !allowed(request.url)
   override fun shouldOverrideUrlLoading(view:WebView,url:String):Boolean =
    !allowed(Uri.parse(url))
  }
  browser.webChromeClient=WebChromeClient()
  val dialog=AlertDialog.Builder(activity)
   .setTitle("P2P 直连测试 · 不控制电影")
   .setMessage("两人各自打开测试房间。此功能不会读取电影、网盘登录信息或 Muse 的房间凭证。")
   .setView(browser)
   .setPositiveButton("关闭",null)
   .create()
  dialog.setOnDismissListener {
   browser.stopLoading()
   browser.loadUrl("about:blank")
   browser.clearHistory()
   browser.removeAllViews()
   browser.destroy()
  }
  dialog.show()
  dialog.window?.setLayout(WindowManager.LayoutParams.MATCH_PARENT,WindowManager.LayoutParams.MATCH_PARENT)
  browser.loadUrl(URL)
 }
}
