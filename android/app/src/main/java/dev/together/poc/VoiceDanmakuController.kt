package dev.together.poc

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.media.*
import android.media.audiofx.AcousticEchoCanceler
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import androidx.media3.exoplayer.ExoPlayer
import org.json.JSONObject
import org.vosk.Model
import org.vosk.Recognizer
import java.io.File
import java.net.URL
import java.security.MessageDigest
import java.util.zip.ZipInputStream
import java.util.concurrent.Executors

/** Offline Chinese recognizer. Only the downloaded model is stored; mic PCM remains in RAM. */
class VoiceDanmakuController(private val activity:Activity,private val player:ExoPlayer,
 private val room:()->String,private val send:(String)->Boolean,private val changed:()->Unit) {
 enum class State {DISABLED,PREPARING,READY,RECORDING,FINISHING,REVIEW}
 var state=State.DISABLED;private set
 var status="语音弹幕未开启";private set
 var preview=""
 var threshold=0.012;var maxSeconds=60;var maxCharacters=300
 var level=0.0;private set
 val busy get()=state in listOf(State.PREPARING,State.RECORDING,State.FINISHING,State.REVIEW)
 private val main=Handler(Looper.getMainLooper())
 private val worker=Executors.newSingleThreadExecutor()
 private var model:Model?=null
 @Volatile private var recording=false
 @Volatile private var epoch=0
 @Volatile private var disposed=false
 private var permissionEpoch=0
 @Volatile private var input:AudioRecord?=null
 private val gate=VoiceSendGate()
 private var originalVolume:Float?=null
 private var ramp:android.animation.ValueAnimator?=null
 fun enable(){
  if(disposed || state!=State.DISABLED)return
  epoch++;permissionEpoch=epoch
  if(activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO)!=PackageManager.PERMISSION_GRANTED){state=State.PREPARING;status="等待麦克风权限";changed();activity.requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO),VOICE_PERMISSION);return}
  prepareModel(epoch)
 }
 fun permissionResult(granted:Boolean){if(state!=State.PREPARING || permissionEpoch!=epoch)return;if(granted)prepareModel(epoch)else{state=State.DISABLED;status="麦克风权限被拒绝，电影继续播放";changed()}}
 private fun prepareModel(token:Int){
  state=State.PREPARING;status="准备免费离线中文模型（首次下载约 42MB）…";changed()
  worker.execute {
   try {
    if(model==null){val dir=File(activity.filesDir,"voice-model-cn");if(!File(dir,".verified").exists())downloadModel(dir,token);if(token!=epoch || disposed)return@execute;model=Model(File(dir,"vosk-model-small-cn-0.22").absolutePath)}
    main.post {if(token==epoch && !disposed){state=State.READY;status="离线识别已就绪，按住说话；松开预览，确认才发送";changed()}}
   }catch(e:Exception){main.post {if(token==epoch && !disposed){state=State.DISABLED;status="本地模型准备失败，请检查网络后重新启用";changed()}}}
  }
 }
 private fun downloadModel(dir:File,token:Int){
  dir.deleteRecursively();dir.mkdirs()
  val archive=File(activity.cacheDir,"voice-cn-model.zip")
  try {
   val digest=MessageDigest.getInstance("SHA-256")
   val connection=URL(MODEL_URL).openConnection().apply {connectTimeout=15000;readTimeout=30000}
   connection.getInputStream().use {source->archive.outputStream().use {out->val block=ByteArray(65536);var total=0L;while(true){if(token!=epoch || disposed)throw java.io.InterruptedIOException();val n=source.read(block);if(n<0)break;total+=n;check(total<60_000_000);digest.update(block,0,n);out.write(block,0,n)}}}
   check(digest.digest().joinToString(""){"%02x".format(it)}==MODEL_SHA)
   ZipInputStream(archive.inputStream()).use {zip->var expanded=0L;var count=0;while(true){if(token!=epoch || disposed)throw java.io.InterruptedIOException();val entry=zip.nextEntry ?: break;check(++count<1000);val file=File(dir,entry.name);check(file.canonicalPath.startsWith(dir.canonicalPath+File.separator));if(entry.isDirectory)file.mkdirs()else{file.parentFile?.mkdirs();file.outputStream().use {out->val block=ByteArray(65536);while(true){val n=zip.read(block);if(n<0)break;expanded+=n;check(expanded<160_000_000);out.write(block,0,n)}}}}}
   File(dir,".verified").writeText(MODEL_SHA)
  }finally{archive.delete()}
 }
 fun begin(){
  if(state!=State.READY || model==null || room().isBlank())return
  epoch++;val token=epoch
  gate.begin(room());gate.limit=maxCharacters;preview="";state=State.RECORDING;status="录音中 · 松开预览，上滑取消";recording=true
  duck(true);changed()
  val seconds=maxSeconds.coerceIn(30,120);val thresholdValue=threshold.coerceIn(0.001,0.1)
  worker.execute {
   var audio:AudioRecord?=null;var echo:AcousticEchoCanceler?=null;var recognizer:Recognizer?=null
   try {
    val size=AudioRecord.getMinBufferSize(16000,AudioFormat.CHANNEL_IN_MONO,AudioFormat.ENCODING_PCM_16BIT).coerceAtLeast(6400)
    audio=AudioRecord(MediaRecorder.AudioSource.VOICE_RECOGNITION,16000,AudioFormat.CHANNEL_IN_MONO,AudioFormat.ENCODING_PCM_16BIT,size)
    check(audio.state==AudioRecord.STATE_INITIALIZED)
    input=audio
    val manager=activity.getSystemService(android.content.Context.AUDIO_SERVICE) as AudioManager
    manager.getDevices(AudioManager.GET_DEVICES_INPUTS).firstOrNull {it.type==AudioDeviceInfo.TYPE_BUILTIN_MIC}?.let {audio.setPreferredDevice(it)}
    if(AcousticEchoCanceler.isAvailable())echo=AcousticEchoCanceler.create(audio.audioSessionId)?.apply {enabled=true}
    recognizer=Recognizer(model,16000f)
    val samples=ShortArray(1600);val filter=VoiceNoiseGate(thresholdValue);val parts=mutableListOf<String>();val start=SystemClock.elapsedRealtime();var lastUI=0L
    audio.startRecording();check(audio.recordingState==AudioRecord.RECORDSTATE_RECORDING)
    while(recording && token==epoch && !disposed){
     val n=audio.read(samples,0,samples.size);check(n>=0);if(n==0)continue
     val now=SystemClock.elapsedRealtime();var energy=0.0;for(i in 0 until n){val v=samples[i]/32768.0;energy+=v*v};val rms=kotlin.math.sqrt(energy/n)
     if(!filter.accepts(rms,now))java.util.Arrays.fill(samples,0,n,0.toShort())
     if(recognizer.acceptWaveForm(samples,n)){val text=JSONObject(recognizer.result).optString("text");if(text.isNotBlank())parts.add(text)}
     if(now-lastUI>=250){lastUI=now;val partial=JSONObject(recognizer.partialResult).optString("partial");val text=(parts+partial).joinToString(" ");main.post {if(token==epoch && state==State.RECORDING){preview=text;level=(rms*10).coerceIn(0.0,1.0);changed()}}}
     if(now-start>=seconds*1000L){recording=false;main.post {if(token==epoch){state=State.FINISHING;gate.finish();status="已到录音上限，正在完成识别；不会自动发送";duck(false);changed()}}}
    }
    val final=JSONObject(recognizer.finalResult).optString("text");val text=(parts+final).joinToString(" ").trim()
    main.post {if(token==epoch && !disposed){duck(false);gate.finish();if(text.isBlank() || text.replace(" ","").contains("取消弹幕")){cancel("未识别到文字或已取消，未发送")}else{gate.review(text);preview=text;state=State.REVIEW;level=0.0;status="检查或修改文字后确认发送";changed()}}}
   }catch(e:Exception){main.post {if(token==epoch && !disposed)cancel("麦克风或本地识别失败，未发送；电影继续播放")}}
   finally{runCatching {audio?.stop()};audio?.release();echo?.release();recognizer?.close();input=null}
  }
 }
 fun release(cancelled:Boolean=false){if(state!=State.RECORDING)return;if(cancelled){cancel();return};recording=false;state=State.FINISHING;gate.finish();duck(false);status="完成本地识别中…";changed()}
 fun confirm(){if(state!=State.REVIEW)return;gate.text=preview;gate.limit=maxCharacters;if(gate.confirm(room(),send)){preview="";state=State.READY;status="已提交发送，按住可继续说话"}else status="未发送：请检查连接、文字和字数上限";changed()}
 fun cancel(message:String="已取消，未发送") {epoch++;recording=false;runCatching {input?.stop()};gate.cancel();duck(false);level=0.0;preview="";state=if(model==null)State.DISABLED else State.READY;status=message;changed()}
 fun disable(){cancel("语音弹幕已关闭，麦克风已释放");state=State.DISABLED;changed()}
 fun close(){disable();ramp?.cancel();disposed=true;worker.execute {model?.close();model=null};worker.shutdown()}
 fun setUserVolume(value:Float){val volume=value.coerceIn(0f,1f);if(originalVolume!=null){originalVolume=volume;duck(true)}else{ramp?.cancel();player.volume=volume}}
 private fun duck(lower:Boolean){
  ramp?.cancel()
  val target=if(lower){if(originalVolume==null)originalVolume=player.volume;originalVolume!!*0.22f}else{val value=originalVolume ?: return;originalVolume=null;value}
  ramp=android.animation.ValueAnimator.ofFloat(player.volume,target).apply {duration=300;interpolator=android.view.animation.AccelerateDecelerateInterpolator();addUpdateListener {player.volume=it.animatedValue as Float};start()}
 }
 companion object {const val VOICE_PERMISSION=702;const val MODEL_URL="https://alphacephei.com/vosk/models/vosk-model-small-cn-0.22.zip";const val MODEL_SHA="3af8b0e7e0f835ae9d414ce5df580237a3cfb08d586c9fbbb0f7ff29ad5b14ba"}
}
