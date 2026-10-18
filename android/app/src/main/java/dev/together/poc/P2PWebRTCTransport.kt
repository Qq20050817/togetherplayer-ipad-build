package dev.together.poc

import android.app.Activity
import android.graphics.Color
import android.os.Handler
import android.os.Looper
import android.view.ViewGroup
import android.webkit.JavascriptInterface
import android.webkit.WebView
import android.webkit.WebViewClient
import android.webkit.WebResourceRequest
import android.net.Uri
import org.json.JSONArray
import org.json.JSONObject

/**
 * Signed-app asset WebRTC transport. Uses native Muse WebSocket for the
 * authenticated SDP/ICE exchange and WebRTC only for peer DataChannel frames.
 * No Muse credentials, video files, Baidu login or room tokens reach the JS.
 */
class P2PWebRTCTransport(private val activity:Activity) {
 var onSignal:((String,JSONObject)->Unit)?=null
 var onState:((String)->Unit)?=null
 var onControl:((JSONObject)->Unit)?=null
 private val handler=Handler(Looper.getMainLooper())
 private var ready=false
 private var destroyed=false
 private val pending=ArrayDeque<String>()
 val view:WebView=WebView(activity)
 init {
  view.setBackgroundColor(Color.TRANSPARENT)
  view.settings.apply {
   javaScriptEnabled=true
   domStorageEnabled=false
   allowFileAccess=false
   allowContentAccess=false
   javaScriptCanOpenWindowsAutomatically=false
   mixedContentMode=android.webkit.WebSettings.MIXED_CONTENT_NEVER_ALLOW
  }
  view.webViewClient=object:WebViewClient() {
   override fun shouldOverrideUrlLoading(view:WebView,request:WebResourceRequest)=true
   override fun shouldOverrideUrlLoading(view:WebView,url:String)=true
  }
  view.addJavascriptInterface(object {
   @JavascriptInterface fun postMessage(text:String) {
    if(text.length>4096)return
    handler.post { if(!destroyed)handleMessage(text) }
   }
  },"TogetherP2PAndroid")
  // The only HTML loaded comes from local application assets.
  val html=activity.assets.open("p2p-transport.html").bufferedReader().use{it.readText()}
  view.loadDataWithBaseURL("https://appassets.androidplatform.net/p2p",html,"text/html","UTF-8",null)
 }
 private fun handleMessage(text:String) {
  val obj=runCatching{JSONObject(text)}.getOrNull()?:return
  when(obj.optString("event")){
   "ready"->{
    ready=true
    while(pending.isNotEmpty())eval(pending.removeFirst())
   }
   "signal"->{
    val kind=obj.optString("kind")
    val payload=obj.optJSONObject("payload")?:return
    if(kind in listOf("offer","answer","candidate","reset"))onSignal?.invoke(kind,payload)
   }
   "status"->onState?.invoke(obj.optString("state"))
   "hint"->obj.optJSONObject("data")?.let{onControl?.invoke(it)}
   "error"->onState?.invoke(obj.optString("reason","webrtc_error"))
  }
 }
 private fun invoke(method:String,args:JSONArray) {
  if(destroyed)return
  val raw=args.toString()
  val inside=raw.substring(1,raw.length-1)
  val js="window.TogetherRTC && window.TogetherRTC.$method($inside);"
  if(ready)eval(js)else if(pending.size<64)pending.addLast(js)
 }
 private fun eval(js:String) {if(!destroyed)view.evaluateJavascript(js,null)}
 fun start(host:Boolean,peerUserId:String){
  invoke("start",JSONArray().put(JSONObject().put("role",if(host)"host" else "guest").put("peerId",peerUserId)))
 }
 fun receiveSignal(kind:String,payload:JSONObject){
  invoke("signal",JSONArray().put(kind).put(payload))
 }
 fun sendControl(hint:JSONObject){invoke("send",JSONArray().put(hint))}
 fun close(){if(!destroyed)invoke("close",JSONArray())}
 fun dispose(){
  if(destroyed)return
  close();destroyed=true
  view.stopLoading()
  (view.parent as? ViewGroup)?.removeView(view)
  view.removeJavascriptInterface("TogetherP2PAndroid")
  view.destroy()
  pending.clear()
  onSignal=null;onState=null;onControl=null
 }
 fun attach(){
  (activity.findViewById<ViewGroup>(android.R.id.content))?.addView(
    view,ViewGroup.LayoutParams(1,1))
  view.alpha=0.01f
  view.isClickable=false
 }
}
