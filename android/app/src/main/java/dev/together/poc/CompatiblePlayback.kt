package dev.together.poc

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import androidx.media3.common.*
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.analytics.AnalyticsListener
import androidx.media3.exoplayer.source.MediaSource
import org.videolan.libvlc.LibVLC
import org.videolan.libvlc.Media
import org.videolan.libvlc.MediaPlayer as VLCPlayer
import org.videolan.libvlc.interfaces.IMedia
import org.videolan.libvlc.util.VLCVideoLayout
import kotlin.math.abs
import kotlin.math.roundToInt

/** A narrow local-video fallback. ExoPlayer remains the normal playback path. */
class CompatiblePlayback(private val context:Context,private val native:ExoPlayer,
 private val changed:(Boolean)->Unit,private val failed:(String)->Unit):ForwardingPlayer(native) {
 private val main=Handler(Looper.getMainLooper())
 private var layout:VLCVideoLayout?=null
 private var rotatedVideoOutput=false
 fun setRotatedVideoOutput(rotated:Boolean){
  if(rotatedVideoOutput==rotated)return
  rotatedVideoOutput=rotated
  if(compatibleActive){vlc?.detachViews();rebindVideoOutput()}
 }
 private var core:LibVLC?=null
 private var vlc:VLCPlayer?=null
 private var source:Media?=null
 private var descriptor:ParcelFileDescriptor?=null
 private var epoch=0
 private var state=Player.STATE_IDLE
 private var wanted=false
 private var ready=false
 private var startPosition=0L
 private var item:MediaItem?=null
 private var speed=1f
 private var buffering=0f
 private var failure:PlaybackException?=null
 private var nativeVideo:Format?=null
 private var nativeAudio:Format?=null
 private var pendingSeek:Long?=null
 private var pendingUntil=0L
 private var requestedSubtitle:Int?=null
 private val compatibleSources=linkedSetOf<String>()
 var compatibleActive=false;private set
 val videoFormat:Format? get()=if(compatibleActive)nativeVideo else native.videoFormat
 val audioFormat:Format? get()=if(compatibleActive)nativeAudio else native.audioFormat
 fun addAnalyticsListener(listener:AnalyticsListener)=native.addAnalyticsListener(listener)
 fun bind(view:VLCVideoLayout){
  layout=view
  view.addOnAttachStateChangeListener(object:android.view.View.OnAttachStateChangeListener {
   override fun onViewDetachedFromWindow(v:android.view.View){if(compatibleActive)vlc?.detachViews()}
   override fun onViewAttachedToWindow(v:android.view.View){main.post {rebindVideoOutput()}}
  })
 }
 private fun rebindVideoOutput(){
  val p=vlc ?: return;val view=layout ?: return
  if(!compatibleActive || source==null || !view.isAttachedToWindow || p.vlcVout.areViewsAttached())return
  p.detachViews();p.attachViews(view,null,true,rotatedVideoOutput)
  applySubtitleSelection()
 }
 private fun applySubtitleSelection(){
  if(source==null)return
  val id=requestedSubtitle ?: if(native.trackSelectionParameters.disabledTrackTypes.contains(C.TRACK_TYPE_TEXT))-1 else return
  vlc?.let {p->if(id<0 || p.spuTracks?.any {it.id==id}==true)p.setSpuTrack(id)}
 }
 fun activateCompatibility(uri:String,positionMs:Long):Boolean {
  if(layout==null || compatibleActive || android.net.Uri.parse(uri).scheme !in listOf("content","file"))return false
  nativeVideo=native.videoFormat;nativeAudio=native.audioFormat
  item=native.currentMediaItem ?: return false
  if(item?.localConfiguration?.uri?.toString()!=uri)return false
  native.pause();native.stop();compatibleSources.add(uri)
  startPosition=positionMs.coerceAtLeast(0);wanted=false
  return openIndependent(uri)
 }
 private fun openIndependent(uri:String):Boolean {
  epoch++;val token=epoch
  closeInput();ready=false;buffering=0f;state=Player.STATE_BUFFERING;failure=null
  compatibleActive=true;changed(true)
  try {
   if(core==null){core=LibVLC(context,arrayListOf("--no-video-title-show","--stats"));vlc=VLCPlayer(core!!).also {p->
    p.vlcVout.addCallback(object:org.videolan.libvlc.interfaces.IVLCVout.Callback {
     override fun onSurfacesDestroyed(vout:org.videolan.libvlc.interfaces.IVLCVout){main.post {rebindVideoOutput()}}
     override fun onSurfacesCreated(vout:org.videolan.libvlc.interfaces.IVLCVout){main.post {
      if(compatibleActive && source!=null){applySubtitleSelection();if(ready){if(wanted)p.play()else p.pause()}}
     }}
    })
   }}
   val p=vlc!!;p.detachViews();p.attachViews(layout!!,null,true,rotatedVideoOutput)
   p.setEventListener {event->
    if(token!=epoch || !compatibleActive)return@setEventListener
    when(event.type){
     VLCPlayer.Event.EncounteredError->fail("独立 HEVC 解码器无法读取该影片")
     VLCPlayer.Event.EndReached->{state=Player.STATE_ENDED;wanted=false}
     VLCPlayer.Event.Buffering->{buffering=event.buffering; if(ready)state=if(buffering<100f)Player.STATE_BUFFERING else Player.STATE_READY}
     VLCPlayer.Event.TimeChanged->{pendingSeek?.let {if(abs(event.timeChanged-it)<500)pendingSeek=null}}
     VLCPlayer.Event.ESAdded->applySubtitleSelection()
    }
   }
   val parsed=android.net.Uri.parse(uri)
   descriptor=if(parsed.scheme=="content")context.contentResolver.openFileDescriptor(parsed,"r") else null
   source=if(parsed.scheme=="content")Media(core!!,descriptor?.fileDescriptor ?: throw java.io.IOException("无法打开本地影片"))else Media(core!!,parsed)
   source!!.setHWDecoderEnabled(false,false)
   source!!.addOption(":codec=avcodec")
   source!!.addOption(":file-caching=1000")
   source!!.addOption(":network-caching=12000")
   source!!.addOption(":http-user-agent=pan.baidu.com")
   source!!.addOption(":start-time=${startPosition/1000.0}")
   p.media=source;p.setVolume(0);p.setRate(speed);p.play()
   val deadline=android.os.SystemClock.elapsedRealtime()+45000
   fun awaitFrame(){
    if(token!=epoch || !compatibleActive || failure!=null)return
    if((source?.stats?.displayedPictures ?: 0)>0){
     ready=true;state=Player.STATE_READY;buffering=100f
     if(!wanted)p.pause()
     p.setVolume((native.volume*100).roundToInt())
     applySubtitleSelection()
     changed(true)
    }else if(android.os.SystemClock.elapsedRealtime()>=deadline)fail("兼容解码准备超时，未显示视频帧")
    else main.postDelayed({awaitFrame()},50)
   }
   main.post {awaitFrame()}
   return true
  }catch(e:Exception){fail("兼容播放准备失败：${e.localizedMessage ?: e.javaClass.simpleName}");return true}
 }
 private fun fail(message:String){failure=PlaybackException(message,null,PlaybackException.ERROR_CODE_DECODING_FAILED);wanted=false;state=Player.STATE_IDLE;vlc?.stop();failed(message)}
 private fun closeInput(){vlc?.stop();vlc?.media=null;source?.release();source=null;descriptor?.close();descriptor=null;pendingSeek=null}
 private fun deactivate(){epoch++;closeInput();compatibleActive=false;ready=false;wanted=false;state=Player.STATE_IDLE;failure=null;changed(false)}
 override fun getCurrentMediaItem():MediaItem?=if(compatibleActive)item else native.currentMediaItem
 override fun getCurrentPosition():Long {
  if(!compatibleActive)return native.currentPosition
  pendingSeek?.let {if(android.os.SystemClock.elapsedRealtime()<pendingUntil)return it;pendingSeek=null}
  return (vlc?.time ?: -1).takeIf {it>=0} ?: startPosition
 }
 override fun getDuration():Long=if(compatibleActive)(vlc?.length ?: 0).coerceAtLeast(0) else native.duration
 override fun getBufferedPosition():Long {
  if(!compatibleActive)return native.bufferedPosition
  val local=item?.localConfiguration?.uri?.scheme in listOf("file","content")
  return if(local && ready)duration else (currentPosition+12000*buffering.toLong()/100).coerceAtMost(duration.takeIf {it>0} ?: Long.MAX_VALUE)
 }
 override fun getPlaybackState():Int=if(compatibleActive)state else native.playbackState
 override fun getPlayerError():PlaybackException?=if(compatibleActive)failure else native.playerError
 override fun getPlayWhenReady():Boolean=if(compatibleActive)wanted else native.playWhenReady
 override fun isPlaying():Boolean=if(compatibleActive)ready && wanted && vlc?.isPlaying==true else native.isPlaying
 override fun isLoading():Boolean=if(compatibleActive)state==Player.STATE_BUFFERING else native.isLoading
 override fun setPlayWhenReady(value:Boolean){if(!compatibleActive){native.playWhenReady=value;return};wanted=value;if(ready){if(value)vlc?.play()else vlc?.pause()}}
 override fun play()=setPlayWhenReady(true)
 override fun pause()=setPlayWhenReady(false)
 override fun seekTo(positionMs:Long){if(!compatibleActive){native.seekTo(positionMs);return};startPosition=positionMs.coerceIn(0,duration.takeIf {it>0} ?: Long.MAX_VALUE);pendingSeek=startPosition;pendingUntil=android.os.SystemClock.elapsedRealtime()+3000;vlc?.setTime(startPosition,false)}
 override fun seekTo(mediaItemIndex:Int,positionMs:Long){if(compatibleActive)seekTo(positionMs)else native.seekTo(mediaItemIndex,positionMs)}
 override fun setVolume(value:Float){native.volume=value.coerceIn(0f,1f);if(compatibleActive && ready)vlc?.setVolume((native.volume*100).roundToInt())}
 override fun getVolume():Float=native.volume
 override fun setPlaybackSpeed(value:Float)=setPlaybackParameters(PlaybackParameters(value))
 override fun setPlaybackParameters(value:PlaybackParameters){speed=value.speed;native.playbackParameters=value;if(compatibleActive)vlc?.setRate(speed)}
 override fun getPlaybackParameters():PlaybackParameters=if(compatibleActive)PlaybackParameters(speed)else native.playbackParameters
 override fun setTrackSelectionParameters(value:TrackSelectionParameters){native.trackSelectionParameters=value;if(compatibleActive && value.disabledTrackTypes.contains(C.TRACK_TYPE_TEXT)){requestedSubtitle=-1;applySubtitleSelection()}}
 override fun setMediaItem(value:MediaItem,startPositionMs:Long){if(value.localConfiguration?.uri!=item?.localConfiguration?.uri)requestedSubtitle=null;if(compatibleActive)deactivate();item=value;startPosition=startPositionMs;native.setMediaItem(value,startPositionMs)}
 fun setMediaSource(value:MediaSource,startPositionMs:Long){if(value.mediaItem.localConfiguration?.uri!=item?.localConfiguration?.uri)requestedSubtitle=null;if(compatibleActive)deactivate();item=value.mediaItem;startPosition=startPositionMs;native.setMediaSource(value,startPositionMs)}
 override fun prepare(){val uri=native.currentMediaItem?.localConfiguration?.uri?.toString();if(uri!=null && uri in compatibleSources)openIndependent(uri)else native.prepare()}
 override fun stop(){if(compatibleActive){epoch++;closeInput();ready=false;state=Player.STATE_IDLE;wanted=false}else native.stop()}
 override fun clearMediaItems(){requestedSubtitle=null;if(compatibleActive)deactivate();item=null;native.clearMediaItems()}
 override fun release(){epoch++;closeInput();vlc?.detachViews();vlc?.release();vlc=null;core?.release();core=null;native.release()}
 data class TrackOption(val id:Int,val name:String)
 fun compatibleTracks(type:Int):List<TrackOption> {
  val p=vlc ?: return emptyList();val tracks=if(type==C.TRACK_TYPE_AUDIO)p.audioTracks else p.spuTracks
  return (tracks ?: emptyArray()).filter {it.id>=0}.mapIndexed {index,t->
   val info=(0 until (source?.trackCount ?: 0)).mapNotNull {source?.getTrack(it)}.firstOrNull {it.id==t.id && it.type==(if(type==C.TRACK_TYPE_AUDIO)IMedia.Track.Type.Audio else IMedia.Track.Type.Text)}
   val codec=info?.codec?.trim()?.uppercase() ?: ""
   val channels=(info as? IMedia.AudioTrack)?.channels ?: -1
   TrackOption(t.id,TrackLabel.label(t.name,info?.language,null,channels,index+1,type==C.TRACK_TYPE_TEXT)+(if(codec.isBlank())"" else " · $codec"))
  }
 }
 fun selectedCompatibleTrack(type:Int):Int=if(type==C.TRACK_TYPE_AUDIO)vlc?.audioTrack ?: -1 else vlc?.spuTrack ?: -1
 fun selectCompatibleTrack(type:Int,id:Int){if(type==C.TRACK_TYPE_AUDIO)vlc?.setAudioTrack(id)else{requestedSubtitle=id;native.trackSelectionParameters=native.trackSelectionParameters.buildUpon().setTrackTypeDisabled(C.TRACK_TYPE_TEXT,id<0).build();vlc?.setSpuTrack(id)}}
 fun decodedFrames():Int=source?.stats?.decodedVideo ?: 0
 fun displayedFrames():Int=source?.stats?.displayedPictures ?: 0
}
