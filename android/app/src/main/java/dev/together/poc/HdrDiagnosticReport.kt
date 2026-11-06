package dev.together.poc

import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.os.Build
import androidx.media3.common.Format
import org.json.JSONArray
import org.json.JSONObject

/** Local-only, bounded technical report; excludes media URLs, file names and room/user identifiers. */
internal object HdrDiagnosticReport {
 private val nativeFields=setOf(
  "decodedVideo","displayedVideo","decodedAudio","playedAudioBuffers",
  "demuxCorrupted","nativeState","nativeRate","requestedRate",
  "bufferingPercent","surfaceRetained","surfaceRestores","selectedVideo",
  "hdrHardwareSurfaceRequested","wantedPlaying","nativeVolume","selectedAudio")
 private fun label(raw:String?):String {
  val value=raw?.trim().orEmpty()
  return value.take(96).takeIf {it.isNotBlank() && it.matches(Regex("[\\p{L}\\p{N} ._+:-]{1,96}"))}.orEmpty()
 }
 fun create(
  appVersion:String,manufacturer:String,model:String,sdk:Int,
  format:Format?,media3VideoDecoder:String,media3AudioDecoder:String,
  compatibleActive:Boolean,isPlaying:Boolean,playbackState:Int,positionMs:Long,
  scheme:String?,nativeHealth:Map<String,Any>,recentEvents:JSONArray,
  codecCandidates:JSONArray=JSONArray()
 ):JSONObject {
  val root=JSONObject().put("reportSchema",1)
   .put("createdUtc",java.time.Instant.now().toString())
   .put("appVersion",label(appVersion))
   .put("manufacturer",label(manufacturer)).put("deviceModel",label(model)).put("sdk",sdk)
  val playback=JSONObject()
   .put("independentVlcActive",compatibleActive).put("isPlaying",isPlaying)
   .put("state",playbackState).put("positionMs",positionMs.coerceAtLeast(0))
   .put("sourceScheme",label(scheme))
   .put("media3VideoDecoder",label(media3VideoDecoder))
   .put("media3AudioDecoder",label(media3AudioDecoder))
  root.put("playback",playback)
  val picture=JSONObject()
  if(format!=null){
   picture.put("mimeType",label(format.sampleMimeType))
    .put("codecs",label(format.codecs))
    .put("width",format.width).put("height",format.height)
    .put("frameRate",format.frameRate)
   format.colorInfo?.let {color->
    picture.put("colorSpace",color.colorSpace).put("colorTransfer",color.colorTransfer)
     .put("colorRange",color.colorRange).put("hasHdrStaticInfo",color.hdrStaticInfo!=null)
   }
  }
  root.put("videoFormat",picture)
  val native=JSONObject()
  for((key,value) in nativeHealth){
   if(key !in nativeFields)continue
   if(value is Number || value is Boolean)native.put(key,value)
  }
  root.put("vlcOutput",native)
  val safeEvents=JSONArray()
  val start=(recentEvents.length()-120).coerceAtLeast(0)
  for(i in start until recentEvents.length()){
   val row=recentEvents.optJSONObject(i) ?: continue
   safeEvents.put(PlaybackDiagnosticJournal.sanitize(row))
  }
  root.put("recentEvents",safeEvents)
  // This is the OS-declared candidate list, never a claim about VLC's selected codec.
  val candidates=JSONArray()
  for(i in 0 until minOf(codecCandidates.length(),24)){
   val c=codecCandidates.optJSONObject(i) ?: continue
   val entry=JSONObject()
   for(k in listOf("name","hardware","software","main10","supports4k24")){
    val v=c.opt(k)
    if(k=="name" && v is String)entry.put(k,label(v))
    else if(v is Boolean)entry.put(k,v)
   }
   candidates.put(entry)
  }
  root.put("osHevcDecoderCandidates",candidates)
  return root
 }

 fun osHevcDecoderCandidates():JSONArray {
  val result=JSONArray()
  val codecs=runCatching {MediaCodecList(MediaCodecList.ALL_CODECS).codecInfos}.getOrNull() ?: return result
  for(info in codecs){
   if(info.isEncoder || info.supportedTypes.none {it.equals("video/hevc",true)})continue
   val caps=runCatching {info.getCapabilitiesForType("video/hevc")}.getOrNull() ?: continue
   val item=JSONObject().put("name",label(info.name))
    .put("main10",caps.profileLevels.any {it.profile==MediaCodecInfo.CodecProfileLevel.HEVCProfileMain10})
   if(Build.VERSION.SDK_INT>=29){
    item.put("hardware",info.isHardwareAccelerated).put("software",info.isSoftwareOnly)
   }
   val supports=runCatching {caps.videoCapabilities?.areSizeAndRateSupported(3840,2160,24.0)}.getOrNull()
   if(supports!=null)item.put("supports4k24",supports)
   result.put(item)
   if(result.length()>=24)break
  }
  return result
 }
}
