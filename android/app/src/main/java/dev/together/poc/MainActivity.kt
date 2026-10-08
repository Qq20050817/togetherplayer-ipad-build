package dev.together.poc
import android.app.Activity
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.Editable
import android.text.TextWatcher
import android.view.View
import android.view.WindowManager
import android.widget.*
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.analytics.AnalyticsListener
import androidx.media3.ui.PlayerView
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.io.IOException
import java.util.UUID
import java.util.concurrent.TimeUnit
import kotlin.math.abs
class Media3Adapter(private val p: ExoPlayer): PlayerAdapter {
 override fun play(){if(!p.playWhenReady)p.play()};override fun pause(){if(p.playWhenReady)p.pause()};override fun seekTo(positionMs: Long){p.seekTo(positionMs)}
 override fun getPosition()=p.currentPosition;override fun getDuration()=p.duration.coerceAtLeast(0);override fun isBuffering()=p.playbackState==Player.STATE_BUFFERING
 override fun isReady()=p.playbackState==Player.STATE_READY || p.playbackState==Player.STATE_ENDED
 override fun setPlaybackSpeed(speed: Float){if(p.playbackParameters.speed!=speed)p.setPlaybackSpeed(speed)}
}
class MainActivity: Activity() {
 private val main=Handler(Looper.getMainLooper());private val http=OkHttpClient.Builder().pingInterval(15,TimeUnit.SECONDS).build()
 private lateinit var player: ExoPlayer;private lateinit var engine: SyncEngine;private val clock=ClockSync();private val chat=ChatEngine()
 private lateinit var server: EditText;private lateinit var media: EditText;private lateinit var roomInput: EditText;private lateinit var seek: EditText
 private lateinit var status: TextView;private lateinit var requestStatus: TextView;private lateinit var titleField: EditText;private lateinit var nickname: EditText
 private lateinit var offset: EditText;private lateinit var localSource: EditText;private lateinit var localFileLabel: TextView;private lateinit var roomTitle: TextView;private lateinit var presence: TextView;private lateinit var notice: TextView
 private lateinit var waitToggle: Switch;private var settingWait=false;private lateinit var chatBubbles: LinearLayout;private lateinit var chatText: TextView;private lateinit var chatScroll: ScrollView
 private lateinit var watchHeading: LinearLayout;private lateinit var optionsRow: LinearLayout;private lateinit var optionsToggle: Button
 private lateinit var draft: EditText;private lateinit var typing: TextView;private lateinit var videoBox: FrameLayout;private lateinit var watchTab: Button;private lateinit var approveButton: Button
 private var credentials: JSONObject?=null;private var ws: WebSocket?=null;private var connected=false;private var stopped=false;private var foreground=false
 private var registering=false;private var generation=0;private var attempt=0;private var sequence=0L;private var pending: JSONObject?=null;private var loadedURL="";private var ticks=0;private var isHost=false
 private var pendingLocalMovie:Pair<android.net.Uri,Int>?=null
 private var pendingLocalRoom="";private var pendingLocalMedia=""
 private var localSelectionGeneration=0;private var localSelectionPublishes=true
 private val baidu=BaiduSourceAdapter();private var baiduURL="";private var baiduSourceID="";private var baiduSourceRoom="";private var localSourceRoomID="";private var localFileUri="";private var localFileName=""
 private var activeLocalSource="";private var localSourceRoom="";private var lastTyping=0.0;private val queued=ArrayDeque<JSONObject>();private var inFlight: JSONObject?=null;private var flightSequence=0L;private var retry=0
 private val outbox=LinkedHashMap<String,JSONObject>();private var chatRoom=""
 private val clientVersion by lazy {packageManager.getPackageInfo(packageName,0).versionName ?: "unknown"}
 private lateinit var watchBody: LinearLayout;private lateinit var videoColumn: LinearLayout;private lateinit var chatColumn: LinearLayout;private lateinit var progress: SeekBar;private lateinit var timeLabel: TextView;private lateinit var pauseButton: ImageButton
 private lateinit var volumeSlider: SeekBar;private var lastAudibleVolume=1f;private lateinit var durationLabel: TextView;private lateinit var mediaBadge: TextView;private var memberSummary="";private var onlineMembers=0
 private lateinit var captions: TextView;private var external: ExternalSubtitle?=null;private var subtitleName="";private var subtitleDelay=0L;private var subtitleEnabled=false;private var subtitleGeneration=0
 private var fullscreenDialog: android.app.Dialog?=null;private var fullscreenControls: LinearLayout?=null;private var fullscreenTime: TextView?=null;private var draggingProgress=false;private var screenRoot: LinearLayout?=null
 private val danmakuPending=ArrayDeque<Triple<String,Double,Long>>();private val danmakuLanes=BooleanArray(3);private var danmakuSize=24f
 private lateinit var voice:VoiceDanmakuController
 private val voiceViews=mutableListOf<VoiceDanmakuView>()
 private var voiceConnected=false
 private val hideControls=Runnable {if(!voice.busy)fullscreenControls?.visibility=View.GONE}
 private fun dp(n: Int)=(n*resources.displayMetrics.density).toInt()
 private fun field(parent: LinearLayout,hintText: String,default: String="")=EditText(this).apply {hint=hintText;setText(default);maxLines=3;parent.addView(this)}
 private fun button(parent: LinearLayout,label: String,action:()->Unit)=Button(this).apply {text=label;isAllCaps=false;minWidth=0;minimumWidth=0;textSize=13f;setTextColor(-1);setPadding(dp(12),dp(6),dp(12),dp(6));background=android.graphics.drawable.RippleDrawable(android.content.res.ColorStateList.valueOf(0x40ffffff),rounded(0xff202a33.toInt(),12),null);setOnClickListener {action()};parent.addView(this,LinearLayout.LayoutParams(-2,dp(44)).apply {setMargins(dp(3),dp(3),dp(3),dp(3))})}
 private fun row(parent: LinearLayout)=LinearLayout(this).also {parent.addView(it)}
 private fun label(parent: LinearLayout,value: String="")=TextView(this).apply {text=value;setTextColor(0xffeeeeee.toInt());parent.addView(this)}
 private fun rounded(color: Int,radius: Int=16)=android.graphics.drawable.GradientDrawable().apply {setColor(color);cornerRadius=dp(radius).toFloat()}
 private fun icon(parent: LinearLayout,resource: Int,description: String,size: Int=44,color: Int=0x00000000,tint: Int=0xfff1f4f7.toInt(),action:()->Unit): ImageButton {
  return ImageButton(this).apply {contentDescription=description;setImageResource(resource);imageTintList=android.content.res.ColorStateList.valueOf(tint);scaleType=ImageView.ScaleType.CENTER_INSIDE;setPadding(dp(if(size>=60)16 else 10),dp(10),dp(if(size>=60)16 else 10),dp(10));background=android.graphics.drawable.RippleDrawable(android.content.res.ColorStateList.valueOf(0x40ffffff),rounded(color,size/2),rounded(-1,size/2));setOnClickListener {action()};parent.addView(this,LinearLayout.LayoutParams(dp(size),dp(size)))}
 }
 private fun emojiPicker(){if(!connected){Toast.makeText(this,"请先加入房间",Toast.LENGTH_SHORT).show();return};android.app.AlertDialog.Builder(this).setTitle("发送表情").setItems(arrayOf("😂","😱","😭","🤯","❤️","👀")){_,i->send(JSONObject().put("type","REACTION").put("data",JSONObject().put("emoji",listOf("😂","😱","😭","🤯","❤️","👀")[i])))}.show()}
 private fun membersDialog(){android.app.AlertDialog.Builder(this).setTitle("房间成员").setMessage(memberSummary.ifBlank {"尚未加入房间"}).setPositiveButton("完成",null).show()}
 override fun onCreate(savedInstanceState: Bundle?) {
  super.onCreate(savedInstanceState);window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
  // Keep a reserve before starting/resuming; a short reserve repeatedly drains on slow sources.
  val buffering=DefaultLoadControl.Builder().setBufferDurationsMs(30000,60000,8000,12000).setPrioritizeTimeOverSizeThresholds(true).build()
  val renderers=PlaybackRenderers.create(this)
  player=ExoPlayer.Builder(this,renderers).setLoadControl(buffering).build();engine=SyncEngine(Media3Adapter(player),clock)
  voice=VoiceDanmakuController(this,player,{if(connected)engine.room?.optString("roomId") ?: "" else ""},{sendVoice(it)},{voiceViews.forEach {it.render()};if(voice.busy){main.removeCallbacks(hideControls);fullscreenControls?.visibility=View.VISIBLE}else if(fullscreenDialog!=null)revealControls()})
  buildInterface()
  savedInstanceState?.let {state->
   pendingLocalRoom=state.getString("localPickerRoom","");pendingLocalMedia=state.getString("localPickerMedia","")
   localSelectionPublishes=state.getBoolean("localPickerPublish",true);localSelectionGeneration=state.getInt("localPickerGeneration",0)
   state.getString("localPickerUri")?.let {pendingLocalMovie=android.net.Uri.parse(it) to state.getInt("localPickerFlags",0)}
  }
  player.addAnalyticsListener(object: AnalyticsListener {
   override fun onBandwidthEstimate(eventTime: AnalyticsListener.EventTime,totalLoadTimeMs: Int,totalBytesLoaded: Long,bitrateEstimate: Long){diagnostic("bandwidthEstimate",JSONObject().put("loadTimeMs",totalLoadTimeMs).put("bytesLoaded",totalBytesLoaded).put("bitrateEstimate",bitrateEstimate))}
   override fun onDroppedVideoFrames(eventTime: AnalyticsListener.EventTime,droppedFrames: Int,elapsedMs: Long){diagnostic("droppedVideoFrames",JSONObject().put("droppedFrames",droppedFrames))}
   override fun onAudioUnderrun(eventTime: AnalyticsListener.EventTime,bufferSize: Int,bufferSizeMs: Long,elapsedSinceLastFeedMs: Long){diagnostic("audioUnderrun")}
  })
  player.addListener(object: Player.Listener {
   override fun onPlayerError(error: androidx.media3.common.PlaybackException){
    val exo=error as? androidx.media3.exoplayer.ExoPlaybackException
    val mime=exo?.rendererFormat?.sampleMimeType ?: "未知编码"
    val trackType=androidx.media3.common.MimeTypes.getTrackType(exo?.rendererFormat?.sampleMimeType)
    val kind=when(trackType){androidx.media3.common.C.TRACK_TYPE_VIDEO->"视频";androidx.media3.common.C.TRACK_TYPE_AUDIO->"音频";else->"片源"}
    val details=JSONObject().put("code",error.errorCodeName).put("rendererType",trackType).put("mimeType",mime)
    var cause:Throwable?=error.cause
    while(cause!=null){if(cause is androidx.media3.exoplayer.mediacodec.MediaCodecRenderer.DecoderInitializationException){details.put("codecName",cause.codecInfo?.name ?: "none").put("decoderMimeType",cause.mimeType);break};cause=cause.cause}
    diagnostic("playerError",details)
    requestStatus.text="$kind 播放失败：${error.errorCodeName}（$mime）。可点“重试播放”；若4K HEVC不受设备支持，需使用兼容版本。"
   }
   override fun onPlaybackStateChanged(playbackState: Int){diagnostic("playbackStateChanged")}
   override fun onPlaybackParametersChanged(playbackParameters: androidx.media3.common.PlaybackParameters){diagnostic("speedChanged")}
   override fun onPositionDiscontinuity(oldPosition: Player.PositionInfo,newPosition: Player.PositionInfo,reason: Int){diagnostic("positionDiscontinuity",JSONObject().put("reason",reason))}
  })
  getPreferences(0).getString("credentials",null)?.let {runCatching {credentials=RoomCredentials.parse(it);roomInput.setText(credentials!!.getString("roomId"))}};main.post(tick)
 }
 override fun onStart(){super.onStart();foreground=true;if(credentials!=null)connect()}
 override fun onSaveInstanceState(state:Bundle){
  state.putString("localPickerRoom",pendingLocalRoom);state.putString("localPickerMedia",pendingLocalMedia)
  state.putBoolean("localPickerPublish",localSelectionPublishes);state.putInt("localPickerGeneration",localSelectionGeneration)
  pendingLocalMovie?.let {state.putString("localPickerUri",it.first.toString());state.putInt("localPickerFlags",it.second)}
  super.onSaveInstanceState(state)
 }
 override fun onStop(){voice.disable();foreground=false;generation++;connected=false;ws?.cancel();ws=null;engine.resetSession();player.stop();status.text="后台暂停；返回同步";super.onStop()}
 private fun buildInterface(){
  danmakuSize=getPreferences(0).getFloat("danmakuSize",24f).coerceIn(14f,44f)
  val root=LinearLayout(this).apply {orientation=LinearLayout.VERTICAL;setPadding(dp(8),dp(4),dp(8),dp(6));setBackgroundColor(0xff090e10.toInt())};screenRoot=root
  val watch=LinearLayout(this).apply {orientation=LinearLayout.VERTICAL};val settingsBody=LinearLayout(this).apply {orientation=LinearLayout.VERTICAL;setPadding(dp(12),dp(8),dp(12),dp(8))};val settings=ScrollView(this).apply {addView(settingsBody);visibility=View.GONE}
  val openSettings={watch.visibility=View.GONE;settings.visibility=View.VISIBLE;chat.visible=false}
  val tabs=row(root).apply {gravity=android.view.Gravity.CENTER_VERTICAL;setPadding(0,dp(4),0,dp(8))}
  icon(tabs,R.drawable.ic_arrow_back,"返回房间设置") {openSettings()}
  watchTab=button(tabs,"一起看") {watch.visibility=View.VISIBLE;settings.visibility=View.GONE;chat.visible=true;chat.read();watchTab.text="一起看"}.apply {textSize=16f;setTextColor(-1);setTypeface(typeface,android.graphics.Typeface.BOLD);setPadding(dp(3),0,dp(8),0);background=rounded(0x00000000);layoutParams=LinearLayout.LayoutParams(dp(70),dp(44))}
  presence=label(tabs,"未连接").apply {gravity=android.view.Gravity.CENTER;textSize=11f;maxLines=1;ellipsize=android.text.TextUtils.TruncateAt.END;setTextColor(0xff9cabb5.toInt());background=rounded(0xff1a2126.toInt(),24);setPadding(dp(8),0,dp(8),0);layoutParams=LinearLayout.LayoutParams(0,dp(32),1f);contentDescription="房间成员";setOnClickListener {membersDialog()}}
  icon(tabs,R.drawable.ic_link,"分享房间") {shareRoom()};icon(tabs,R.drawable.ic_settings,"房间 / 设置") {openSettings()}
  icon(tabs,R.drawable.ic_logout,"离开房间",44,0xfff73861.toInt()) {if(connected)send(JSONObject().put("type","ROOM_LEAVE"))else clearRoom()}
  root.addView(watch,LinearLayout.LayoutParams(-1,0,1f));root.addView(settings,LinearLayout.LayoutParams(-1,0,1f))
  watchBody=LinearLayout(this);watch.addView(watchBody,LinearLayout.LayoutParams(-1,0,1f));videoColumn=LinearLayout(this).apply {orientation=LinearLayout.VERTICAL};chatColumn=LinearLayout(this).apply {orientation=LinearLayout.VERTICAL;setBackgroundColor(0xff090e10.toInt())};watchBody.addView(videoColumn);watchBody.addView(chatColumn)
  videoBox=FrameLayout(this).apply {setBackgroundColor(android.graphics.Color.BLACK)};videoColumn.addView(videoBox);videoBox.addView(PlayerView(this).apply {player=this@MainActivity.player;useController=false;isClickable=false},FrameLayout.LayoutParams(-1,-1))
  val titlePanel=LinearLayout(this).apply {orientation=LinearLayout.VERTICAL;setPadding(dp(12),dp(8),dp(8),dp(16));background=android.graphics.drawable.GradientDrawable(android.graphics.drawable.GradientDrawable.Orientation.TOP_BOTTOM,intArrayOf(0xc9000000.toInt(),0x00000000))};watchHeading=titlePanel;videoBox.addView(titlePanel,FrameLayout.LayoutParams(-1,-2,android.view.Gravity.TOP))
  val heading=row(titlePanel).apply {gravity=android.view.Gravity.CENTER_VERTICAL};roomTitle=label(heading,"选择影片，开始一起看").apply {layoutParams=LinearLayout.LayoutParams(0,-2,1f);textSize=15f;setTypeface(typeface,android.graphics.Typeface.BOLD);maxLines=1;ellipsize=android.text.TextUtils.TruncateAt.END}
  icon(heading,R.drawable.ic_audiotrack,"音轨",36) {selectTrack(androidx.media3.common.C.TRACK_TYPE_AUDIO)}
  icon(heading,R.drawable.ic_subtitles,"字幕",36) {subtitleMenu()}
  icon(heading,R.drawable.ic_more_horiz,"更多",36) {android.app.AlertDialog.Builder(this).setTitle("观影工具").setItems(arrayOf("播放列表","发送表情","房间成员","片源与校准")){_,i->when(i){0->showLibrary();1->emojiPicker();2->membersDialog();3->openSettings()}}.show()}
  mediaBadge=label(titlePanel).apply {textSize=10f;setTextColor(0xffc8d1da.toInt());setPadding(dp(8),dp(4),dp(8),dp(4));background=rounded(0x90313842.toInt(),6);visibility=View.GONE;layoutParams=LinearLayout.LayoutParams(-2,-2)}
  captions=TextView(this).apply {textSize=20f;gravity=android.view.Gravity.CENTER;setTextColor(android.graphics.Color.WHITE);setShadowLayer(3f,1f,1f,android.graphics.Color.BLACK);setBackgroundColor(0x66000000);visibility=View.GONE;setPadding(dp(8),dp(4),dp(8),dp(4))};videoBox.addView(captions,FrameLayout.LayoutParams(-1,-2,android.view.Gravity.BOTTOM).apply {bottomMargin=dp(18)})
  val videoSeekRow=row(videoColumn).apply {gravity=android.view.Gravity.CENTER_VERTICAL;setPadding(dp(8),0,dp(8),0)}
  timeLabel=label(videoSeekRow,"00:00").apply {textSize=11f;layoutParams=LinearLayout.LayoutParams(dp(48),dp(32));gravity=android.view.Gravity.CENTER_VERTICAL}
  progress=SeekBar(this).apply {max=1000;contentDescription="影片进度";progressTintList=android.content.res.ColorStateList.valueOf(0xff188dff.toInt());thumbTintList=android.content.res.ColorStateList.valueOf(0xff188dff.toInt());progressBackgroundTintList=android.content.res.ColorStateList.valueOf(0xff58616b.toInt())};videoSeekRow.addView(progress,LinearLayout.LayoutParams(0,dp(32),1f));progress.setOnSeekBarChangeListener(object: SeekBar.OnSeekBarChangeListener {override fun onProgressChanged(s: SeekBar?,p: Int,user: Boolean){};override fun onStartTrackingTouch(s: SeekBar?){draggingProgress=true};override fun onStopTrackingTouch(s: SeekBar?){draggingProgress=false;if(player.duration>0)control("SEEK",player.duration*(progress.progress/1000.0)-engine.timelineOffset)}})
  durationLabel=label(videoSeekRow,"--:--").apply {textSize=11f;gravity=android.view.Gravity.END or android.view.Gravity.CENTER_VERTICAL;layoutParams=LinearLayout.LayoutParams(dp(48),dp(32))}
  val controls=row(videoColumn).apply {gravity=android.view.Gravity.CENTER_VERTICAL;setPadding(0,dp(4),0,dp(8))}
  icon(controls,R.drawable.ic_volume_up,"静音 / 恢复音量") {if(voice.userVolume>0f){lastAudibleVolume=voice.userVolume;voice.setUserVolume(0f)}else voice.setUserVolume(lastAudibleVolume)}
  val volume=SeekBar(this).apply {max=100;progress=100;contentDescription="播放器音量";progressTintList=android.content.res.ColorStateList.valueOf(0xff188dff.toInt());thumbTintList=android.content.res.ColorStateList.valueOf(0xff188dff.toInt());setPadding(dp(4),0,dp(4),0);setOnSeekBarChangeListener(object: SeekBar.OnSeekBarChangeListener {override fun onProgressChanged(s: SeekBar?,p: Int,user: Boolean){if(user)voice.setUserVolume(p/100f)};override fun onStartTrackingTouch(s: SeekBar?){};override fun onStopTrackingTouch(s: SeekBar?){}})};volumeSlider=volume;controls.addView(volume,LinearLayout.LayoutParams(0,dp(32),1f))
  icon(controls,R.drawable.ic_replay_10,"后退10秒") {control("SEEK",player.currentPosition-engine.timelineOffset-10000)}
  pauseButton=icon(controls,R.drawable.ic_play_arrow,"播放",60,-1,0xff0a1016.toInt()) {togglePlayback()}
  icon(controls,R.drawable.ic_forward_10,"前进10秒") {control("SEEK",player.currentPosition-engine.timelineOffset+10000)}
  icon(controls,R.drawable.ic_chat_bubble_outline,"选择字幕") {subtitleMenu()};icon(controls,R.drawable.ic_fullscreen,"全屏") {showFullscreen()}
  optionsRow=LinearLayout(this).apply {orientation=LinearLayout.HORIZONTAL;visibility=View.GONE};optionsToggle=Button(this).apply {visibility=View.GONE}
  addVoicePanel(videoColumn)
  notice=label(videoColumn);notice.textSize=12f;notice.setTextColor(0xff95b7d3.toInt());requestStatus=label(videoColumn);requestStatus.textSize=12f;requestStatus.setTextColor(0xffffba67.toInt());approveButton=button(videoColumn,"批准对方请求") {pending?.let {control(it.optString("type"),it.optDouble("position",0.0));pending=null;approveButton.visibility=View.GONE;requestStatus.text=""}};approveButton.visibility=View.GONE
  chatScroll=ScrollView(this).apply {isFillViewport=true;isVerticalScrollBarEnabled=false};chatText=TextView(this);chatBubbles=LinearLayout(this).apply {orientation=LinearLayout.VERTICAL;setPadding(dp(6),dp(8),dp(6),dp(8))};chatScroll.addView(chatBubbles);chatColumn.addView(chatScroll,LinearLayout.LayoutParams(-1,0,1f));typing=label(chatColumn);typing.textSize=11f
  val chatRow=row(chatColumn).apply {gravity=android.view.Gravity.CENTER_VERTICAL;setPadding(0,dp(8),0,dp(6))}
  icon(chatRow,R.drawable.ic_add,"聊天工具",44,0xff1c242b.toInt()) {android.app.AlertDialog.Builder(this).setTitle("聊天工具").setItems(arrayOf("播放列表","导入外挂字幕","房间与片源")){_,i->when(i){0->showLibrary();1->importSubtitle();2->openSettings()}}.show()}
  val inputWrap=LinearLayout(this).apply {gravity=android.view.Gravity.CENTER_VERTICAL;background=rounded(0xff191f24.toInt(),28)};chatRow.addView(inputWrap,LinearLayout.LayoutParams(0,-2,1f).apply {setMargins(dp(8),0,dp(8),0)})
  draft=field(inputWrap,"发消息…").apply {textSize=14f;maxLines=3;minHeight=dp(48);setTextColor(-1);setHintTextColor(0xff8f99a4.toInt());background=null;setPadding(dp(14),dp(10),0,dp(10));layoutParams=LinearLayout.LayoutParams(0,-2,1f);imeOptions=android.view.inputmethod.EditorInfo.IME_ACTION_SEND;setOnEditorActionListener {_,action,_->if(action==android.view.inputmethod.EditorInfo.IME_ACTION_SEND){sendChat();true}else false}}
  icon(inputWrap,R.drawable.ic_sentiment_satisfied_alt,"发送表情") {emojiPicker()};icon(chatRow,R.drawable.ic_send,"发送",48,0xff1688ff.toInt()) {sendChat()};draft.addTextChangedListener(object: TextWatcher {override fun beforeTextChanged(s: CharSequence?,start: Int,count: Int,after: Int){};override fun onTextChanged(s: CharSequence?,start: Int,before: Int,count: Int){if(connected && clock.localNow()-lastTyping>1000){lastTyping=clock.localNow();send(JSONObject().put("type","CHAT_TYPING"))}};override fun afterTextChanged(s: Editable?) {}})
  renderChat()
  label(settingsBody,"TogetherPlayer $clientVersion · 房间与片源");server=field(settingsBody,"服务端 HTTPS 地址",getPreferences(0).getString("server","https://together.xiaokai123.de5.net")!!);roomInput=field(settingsBody,"房间编号")
  val rooms=row(settingsBody);button(rooms,"创建") {register(false)};button(rooms,"加入 / 重连") {register(true)};button(rooms,"离开") {if(connected)send(JSONObject().put("type","ROOM_LEAVE"))else clearRoom()}
  // Keep REST feedback visible next to the buttons as well as on the watch page.
  val feedback=label(settingsBody);requestStatus.addTextChangedListener(object: TextWatcher {override fun beforeTextChanged(s: CharSequence?,start: Int,count: Int,after: Int){};override fun onTextChanged(s: CharSequence?,start: Int,before: Int,count: Int){feedback.text=s};override fun afterTextChanged(s: Editable?) {}})
  waitToggle=Switch(this).apply {text="等待对方缓冲或重连";settingsBody.addView(this);setOnCheckedChangeListener {_,enabled->if(!settingWait && connected && isHost)enqueue(JSONObject().put("type","ROOM_SETTINGS").put("data",JSONObject().put("waitForPeer",enabled)))}}
  titleField=field(settingsBody,"影片名称","一起看电影");media=field(settingsBody,"HTTP / HLS / WebDAV 文件链接","https://media.w3.org/2010/05/bunny/movie.mp4");button(settingsBody,"设置房间影片") {setRoomMedia()};button(settingsBody,"添加到本机播放列表") {saveLibrary()}
  button(settingsBody,"苹果 HDR / Atmos 测试片") {media.setText("https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/main.m3u8");titleField.setText("苹果 HDR / Atmos 测试片");if(connected && isHost)setRoomMedia()};label(settingsBody,"视频由设备直接读取。实际 HDR / Atmos 输出取决于设备与片源。")
  button(settingsBody,"百度网盘 · 授权并选择房间影片") {openBaidu()}
  button(settingsBody,"重试播放") {retryPlayback()}
  button(settingsBody,"清除本机百度授权和片源") {baidu.clear();clearBaiduSource()}
  localFileLabel=label(settingsBody,"未选择本地影片").apply {textSize=12f;setTextColor(0xff95b7d3.toInt())}
  val localRow=row(settingsBody);button(localRow,"选择本地影片") {importLocalMovie()};button(localRow,"清除本地影片") {clearLocalMovie()}
  button(settingsBody,"仅替换本机为本地影片（好友继续在线）") {importLocalMovie(false)}
  localSource=field(settingsBody,"仅本机片源（留空恢复）");button(settingsBody,"应用本机片源") {applyLocalSource()};nickname=field(settingsBody,"昵称",getPreferences(0).getString("nickname","我")!!);offset=field(settingsBody,"时间偏移（秒，可负数）",getPreferences(0).getString("offset","0")!!);label(settingsBody,"本地文件直接从本机读取，不会上传；百度房间会核对同一文件。片头差异可用时间偏移校准，不同剪辑无法靠偏移同步。");button(settingsBody,"保存昵称与校准") {saveProfile()}
  val seekRow=row(settingsBody);seek=field(seekRow,"跳转秒数","20");seek.layoutParams=LinearLayout.LayoutParams(0,-2,1f);button(seekRow,"跳转") {seek.text.toString().toDoubleOrNull()?.takeIf {it.isFinite()}?.let {control("SEEK",it*1000)}}
  status=label(settingsBody,"未连接");button(settingsBody,"模拟断线3秒") {disconnectForTest()};label(settingsBody,"前台观影；后台暂停，返回恢复同步。外挂字幕只在本机读取。")
  root.setOnApplyWindowInsetsListener {view,insets->
   val edges=if(android.os.Build.VERSION.SDK_INT>=30){val safe=insets.getInsets(android.view.WindowInsets.Type.systemBars() or android.view.WindowInsets.Type.displayCutout());intArrayOf(safe.left,safe.top,safe.right,safe.bottom)}else intArrayOf(insets.systemWindowInsetLeft,insets.systemWindowInsetTop,insets.systemWindowInsetRight,insets.systemWindowInsetBottom)
   view.setPadding(dp(8)+edges[0],dp(4)+edges[1],dp(8)+edges[2],dp(6)+edges[3])
   view.post {adaptOrientation()};insets
  }
  setContentView(root);root.requestApplyInsets();root.post {adaptOrientation()}
 }
 override fun onConfigurationChanged(config: android.content.res.Configuration){super.onConfigurationChanged(config);screenRoot?.post {adaptOrientation()}}
 private fun adaptOrientation(){
  if(fullscreenDialog!=null)return
  val landscape=resources.configuration.orientation==android.content.res.Configuration.ORIENTATION_LANDSCAPE
  watchHeading.visibility=View.VISIBLE
  optionsRow.visibility=View.GONE;optionsToggle.visibility=View.GONE
  progress.layoutParams=LinearLayout.LayoutParams(0,dp(32),1f)
  val width=screenRoot?.width ?: resources.displayMetrics.widthPixels;val height=screenRoot?.height ?: resources.displayMetrics.heightPixels
  watchBody.orientation=if(landscape)LinearLayout.HORIZONTAL else LinearLayout.VERTICAL
  if(landscape){videoColumn.layoutParams=LinearLayout.LayoutParams(0,-1,2.2f);chatColumn.layoutParams=LinearLayout.LayoutParams(0,-1,1f);videoBox.layoutParams=LinearLayout.LayoutParams(-1,0,1f)}
  else {videoColumn.layoutParams=LinearLayout.LayoutParams(-1,-2);chatColumn.layoutParams=LinearLayout.LayoutParams(-1,0,1f);videoBox.layoutParams=LinearLayout.LayoutParams(-1,((width-screenRoot!!.paddingLeft-screenRoot!!.paddingRight)*9/16).coerceAtMost((height*0.40).toInt()))}
 }
 private fun updatePlaybackUI(){if(!::timeLabel.isInitialized)return;if(voiceConnected!=connected){voiceConnected=connected;voiceViews.forEach {it.render()}};val duration=player.duration.coerceAtLeast(0);val position=player.currentPosition.coerceAtLeast(0);val line="${formatTime(position)}  /  ${if(duration>0)formatTime(duration) else "时长待加载"}${if(player.playbackState==Player.STATE_BUFFERING)" · 缓冲中" else ""}";timeLabel.text=formatTime(position);durationLabel.text=if(duration>0)formatTime(duration) else "--:--";fullscreenTime?.text=line;val playing=engine.room?.optString("state")=="playing";val playLabel=if(playing)"暂停" else "播放";if(pauseButton.contentDescription!=playLabel){pauseButton.setImageResource(if(playing)R.drawable.ic_pause else R.drawable.ic_play_arrow);pauseButton.contentDescription=playLabel};volumeSlider.progress=(voice.userVolume*100).toInt();val memberLabel=if(connected)"${onlineMembers}人一起看" else if(credentials!=null)"连接中" else "未连接";if(presence.text.toString()!=memberLabel)presence.text=memberLabel;presence.setTextColor(if(connected)0xff44d68b.toInt()else 0xff9cabb5.toInt());val format=player.videoFormat;val badges=mutableListOf<String>();if(format!=null){if(format.height>=2160)badges.add("4K")else if(format.height>=1080)badges.add("1080p");if(format.colorInfo?.colorTransfer==androidx.media3.common.C.COLOR_TRANSFER_ST2084 || format.colorInfo?.colorTransfer==androidx.media3.common.C.COLOR_TRANSFER_HLG)badges.add("HDR");if(format.sampleMimeType=="video/dolby-vision")badges.add("杜比视界轨道");if(format.frameRate>0)badges.add("%.2f FPS".format(format.frameRate))};val info=badges.joinToString("   ·   ");if(mediaBadge.text.toString()!=info)mediaBadge.text=info;mediaBadge.visibility=if(info.isBlank())View.GONE else View.VISIBLE;if(!draggingProgress){progress.progress=if(duration>0)(position*1000/duration).toInt().coerceIn(0,1000)else 0};progress.isEnabled=connected && duration>0
  val text=if(subtitleEnabled)external?.textAt(position,subtitleDelay) ?: "" else "";if(captions.text.toString()!=text)captions.text=text;captions.visibility=if(text.isBlank())View.GONE else View.VISIBLE;(captions.layoutParams as FrameLayout.LayoutParams).bottomMargin=if(fullscreenControls?.visibility==View.VISIBLE)dp(170) else dp(18)
 }
 private fun formatTime(ms: Long): String {val s=ms/1000;return if(s>=3600)"%d:%02d:%02d".format(s/3600,s/60%60,s%60) else "%02d:%02d".format(s/60,s%60)}
 private fun shareRoom(){val id=credentials?.optString("roomId");if(id.isNullOrBlank()){requestStatus.text="请先加入房间";return};startActivity(android.content.Intent.createChooser(android.content.Intent(android.content.Intent.ACTION_SEND).setType("text/plain").putExtra(android.content.Intent.EXTRA_TEXT,"TogetherPlayer 房间：$id\n服务器：${server.text}"),"分享房间"))}
 private fun readSubtitleBytes(input: java.io.InputStream): ByteArray {val out=java.io.ByteArrayOutputStream();val buffer=ByteArray(8192);while(out.size()<=ExternalSubtitle.MAX_BYTES){val count=input.read(buffer,0,minOf(buffer.size,ExternalSubtitle.MAX_BYTES+1-out.size()));if(count<0)break;out.write(buffer,0,count)};return out.toByteArray()}
 private fun clearSubtitle(){subtitleGeneration++;external=null;subtitleName="";subtitleDelay=0;subtitleEnabled=false;if(::captions.isInitialized)captions.visibility=View.GONE}
 private fun subtitleMenu(){main.removeCallbacks(hideControls);val items=mutableListOf("内置字幕 / 关闭","导入外挂字幕（SRT / VTT / ASS）");if(external!=null){items.add("使用外挂：$subtitleName");items.add("调整外挂字幕延迟");items.add("移除外挂字幕")};android.app.AlertDialog.Builder(this).setTitle("字幕").setItems(items.toTypedArray()){_,i->when(i){0->selectTrack(androidx.media3.common.C.TRACK_TYPE_TEXT);1->importSubtitle();2->{subtitleEnabled=true;player.trackSelectionParameters=player.trackSelectionParameters.buildUpon().setTrackTypeDisabled(androidx.media3.common.C.TRACK_TYPE_TEXT,true).build()};3->subtitleTiming();4->clearSubtitle()}}.create().apply {setOnDismissListener {revealControls()};show()}}
 private fun importSubtitle(){main.removeCallbacks(hideControls);startActivityForResult(android.content.Intent(android.content.Intent.ACTION_OPEN_DOCUMENT).setType("*/*").addCategory(android.content.Intent.CATEGORY_OPENABLE),701)}
 private fun importLocalMovie(publishRoom:Boolean=true){
  if(!connected || engine.room==null){requestStatus.text="请先创建或加入房间，再选择本地影片";return}
  pendingLocalRoom=engine.room!!.optString("roomId");pendingLocalMedia=engine.room!!.optString("mediaUrl")
  localSelectionGeneration++;localSelectionPublishes=publishRoom;pendingLocalMovie=null
  val intent=android.content.Intent(android.content.Intent.ACTION_OPEN_DOCUMENT).setType("*/*").addCategory(android.content.Intent.CATEGORY_OPENABLE).addFlags(android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION or android.content.Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
  intent.putExtra(android.content.Intent.EXTRA_MIME_TYPES,arrayOf("video/*","video/x-matroska","application/octet-stream"))
  startActivityForResult(intent,702)
 }
 override fun onActivityResult(requestCode: Int,resultCode: Int,data: android.content.Intent?){
  super.onActivityResult(requestCode,resultCode,data);if(requestCode !in listOf(701,702))return;revealControls();if(resultCode!=RESULT_OK)return;val uri=data?.data ?: return
  if(requestCode==702){pendingLocalMovie=uri to data.flags;localFileLabel.text="本地影片已选择，等待房间连接…";applyPendingLocalMovie();return}
  val g=++subtitleGeneration
  Thread {val result=runCatching {val name=contentResolver.query(uri,arrayOf(android.provider.OpenableColumns.DISPLAY_NAME),null,null,null)?.use {if(it.moveToFirst())it.getString(0) else "外挂字幕"} ?: "外挂字幕";val bytes=contentResolver.openInputStream(uri)?.use {readSubtitleBytes(it)} ?: throw IOException("文件无法读取");Pair(name,ExternalSubtitle.parse(bytes))};main.post {if(g!=subtitleGeneration || stopped)return@post;result.onSuccess {(name,parsed)->external=parsed;subtitleName=name;subtitleDelay=0;subtitleEnabled=true;player.trackSelectionParameters=player.trackSelectionParameters.buildUpon().setTrackTypeDisabled(androidx.media3.common.C.TRACK_TYPE_TEXT,true).build();requestStatus.text="已加载外挂字幕：$name"}.onFailure {requestStatus.text=it.message ?: "字幕读取失败"}}}.start()
 }
 private fun subtitleTiming(){val input=EditText(this).apply {setText((subtitleDelay/1000.0).toString());inputType=android.text.InputType.TYPE_CLASS_NUMBER or android.text.InputType.TYPE_NUMBER_FLAG_DECIMAL or android.text.InputType.TYPE_NUMBER_FLAG_SIGNED};android.app.AlertDialog.Builder(this).setTitle("字幕延迟（秒，正值更晚，±120秒）").setView(input).setNegativeButton("取消",null).setPositiveButton("保存"){_,_->val value=input.text.toString().toDoubleOrNull();if(value!=null && value.isFinite() && kotlin.math.abs(value)<=120)subtitleDelay=(value*1000).toLong() else requestStatus.text="字幕延迟必须在正负120秒内"}.show()}
 private fun library()=runCatching {org.json.JSONArray(getPreferences(0).getString("mediaLibrary","[]"))}.getOrElse {org.json.JSONArray()}
 private fun saveLibrary(){val url=media.text.toString().trim();if(!MediaSources.canShare(url)){requestStatus.text="不能保存带账户凭据的链接";return};val list=library();if((0 until list.length()).none {list.getJSONObject(it).optString("url")==url})list.put(JSONObject().put("title",titleField.text.toString()).put("url",url));getPreferences(0).edit().putString("mediaLibrary",list.toString()).apply();requestStatus.text="已保存到本机播放列表"}
 private fun showLibrary(){val list=library();val titles=(0 until list.length()).map {list.getJSONObject(it).optString("title")}.toTypedArray();if(titles.isEmpty()){android.app.AlertDialog.Builder(this).setTitle("播放列表").setMessage("在房间 / 设置中填入授权影片链接后，点击添加到本机播放列表。").setPositiveButton("知道了",null).show();return};android.app.AlertDialog.Builder(this).setTitle("本机播放列表").setItems(titles){_,i->if(!isHost || !connected){requestStatus.text="房主连接后可以切换影片"}else {media.setText(list.getJSONObject(i).getString("url"));titleField.setText(titles[i]);setRoomMedia()}}.setNeutralButton("删除影片"){_,_->android.app.AlertDialog.Builder(this).setTitle("删除本机记录").setItems(titles){_,i->list.remove(i);getPreferences(0).edit().putString("mediaLibrary",list.toString()).apply()}.show()}.setNegativeButton("关闭",null).show()}

 private fun register(join: Boolean) {
  val base=server.text.toString().trim().trimEnd('/');val requested=roomInput.text.toString().trim().lowercase()
  if(registering){requestStatus.text="房间请求处理中";return}
  if(join && credentials?.optString("roomId")==requested && getPreferences(0).getString("server",null)==base){connect();return}
  if(!join && !MediaSources.canShare(media.text.toString())){requestStatus.text="公用片源不能含账户凭据";return};registering=true;requestStatus.text="正在处理房间请求…"
  val url=if(join)"$base/rooms/$requested/join" else "$base/rooms";val body=if(join)"{}" else JSONObject().put("mediaUrl",MediaSources.resolve(media.text.toString())).put("title",titleField.text.toString()).toString()
  try {http.newCall(Request.Builder().url(url).post(body.toRequestBody("application/json".toMediaType())).build()).enqueue(object: Callback {
   override fun onFailure(call: Call,e: IOException){main.post {registering=false;requestStatus.text="房间请求失败，请检查网络"}}
   override fun onResponse(call: Call,response: Response){response.use {val code=it.code;val text=it.body?.string() ?: "";main.post {
    registering=false;if(stopped)return@post
    if(code!=201){requestStatus.text=when(code){409->"房间已满，请创建新房间";404->"房间不存在或已过期";else->"房间请求失败（$code）"};return@post}
    val next=try {RoomCredentials.parse(text)}catch(e: Exception){requestStatus.text="房间凭证无效";return@post}
    credentials=next;roomInput.setText(next.getString("roomId"));getPreferences(0).edit().putString("credentials",text).putString("server",base).apply();connect()
   }}}
  })}catch(e: Exception){registering=false;requestStatus.text="服务地址无效"}
 }
 private fun connect() {
  if(!foreground || stopped)return;val auth=credentials ?: return
  generation++;val g=generation;ws?.cancel();connected=false;engine.resetSession();pending=null;approveButton.visibility=View.GONE;queued.clear();inFlight=null;requestStatus.text=""
  val base=(getPreferences(0).getString("server",null) ?: return).trim().trimEnd('/').replaceFirst("http","ws");status.text="重新同步中…"
  try {ws=http.newWebSocket(Request.Builder().url("$base/ws").header("Authorization","Bearer ${auth.getString("token")}").build(),object: WebSocketListener() {
   override fun onMessage(webSocket: WebSocket,text: String){val t4=clock.localNow();main.post {if(g==generation)runCatching {receive(JSONObject(text),t4)}.onFailure {requestStatus.text="服务器消息无法解析"}}}
   override fun onFailure(webSocket: WebSocket,t: Throwable,response: Response?){main.post {if(g==generation){if(response?.code==401)clearRoom() else reconnect(g)}}}
   override fun onClosing(webSocket: WebSocket,code: Int,reason: String){webSocket.close(code,reason)}
   override fun onClosed(webSocket: WebSocket,code: Int,reason: String){main.post {if(g==generation)reconnect(g)}}
  })}catch(e: Exception){requestStatus.text="连接地址无效"}
 }
 private fun reconnect(g: Int){if(g!=generation)return;voice.cancel("连接中断，录音已取消，未发送");connected=false;engine.resetSession();attempt++;status.text="自动重连中…";main.postDelayed({if(!stopped && foreground && generation==g)connect()},(500L shl attempt.coerceAtMost(5)).coerceAtMost(15000))}
 private fun send(obj: JSONObject){if(connected)ws?.send(obj.toString())}
 private fun pingBurst(){repeat(5){i->val g=generation;main.postDelayed({if(g==generation)send(JSONObject().put("type","PING").put("t1",clock.localNow()))},i*200L)}}
 private fun receive(obj: JSONObject,t4: Double) {
  val type=obj.optString("type");if(type=="PONG"){clock.add(obj.getDouble("t1"),obj.getDouble("t2"),obj.getDouble("t3"),t4);return}
  if(type=="WELCOME"){sequence=obj.optLong("lastSequence");connected=true;attempt=0;pingBurst()}
  obj.optJSONObject("room")?.let {r->
   engine.receive(r);isHost=r.getString("hostId")==credentials?.optString("userId");val id=r.getString("roomId");if(chatRoom!=id){chatRoom=id;outbox.clear();chat.reset(id);renderChat()}
   roomTitle.text=r.optString("title").ifBlank {"一起看电影"};settingWait=true;waitToggle.isChecked=r.optBoolean("waitForPeer");waitToggle.isEnabled=isHost;settingWait=false
   notice.text=when(r.optString("pauseReason")){"buffering"->"等待对方缓冲";"disconnected"->"等待对方重连";"ended"->"播放完毕，点播放重播";else->""}
   val url=r.getString("mediaUrl");obj.optJSONArray("members")?.let {applyMembers(it)}
   if(BaiduMediaReference.parse(url)!=null) {
    if(url!=loadedURL || (type=="WELCOME" && hasBaiduMatch() && player.playerError==null && player.playbackState==Player.STATE_IDLE)) {
     loadedURL=url;titleField.setText(r.optString("title"))
     if(hasBaiduMatch())loadMedia(if(localFileUri.isNotBlank())localFileUri else baiduURL,r.getDouble("position")+engine.timelineOffset)
     else {player.pause();player.clearMediaItems();clearSubtitle();requestStatus.text="房间已切换到文件匹配模式，请选择本地同一文件，或授权百度网盘并选择转存的同一文件。"}
    }
    notice.text=if(hasBaiduMatch())if(localFileUri.isNotBlank())"本地同一文件已匹配；等待双方准备好后由房主播放。" else "百度同一文件已匹配；等待双方准备好后由房主播放。" else "等待百度选片：${r.optString("title")}；也可选择本地同一文件"
   }else if(url!=loadedURL || (type=="WELCOME" && player.playerError==null && player.playbackState==Player.STATE_IDLE)) {
    if(baiduSourceID.isNotBlank()){baiduSourceID="";baiduSourceRoom="";baiduURL="";activeLocalSource="";localSource.text.clear()}
    if(localFileUri.isNotBlank() && (localSourceRoomID!=r.optString("roomId") || localSourceRoom!=url)){localFileUri="";localFileName="";if(::localFileLabel.isInitialized)localFileLabel.text="未选择本地影片"}
    loadedURL=url;media.setText(url);titleField.setText(r.optString("title"));loadMedia(playbackSource(url),r.getDouble("position")+engine.timelineOffset)
   }
  }
  if(type=="PRESENCE")obj.optJSONArray("members")?.let {applyMembers(it)}
  when(type){
   "WELCOME"->{obj.optJSONArray("messages")?.let {list->repeat(list.length()){acceptChat(list.getJSONObject(it))}};sendProfile();outbox.values.forEach {send(it)};applyPendingLocalMovie()}
   "CHAT_MESSAGE"->obj.optJSONObject("message")?.let {acceptChat(it,true)}
   "CHAT_TYPING"->if(obj.optString("userId")!=credentials?.optString("userId"))chat.typing(obj.optString("name"),clock.localNow())
   "REACTION"->showReaction(obj.optString("emoji"))
   "CONTROL_REQUEST"->{pending=obj.optJSONObject("data");approveButton.visibility=View.VISIBLE;requestStatus.text="对方请求：${pending?.optString("type")}"}
   "ROOM_CLOSE","ROOM_LEAVE"->{clearRoom();return}
  }
  if(obj.optString("ackUserId")==credentials?.optString("userId") && obj.optLong("ackSequence",-1)==flightSequence){inFlight=null;retry=0;flush()}
  if(type=="ERROR"){if(obj.optString("error")=="STALE_VERSION" && inFlight!=null && retry<1){retry++;queued.addFirst(inFlight!!);inFlight=null;flush()}else {inFlight=null;queued.clear();requestStatus.text=errorText(obj.optString("error"))}}
 }
 private fun selectTrack(type: Int){
  val options=ArrayList<String>();val overrides=ArrayList<androidx.media3.common.TrackSelectionOverride?>()
  options.add("自动选择");overrides.add(null)
  if(type==androidx.media3.common.C.TRACK_TYPE_TEXT){options.add("关闭字幕");overrides.add(null)}
  for(g in player.currentTracks.groups)if(g.type==type)for(i in 0 until g.length){if(g.isTrackSupported(i)){val f=g.getTrackFormat(i);options.add("${f.label ?: f.language ?: "轨道 ${i+1}"} ${f.sampleMimeType ?: ""}");overrides.add(androidx.media3.common.TrackSelectionOverride(g.mediaTrackGroup,listOf(i)))}}
  main.removeCallbacks(hideControls)
  android.app.AlertDialog.Builder(this).setTitle(if(type==androidx.media3.common.C.TRACK_TYPE_AUDIO)"音轨" else "字幕").setItems(options.toTypedArray()){_,i->
   if(type==androidx.media3.common.C.TRACK_TYPE_TEXT)subtitleEnabled=false
   val b=player.trackSelectionParameters.buildUpon().clearOverridesOfType(type).setTrackTypeDisabled(type,type==androidx.media3.common.C.TRACK_TYPE_TEXT && i==1)
   overrides[i]?.let {b.addOverride(it)};player.trackSelectionParameters=b.build()
  }.create().apply {setOnDismissListener {revealControls()};show()}
 }
 private fun showFullscreen(){
  if(fullscreenDialog!=null)return
  watchHeading.visibility=View.GONE
  val parent=videoBox.parent as LinearLayout;val index=parent.indexOfChild(videoBox);val layout=videoBox.layoutParams;parent.removeView(videoBox)
  val content=FrameLayout(this).apply {setBackgroundColor(android.graphics.Color.BLACK);addView(videoBox,FrameLayout.LayoutParams(-1,-1))}
  val dialog=android.app.Dialog(this,android.R.style.Theme_Black_NoTitleBar_Fullscreen);fullscreenDialog=dialog
  val overlay=LinearLayout(this).apply {orientation=LinearLayout.VERTICAL;setPadding(dp(12),dp(6),dp(12),dp(8));setBackgroundColor(0xbb101216.toInt())};fullscreenControls=overlay
  val top=row(overlay);button(top,"退出全屏") {dialog.dismiss()};button(top,"发弹幕") {composeDanmaku()};button(top,"字号") {danmakuSettings()}
  fullscreenTime=label(overlay);val transport=row(overlay);button(transport,"↩10") {control("SEEK",player.currentPosition-engine.timelineOffset-10000);revealControls()};button(transport,"播放 / 暂停") {togglePlayback();revealControls()};button(transport,"10↪") {control("SEEK",player.currentPosition-engine.timelineOffset+10000);revealControls()}
  val tracks=row(overlay);button(tracks,"音轨") {selectTrack(androidx.media3.common.C.TRACK_TYPE_AUDIO)};button(tracks,"字幕") {subtitleMenu()}
  val fullVoice=addVoicePanel(overlay)
  content.addView(overlay,FrameLayout.LayoutParams(-1,-2,android.view.Gravity.BOTTOM));videoBox.setOnClickListener {if(overlay.visibility==View.VISIBLE && !voice.busy){overlay.visibility=View.GONE;main.removeCallbacks(hideControls)}else revealControls()}
  dialog.setContentView(content);dialog.setOnDismissListener {if(voice.busy)voice.cancel();voiceViews.remove(fullVoice);main.removeCallbacks(hideControls);fullscreenDialog=null;fullscreenControls=null;fullscreenTime=null;danmakuPending.clear();removeDanmaku();videoBox.setOnClickListener(null);content.removeView(videoBox);parent.addView(videoBox,index,layout);adaptOrientation()};dialog.show();dialog.window?.setLayout(-1,-1);dialog.window?.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);revealControls()
 }
 private fun revealControls(){fullscreenControls?.visibility=View.VISIBLE;main.removeCallbacks(hideControls);main.postDelayed(hideControls,if(applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE!=0 && intent.getBooleanExtra("uiTestSlow",false))12000 else 3000)}
 private fun togglePlayback(){control(if(engine.room?.optString("state")=="playing")"PAUSE" else "PLAY")}
 private fun composeDanmaku(){main.removeCallbacks(hideControls);val input=EditText(this).apply {hint="发弹幕（同时发送到聊天）";maxLines=3}
  val d=android.app.AlertDialog.Builder(this).setTitle("发弹幕").setView(input).setNegativeButton("取消",null).setPositiveButton("发送",null).create()
  d.setOnShowListener {d.getButton(android.app.AlertDialog.BUTTON_POSITIVE).setOnClickListener {draft.setText(input.text);sendChat();if(draft.text.isEmpty())d.dismiss() else android.widget.Toast.makeText(this,requestStatus.text,android.widget.Toast.LENGTH_SHORT).show()};input.requestFocus();d.window?.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_VISIBLE)};d.setOnDismissListener {revealControls()};d.show()
 }
 private fun danmakuSettings(){main.removeCallbacks(hideControls);val body=LinearLayout(this).apply {orientation=LinearLayout.VERTICAL;setPadding(dp(20),dp(10),dp(20),dp(10))};val preview=label(body,"弹幕文字大小：${danmakuSize.toInt()}");val size=SeekBar(this).apply {max=30;progress=danmakuSize.toInt()-14;contentDescription="弹幕文字大小"};body.addView(size);size.setOnSeekBarChangeListener(object: SeekBar.OnSeekBarChangeListener {override fun onProgressChanged(s: SeekBar?,p: Int,user: Boolean){if(user){danmakuSize=(14+p).toFloat();preview.text="弹幕文字大小：${danmakuSize.toInt()}";getPreferences(0).edit().putFloat("danmakuSize",danmakuSize).apply()}};override fun onStartTrackingTouch(s: SeekBar?){};override fun onStopTrackingTouch(s: SeekBar?) {}});android.app.AlertDialog.Builder(this).setTitle("弹幕字号").setView(body).setPositiveButton("完成",null).create().apply {setOnDismissListener {revealControls()};show()}}
 private fun drainDanmaku(){while(danmakuPending.isNotEmpty() && clock.localNow()-danmakuPending.first().second>30000)danmakuPending.removeFirst();val lane=danmakuLanes.indexOfFirst {!it};if(lane<0 || danmakuPending.isEmpty())return;val entry=danmakuPending.removeFirst();val text=entry.first;danmakuLanes[lane]=true
  val v=TextView(this).apply {this.text=text;textSize=danmakuSize;setTextColor(android.graphics.Color.WHITE);setShadowLayer(3f,1f,1f,android.graphics.Color.BLACK);tag="danmaku";isClickable=false};v.measure(View.MeasureSpec.UNSPECIFIED,View.MeasureSpec.UNSPECIFIED);val h=dp((danmakuSize*1.6).toInt());videoBox.addView(v,FrameLayout.LayoutParams(-2,h).apply {topMargin=dp(if(fullscreenDialog!=null)16 else 72)+lane*h});v.translationX=videoBox.width.toFloat();v.animate().translationX(-v.measuredWidth.toFloat()).setDuration(entry.third).setInterpolator(android.view.animation.LinearInterpolator()).withEndAction {videoBox.removeView(v);danmakuLanes[lane]=false;drainDanmaku()}.start();drainDanmaku()
 }
 private fun removeDanmaku(){for(i in videoBox.childCount-1 downTo 0){val v=videoBox.getChildAt(i);if(v.tag=="danmaku"){v.animate().cancel();videoBox.removeView(v)}};danmakuLanes.fill(false)}
 private fun errorText(code: String)=when(code){"STALE_VERSION"->"房间状态变化，请重试";"HOST_REQUIRED"->"只有房主可以操作";"HOST_OFFLINE"->"房主离线";"SEEK_AFTER_END"->"超出影片时长";"SOURCE_NOT_READY"->"等待两端匹配同一百度影片并准备好";"INVALID_SOURCE"->"片源无效或含凭据";"RATE_LIMIT"->"操作过于频繁";else->code}
 private fun applyMembers(list: org.json.JSONArray){val labels=ArrayList<String>();val durations=ArrayList<Double>();repeat(list.length()){val p=list.getJSONObject(it);labels.add("${if(p.optBoolean("online"))"🟢" else "⚪"} ${p.optString("name")} ${if(p.optBoolean("buffering"))"缓冲中" else ""}");if(p.optString("userId")==credentials?.optString("userId"))engine.timelineOffset=p.optDouble("timelineOffset",0.0);if(p.optDouble("duration",0.0)>0)durations.add(p.optDouble("duration")-p.optDouble("timelineOffset",0.0))};memberSummary=labels.joinToString("\n");onlineMembers=(0 until list.length()).count {list.getJSONObject(it).optBoolean("online")};presence.text="${onlineMembers}人一起看";presence.setTextColor(0xff44d68b.toInt());if(durations.size==2 && abs(durations[0]-durations[1])>5000)notice.text="影片时长不同，请确认剪辑一致"}
 private fun hasBaiduMatch()=(baiduURL.isNotBlank() || localFileUri.isNotBlank()) && baiduSourceID==engine.room?.optString("mediaUrl") && baiduSourceRoom==engine.room?.optString("roomId")
 private fun clearBaiduSource(){
  if(baiduURL.isBlank()){requestStatus.text=if(localFileUri.isNotBlank())"百度授权已清除；本地影片保持不变。" else "百度授权已清除。";return}
  baiduURL="";baiduSourceID="";baiduSourceRoom="";player.pause();player.clearMediaItems();clearSubtitle();loadedURL="";requestStatus.text="百度本机片源已清除；请重新授权并选片。"
 }
 private fun openBaidu(){
  // Authorization is local and must remain reachable while disconnected/reconnecting.
  // Capture an existing room to prevent applying a selection after a room/media switch.
  val opening=engine.room;val expectedRoom=opening?.optString("roomId");val original=opening?.optString("mediaUrl")
  BaiduBrowserDialog(this,baidu,if(BaiduMediaReference.parse(original ?: "")!=null)opening?.optString("title") ?: "" else "",{f,u->
   val r=engine.room;val room=r?.optString("roomId") ?: ""
   if(!connected || r==null){requestStatus.text="请先加入房间，连接恢复后再应用影片";android.widget.Toast.makeText(this,requestStatus.text,android.widget.Toast.LENGTH_LONG).show();false}
   else if(expectedRoom!=null && (room!=expectedRoom || r.optString("mediaUrl")!=original)){requestStatus.text="房间或影片已改变，请重新打开百度选片";android.widget.Toast.makeText(this,requestStatus.text,android.widget.Toast.LENGTH_LONG).show();false}
   else if(!BaiduSourceAdapter.allowedURL(u)){requestStatus.text="不允许的百度片源";false}
   else {
    val ref=if(isHost)BaiduMediaReference.create(f.fingerprint,f.size) else BaiduMediaReference.parse(r.optString("mediaUrl"))?.takeIf {it.matches(f.fingerprint,f.size)}
    if(ref==null){requestStatus.text=if(isHost)"百度未提供可核对的文件指纹/大小" else "文件与房间影片不匹配，请转存房主分享的同一文件";android.widget.Toast.makeText(this,requestStatus.text,android.widget.Toast.LENGTH_LONG).show();false}
    else if(isHost && queued.size>=8){requestStatus.text="请等待操作完成";false}
    else {localFileUri="";localFileName="";if(::localFileLabel.isInitialized)localFileLabel.text="未选择本地影片";baiduURL=u;baiduSourceID=ref.value;baiduSourceRoom=room;activeLocalSource="";localSource.text.clear()
     if(isHost)enqueue(JSONObject().put("type","ROOM_MEDIA").put("data",JSONObject().put("mediaUrl",ref.value).put("title",f.name.take(160))))
     else loadMedia(u,r.getDouble("position")+engine.timelineOffset)
     requestStatus.text="已选择百度同一文件，等待双方准备好后由房主播放";true}
   }
  },{clearBaiduSource()}).show()
 }
 private fun playbackSource(url: String):String {
  if(localSourceRoomID==engine.room?.optString("roomId") && localSourceRoom==url){
   if(localFileUri.isNotBlank())return localFileUri
   if(activeLocalSource.isNotEmpty())return activeLocalSource
  }
  return url
 }
 private fun resolvedMediaUri(url:String)=if(url.startsWith("content://") || url.startsWith("file://"))url else MediaSources.resolve(url)
 private fun applyPendingLocalMovie(){
  val selection=pendingLocalMovie ?: return;val r=engine.room ?: return;if(!connected)return
  pendingLocalMovie=null
  if(r.optString("roomId")!=pendingLocalRoom || r.optString("mediaUrl")!=pendingLocalMedia){requestStatus.text="房间或影片已改变，请重新选择本地影片";return}
  useLocalMovie(selection.first,selection.second)
 }
 private fun retryPlayback(){
  val r=engine.room ?: return
  val url=if(BaiduMediaReference.parse(r.optString("mediaUrl"))!=null){if(!hasBaiduMatch()){requestStatus.text="请先选择同一影片";return};if(localFileUri.isNotBlank())localFileUri else baiduURL}else playbackSource(r.optString("mediaUrl"))
  requestStatus.text="正在重试播放…";loadMedia(url,r.optDouble("position")+engine.timelineOffset)
 }
 private fun loadMedia(url: String,position: Double){val resolved=resolvedMediaUri(url);if(player.currentMediaItem?.localConfiguration?.uri?.toString()!=resolved){clearSubtitle()};player.pause();val item=MediaItem.fromUri(android.net.Uri.parse(resolved));if(url==baiduURL){val network=androidx.media3.datasource.DefaultHttpDataSource.Factory().setUserAgent("pan.baidu.com");val factory=androidx.media3.exoplayer.source.DefaultMediaSourceFactory(androidx.media3.datasource.DefaultDataSource.Factory(this,network));player.setMediaSource(factory.createMediaSource(item),position.coerceAtLeast(0.0).toLong())}else player.setMediaItem(item,position.coerceAtLeast(0.0).toLong());player.prepare()}
 private fun localDisplayName(uri:android.net.Uri)=contentResolver.query(uri,arrayOf(android.provider.OpenableColumns.DISPLAY_NAME),null,null,null)?.use {if(it.moveToFirst())it.getString(0) else null} ?: "本地影片"
 private fun localFileIdentity(uri:android.net.Uri):Pair<Long,String> {
  val queried=contentResolver.query(uri,arrayOf(android.provider.OpenableColumns.SIZE),null,null,null)?.use {if(it.moveToFirst() && !it.isNull(0))it.getLong(0) else -1L} ?: -1L
  val pfd=contentResolver.openFileDescriptor(uri,"r") ?: throw IOException("无法打开本地影片")
  // AutoCloseInputStream owns the ParcelFileDescriptor. Closing a FileInputStream
  // around its raw fd and then pfd.use closed the fd twice and failed valid picks.
  android.os.ParcelFileDescriptor.AutoCloseInputStream(pfd).use {input->
   val size=(if(pfd.statSize>0)pfd.statSize else queried).takeIf {it in 1..9007199254740991L} ?: throw IOException("无法读取文件大小")
    val channel=input.channel;val samples=ArrayList<Pair<Long,ByteArray>>()
    for(off in BaiduFileIdentity.offsets(size)){
     val count=minOf(65536L,size-off).toInt();val bytes=ByteArray(count);channel.position(off);var read=0
     while(read<count){val n=input.read(bytes,read,count-read);if(n<0)throw java.io.EOFException("本地影片读取不完整");read+=n}
     samples.add(off to bytes)
    }
    return size to BaiduFileIdentity.sample(size,samples)
  }
 }
 private fun useLocalMovie(uri:android.net.Uri,grantFlags:Int){
  val room=engine.room ?: return;val expectedRoom=room.optString("roomId");val expectedMedia=room.optString("mediaUrl");val start=room.optDouble("position")+engine.timelineOffset
  val selection=localSelectionGeneration;val publish=isHost && localSelectionPublishes
  runCatching {contentResolver.takePersistableUriPermission(uri,grantFlags and android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION)}
  requestStatus.text="正在读取本地影片…"
  localFileLabel.text="正在读取本地影片…"
  Thread {
   val result=runCatching {
    val name=localDisplayName(uri);val target=BaiduMediaReference.parse(expectedMedia)
    var roomReference=target
    if(target!=null || publish){
     val identity=localFileIdentity(uri)
     if(target!=null && !target.matches(identity.second,identity.first))throw IOException("本地文件与房间影片不是同一文件")
     if(target==null && publish)roomReference=BaiduMediaReference.create(identity.second,identity.first) ?: throw IOException("本地文件身份生成失败")
    }
    Triple(name,target,roomReference)
   }
   main.post {
    if(stopped || selection!=localSelectionGeneration)return@post
    val current=engine.room
    if(current==null || current.optString("roomId")!=expectedRoom || current.optString("mediaUrl")!=expectedMedia){requestStatus.text="房间或影片已变化，请重新选择本地影片";return@post}
    result.onSuccess {(name,target,roomReference)->
     localFileUri=uri.toString();localFileName=name;localFileLabel.text="本地影片：$name";activeLocalSource="";localSource.text.clear();baiduURL=""
     if(roomReference!=null){baiduSourceID=roomReference.value;baiduSourceRoom=expectedRoom;localSourceRoom=roomReference.value;localSourceRoomID=expectedRoom}
     else {baiduSourceID="";baiduSourceRoom="";localSourceRoom=expectedMedia;localSourceRoomID=expectedRoom}
     if(isHost && target==null && roomReference!=null){enqueue(JSONObject().put("type","ROOM_MEDIA").put("data",JSONObject().put("mediaUrl",roomReference.value).put("title",name.take(160))))}
     else loadMedia(localFileUri,start)
     requestStatus.text=if(roomReference!=null)"本地同一文件已匹配；影片只从这台设备读取。" else "本地影片已应用；文件只从这台设备读取。"
    }.onFailure {requestStatus.text=if(it.message?.contains("不是同一文件")==true)"本地文件与房间影片不是同一文件，请选择与对方完全相同的版本。" else "读取本地影片失败，请确认文件已完整下载到设备本地。";localFileLabel.text=requestStatus.text}
   }
  }.start()
 }
 private fun clearLocalMovie(){
  localSelectionGeneration++;pendingLocalMovie=null
  if(localFileUri.isBlank()){requestStatus.text="当前没有本地影片";return}
  localFileUri="";localFileName="";if(::localFileLabel.isInitialized)localFileLabel.text="未选择本地影片";val r=engine.room
  if(r==null){requestStatus.text="本地影片已清除";return}
  if(BaiduMediaReference.parse(r.optString("mediaUrl"))!=null){baiduSourceID="";baiduSourceRoom="";player.pause();player.clearMediaItems();clearSubtitle();loadedURL="";requestStatus.text="本地影片已清除；当前房间仍需重新选择同一文件。"}
  else {localSourceRoom="";localSourceRoomID="";loadMedia(r.optString("mediaUrl"),r.optDouble("position")+engine.timelineOffset);requestStatus.text="本地影片已清除，已恢复房间片源。"}
 }
 private fun applyLocalSource(){val r=engine.room ?: return;if(BaiduMediaReference.parse(r.optString("mediaUrl"))!=null){requestStatus.text="当前房间使用文件匹配，请点“选择本地影片”或使用自己的百度授权选片";return};try {localFileUri="";localFileName="";if(::localFileLabel.isInitialized)localFileLabel.text="未选择本地影片";activeLocalSource=if(localSource.text.isBlank())"" else MediaSources.resolve(localSource.text.toString());localSourceRoom=r.getString("mediaUrl");localSourceRoomID=r.getString("roomId");loadMedia(playbackSource(localSourceRoom),r.getDouble("position")+engine.timelineOffset);requestStatus.text="已应用本机片源；链接不分享"}catch(e: Exception){requestStatus.text="本机链接无效"}}
 private fun setRoomMedia(){if(!isHost || !connected){requestStatus.text="请先作为房主连接";return};val source=media.text.toString();if(!MediaSources.canShare(source)){requestStatus.text="公用片源不能含账户凭据";return};enqueue(JSONObject().put("type","ROOM_MEDIA").put("data",JSONObject().put("mediaUrl",MediaSources.resolve(source)).put("title",titleField.text.toString())))}
 private fun enqueue(obj: JSONObject){if(queued.size>=8){requestStatus.text="请等待操作完成";return};queued.addLast(obj);flush()}
 private fun flush(){if(!isHost || !connected || !clock.ready || inFlight!=null || queued.isEmpty())return;val op=queued.removeFirst();inFlight=op;flightSequence=++sequence;send(JSONObject(op.toString()).put("sequence",sequence).put("baseVersion",engine.version))}
 private fun control(type: String,position: Double=0.0){if(!connected || !clock.ready){requestStatus.text="正在连接或校准";return};if(!position.isFinite())return;val op=JSONObject().put("type",type).put("position",position.coerceAtLeast(0.0));if(isHost)enqueue(op)else {send(JSONObject().put("type","CONTROL_REQUEST").put("sequence",++sequence).put("data",op));requestStatus.text="已请求房主批准"}}
 private fun saveProfile(){val n=offset.text.toString().toDoubleOrNull();if(n==null || !n.isFinite() || abs(n)>600 || nickname.text.toString().codePointCount(0,nickname.text.length)>32){requestStatus.text="昵称最多32字，偏移正负600秒";return};getPreferences(0).edit().putString("nickname",nickname.text.toString()).putString("offset",offset.text.toString()).apply();sendProfile()}
 private fun sendProfile(){val n=offset.text.toString().toDoubleOrNull()?.takeIf {it.isFinite() && abs(it)<=600} ?: 0.0;send(JSONObject().put("type","PROFILE_UPDATE").put("data",JSONObject().put("name",nickname.text.toString()).put("timelineOffset",n*1000)))}
 private fun addVoicePanel(parent:LinearLayout):VoiceDanmakuView {val view=VoiceDanmakuView(this,voice,{connected});voiceViews.add(view);parent.addView(view);return view}
 override fun onRequestPermissionsResult(requestCode:Int,permissions:Array<out String>,grantResults:IntArray){super.onRequestPermissionsResult(requestCode,permissions,grantResults);if(requestCode==VoiceDanmakuController.VOICE_PERMISSION)voice.permissionResult(grantResults.firstOrNull()==android.content.pm.PackageManager.PERMISSION_GRANTED)}
 private fun sendVoice(value:String):Boolean {val text=value.trim();if(!connected || text.isBlank() || text.codePointCount(0,text.length)>500 || outbox.size>=20)return false;val id="voice:"+UUID.randomUUID().toString();val op=JSONObject().put("type","CHAT_MESSAGE").put("data",JSONObject().put("text",text).put("clientMessageId",id).put("source","voice"));outbox[id]=op;send(op);return true}
 private fun sendChat(){val text=draft.text.toString().trim();if(!connected){requestStatus.text="重连后再发送";return};if(text.isBlank() || text.codePointCount(0,text.length)>1000 || outbox.size>=20){requestStatus.text="消息过长或等待发送中";return};val id=UUID.randomUUID().toString();val op=JSONObject().put("type","CHAT_MESSAGE").put("data",JSONObject().put("text",text).put("clientMessageId",id));outbox[id]=op;send(op);draft.setText("")}
 private fun acceptChat(raw: JSONObject,live: Boolean=false){val m=ChatMessage.parse(raw);outbox.remove(m.clientId);if(chat.accept(m,m.userId==credentials?.optString("userId"))){renderChat();if(live && (fullscreenDialog!=null || m.clientId.startsWith("voice:"))){if(danmakuPending.size<20)danmakuPending.addLast(Triple(m.text.take(500),clock.localNow(),if(m.clientId.startsWith("voice:"))4000L else 8000L));drainDanmaku()}}}
 private fun renderChat(){
  chatBubbles.removeAllViews()
  if(chat.messages.isEmpty()){label(chatBubbles,"加入房间后，和好友聊聊这部电影").apply {gravity=android.view.Gravity.CENTER;textSize=13f;setTextColor(0xff74818c.toInt());setPadding(dp(12),dp(28),dp(12),dp(24));layoutParams=LinearLayout.LayoutParams(-1,-2)}}
  chat.messages.takeLast(100).forEach {message->
   val mine=message.userId==credentials?.optString("userId")
   val row=LinearLayout(this).apply {orientation=LinearLayout.HORIZONTAL;gravity=if(mine)android.view.Gravity.END else android.view.Gravity.START;setPadding(0,dp(8),0,dp(8))}
   val avatar=ImageView(this).apply {setImageResource(R.drawable.ic_person);imageTintList=android.content.res.ColorStateList.valueOf(0xffe0e9ef.toInt());background=rounded(if(mine)0xff304452.toInt()else 0xff415465.toInt(),20);setPadding(dp(8),dp(8),dp(8),dp(8));contentDescription=message.name}
   val body=LinearLayout(this).apply {orientation=LinearLayout.VERTICAL;gravity=if(mine)android.view.Gravity.END else android.view.Gravity.START;setPadding(dp(8),0,dp(8),0)}
   val time=if(message.timestamp>0)java.text.SimpleDateFormat("HH:mm",java.util.Locale.getDefault()).format(java.util.Date(message.timestamp.toLong()))else ""
   label(body,"${if(mine)"我" else message.name}  $time").apply {textSize=11f;setTextColor(0xff88939d.toInt());setPadding(0,0,0,dp(6))}
   label(body,message.text).apply {textSize=15f;maxWidth=(resources.displayMetrics.widthPixels*if(resources.configuration.orientation==android.content.res.Configuration.ORIENTATION_LANDSCAPE)0.20 else 0.67).toInt();setPadding(dp(12),dp(10),dp(12),dp(10));background=rounded(if(mine)0xff1688ff.toInt()else 0xff20262c.toInt(),16);layoutParams=LinearLayout.LayoutParams(-2,-2)}
   if(!mine)row.addView(avatar,LinearLayout.LayoutParams(dp(36),dp(36)))
   row.addView(body,LinearLayout.LayoutParams(-2,-2))
   if(mine)row.addView(avatar,LinearLayout.LayoutParams(dp(36),dp(36)))
   chatBubbles.addView(row,LinearLayout.LayoutParams(-1,-2))
  }
  chatScroll.post {chatScroll.fullScroll(View.FOCUS_DOWN)};watchTab.text=if(chat.unread>0)"一起看 (${chat.unread})" else "一起看"
 }

 private fun showReaction(emoji: String){if(emoji !in listOf("😂","😱","😭","🤯","❤️","👀"))return;val v=TextView(this).apply {text=emoji;textSize=34f};videoBox.addView(v,FrameLayout.LayoutParams(-2,-2,android.view.Gravity.END or android.view.Gravity.CENTER_VERTICAL));v.animate().translationY(-dp(80).toFloat()).alpha(0f).setDuration(3000).withEndAction {videoBox.removeView(v)}.start()}
 private fun clearRoom(){voice.disable();localSelectionGeneration++;pendingLocalMovie=null;baiduSourceID="";baiduSourceRoom="";baiduURL="";localFileUri="";localFileName="";if(::localFileLabel.isInitialized)localFileLabel.text="未选择本地影片";activeLocalSource="";localSourceRoom="";localSourceRoomID="";localSource.text.clear();generation++;connected=false;ws?.cancel();credentials=null;getPreferences(0).edit().remove("credentials").apply();engine.resetSession();clearSubtitle();danmakuPending.clear();player.clearMediaItems();loadedURL="";queued.clear();inFlight=null;outbox.clear();chatRoom="";chat.reset("");renderChat();roomInput.setText("");presence.text="未连接";memberSummary="";onlineMembers=0;presence.setTextColor(0xff9cabb5.toInt());notice.text="";roomTitle.text="选择影片，开始一起看";status.text="已离开房间";requestStatus.text="";isHost=false}
 private fun diagnostic(event: String,details: JSONObject=JSONObject()){if(!connected)return;send(JSONObject().put("type","TELEMETRY").put("data",JSONObject().put("diagnostic",true).put("event",event).put("details",details).put("clientVersion",clientVersion).put("positionMs",player.currentPosition).put("version",engine.version).put("playbackRate",player.playbackParameters.speed).put("bufferedPositionMs",player.bufferedPosition).put("playbackState",player.playbackState)))}
 private val tick=object: Runnable {override fun run(){if(stopped)return;updatePlaybackUI();notice.visibility=if(notice.text.isBlank())View.GONE else View.VISIBLE;requestStatus.visibility=if(requestStatus.text.isBlank())View.GONE else View.VISIBLE;presence.visibility=if(presence.text.isBlank())View.GONE else View.VISIBLE;chat.tick(clock.localNow());typing.text=if(chat.typingName.isBlank())"" else "${chat.typingName} 正在输入…";if(foreground && connected){val error=engine.tick();ticks++;flush();if(ticks%10==0){send(JSONObject().put("type","SYNC"));val ready=(BaiduMediaReference.parse(engine.room?.optString("mediaUrl") ?: "")==null || hasBaiduMatch()) && RecoveryBufferPolicy.ready(player.playbackState==Player.STATE_READY || player.playbackState==Player.STATE_ENDED,(player.bufferedPosition-player.currentPosition).coerceAtLeast(0),player.currentPosition,player.duration,engine.room?.optBoolean("autoResume")==true && localFileUri.isBlank());send(JSONObject().put("type","PLAYER_STATUS").put("data",JSONObject().put("sourceId",if(hasBaiduMatch())baiduSourceID else "").put("ready",ready).put("buffering",player.playbackState==Player.STATE_BUFFERING).put("position",(player.currentPosition-engine.timelineOffset).coerceAtLeast(0.0)).put("duration",player.duration.coerceAtLeast(0))));val target=engine.target();send(JSONObject().put("type","TELEMETRY").put("data",JSONObject().put("clientVersion",clientVersion).put("serverTimeMs",if(clock.ready)clock.serverNow() else JSONObject.NULL).put("ready",ready).put("timelineOffsetMs",engine.timelineOffset).put("executeAtMs",engine.room?.optDouble("executeAt",0.0) ?: 0.0).put("resyncCount",engine.resyncCount).put("positionMs",player.currentPosition).put("expectedMs",target?.first).put("errorMs",if(error!=null)target!!.first-player.currentPosition else JSONObject.NULL).put("rttMs",clock.rtt).put("version",engine.version).put("playing",player.isPlaying).put("buffering",!ready).put("playbackRate",player.playbackParameters.speed)));val bufferedSeconds=((player.bufferedPosition-player.currentPosition).coerceAtLeast(0)/1000);status.text="$clientVersion ${if(isHost)"HOST" else "GUEST"} room=${credentials?.optString("roomId")} v=${engine.version}\n位置 ${player.currentPosition/1000}s 误差 ${error?.toInt()}ms RTT ${clock.rtt.toInt()}ms\n视频 ${player.videoFormat?.sampleMimeType ?: "等待"} 音频 ${player.audioFormat?.sampleMimeType ?: "等待"}\n已缓存 ${bufferedSeconds}s"};if(ticks%150==0)pingBurst()};main.postDelayed(this,100)}}
 private fun disconnectForTest(){generation++;val g=generation;ws?.cancel();connected=false;engine.resetSession();main.postDelayed({if(!stopped && foreground && generation==g)connect()},3000)}
 override fun onDestroy(){voice.close();stopped=true;fullscreenDialog?.dismiss();generation++;main.removeCallbacksAndMessages(null);ws?.cancel();player.release();baidu.close();http.dispatcher.executorService.shutdown();super.onDestroy()}
}
