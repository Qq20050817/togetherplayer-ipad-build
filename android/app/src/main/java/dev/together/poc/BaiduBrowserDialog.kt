package dev.together.poc
import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.widget.*
import android.text.method.PasswordTransformationMethod
import java.util.concurrent.Executors

class BaiduBrowserDialog(private val activity:Activity,private val adapter:BaiduSourceAdapter,private val title:String,private val use:(BaiduFile,String)->Boolean,private val clear:()->Unit,private val openAuthorization:(Intent)->Unit = {activity.startActivity(it)}) {
 private val main=Handler(Looper.getMainLooper());private val worker=Executors.newSingleThreadExecutor()
 private var epoch=0;private var busy=false;private var directory="/";private var page=0
 private var selection:Pair<BaiduFile,String>?=null
 private lateinit var status:TextView;private lateinit var files:LinearLayout;private lateinit var path:EditText;private lateinit var dialog:AlertDialog
 private fun button(body:LinearLayout,text:String,action:()->Unit)=Button(activity).apply {this.text=text;isAllCaps=false;body.addView(this);setOnClickListener {action()}}
 private fun label(body:LinearLayout,text:String)=TextView(activity).apply {this.text=text;setPadding(0,12,0,12);body.addView(this)}
 fun show() {
  val body=LinearLayout(activity).apply {orientation=LinearLayout.VERTICAL;setPadding(24,16,24,16)}
  label(body,"${if(title.isBlank())"房主选择影片后发布到房间" else "房间影片：$title"}\n好友需先转存同一文件，各自授权取流。")
  label(body,"百度官方个人限时体验，非正式应用接入。授权页应用名 mcp_server，申请网盘读写权限；本功能仅读取。授权留在本机内存，退出App不保存。")
  button(body,"打开官方体验授权页") {
   try {openAuthorization(Intent(Intent.ACTION_VIEW,Uri.parse(BaiduSourceAdapter.AUTHORIZE)))}
   catch(e:android.content.ActivityNotFoundException){status.text="没有可用浏览器。请复制授权页链接，在浏览器中打开。"}
   catch(e:SecurityException){status.text="系统阻止打开浏览器。请复制授权页链接，在浏览器中打开。"}
  }
  button(body,"复制授权页链接") {
   val clipboard=activity.getSystemService(android.content.Context.CLIPBOARD_SERVICE) as android.content.ClipboardManager
   clipboard.setPrimaryClip(android.content.ClipData.newPlainText("百度官方授权页",BaiduSourceAdapter.AUTHORIZE));status.text="授权页链接已复制，请在浏览器中打开。"
  }
  val auth=EditText(activity).apply {hint="本人授权返回的 Token 或完整回跳链接";transformationMethod=PasswordTransformationMethod.getInstance();inputType=android.text.InputType.TYPE_CLASS_TEXT or android.text.InputType.TYPE_TEXT_VARIATION_PASSWORD;isSaveEnabled=false;body.addView(this)}
  button(body,"应用授权并读取文件") {if(!busy)try {adapter.authorize(auth.text.toString());auth.setText("");load("/",0)}catch(e:Exception){status.text="授权格式无效；不要输入密码或 Cookie。"}}
  button(body,"清除本机百度授权") {epoch++;busy=false;adapter.clear();selection=null;files.removeAllViews();clear();status.text="授权已清除；请重新授权后选片。"}
  status=label(body,if(adapter.authorized())"本机已授权，可以读取目录" else "尚未授权")
  path=EditText(activity).apply {hint="目录，例如 /电影";setText("/");body.addView(this)}
  button(body,"读取目录") {load(path.text.toString(),0)}
  val nav=LinearLayout(activity);body.addView(nav)
  button(nav,"根目录") {load("/",0)};button(nav,"上一页") {if(page>0)load(directory,page-1)};button(nav,"下一页") {load(directory,page+1)}
  files=LinearLayout(activity).apply {orientation=LinearLayout.VERTICAL};body.addView(files)
  button(body,"使用选中的影片进行同步") {selection?.let {(f,u)->if(use(f,u))dialog.dismiss() else {status.text="片源尚未应用，请检查房间连接及文件是否匹配后重试。"}} ?: run {status.text="请先从列表选择影片。"}}
  label(body,"核对百度返回的文件指纹和大小后，双方准备好才可播放。转存不会提前下载整部影片；在线播放速度仍取决于账户与网络。")
  val scroll=ScrollView(activity).apply {addView(body)}
  dialog=AlertDialog.Builder(activity).setTitle("百度网盘 · 房间选片").setView(scroll).setNegativeButton("返回",null).create()
  dialog.setOnDismissListener {epoch++;worker.shutdownNow()};dialog.show()
  if(adapter.authorized())load("/",0)
 }
 private fun load(dir:String,p:Int) {
  if(busy)return
  if(!adapter.authorized()){status.text="请先完成本人百度授权。";return}
  if(!dir.startsWith('/') || p<0){status.text="目录必须以 / 开头";return}
  selection=null;run("正在读取目录…",{adapter.list(dir,p)}) {list->directory=dir;page=p;path.setText(dir);files.removeAllViews();status.text="第${p+1}页，共${list.size}项";list.forEach {f->button(files,(if(f.directory)"文件夹 · " else "影片 · ")+f.name){if(f.directory)load(f.path,0)else select(f)}}}
 }
 private fun select(file:BaiduFile) {
  selection=null
  run("正在取得本机授权片源…",{adapter.playable(file)}) {result->selection=result;status.text="已选择：${result.first.name}。点下方按钮匹配房间影片。"}
 }
 private fun <T> run(message:String,job:()->T,done:(T)->Unit) {
  if(busy)return;busy=true;val g=++epoch;status.text=message
  worker.execute {try {val result=job();main.post {if(g==epoch){busy=false;done(result)}}}catch(e:Exception){main.post {if(g==epoch){busy=false;status.text="百度读取失败；请检查授权、网盘访问权限和网络后重试。"}}}}
 }
}
