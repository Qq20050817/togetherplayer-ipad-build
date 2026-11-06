package dev.together.poc
import java.io.File
import java.util.concurrent.*
import org.json.JSONObject
import org.json.JSONArray

/** Private, bounded code/format diagnostics, with no URLs, credentials or media names. */
internal class PlaybackDiagnosticJournal(private val file:File) {
 private val writer=ThreadPoolExecutor(1,1,0L,TimeUnit.MILLISECONDS,ArrayBlockingQueue<Runnable>(32),{r->Thread(r,"playback-diagnostic-writer").apply{isDaemon=true}},ThreadPoolExecutor.DiscardOldestPolicy())
 fun record(event:String,payload:JSONObject){
  val safe=sanitize(payload).put("event",if(Regex("[A-Za-z][A-Za-z0-9_]{0,59}").matches(event))event else "invalid_event").put("elapsedMs",android.os.SystemClock.elapsedRealtime()).toString()
  runCatching {writer.execute {runCatching {
   if(file.length()>65536){val previous=File(file.parentFile,file.name+".previous");previous.delete();file.renameTo(previous)}
   file.appendText(safe+"\n",Charsets.UTF_8)
  }}}
 }
 /** Read a bounded, re-sanitized snapshot for user-chosen local file export. */
 fun recentSafeRecords(maxRecords:Int=120):JSONArray {
  val previous=File(file.parentFile,file.name+".previous")
  val all=listOf(previous,file).flatMap {candidate->
   if(!candidate.isFile)return@flatMap emptyList<String>()
   runCatching {candidate.readLines(Charsets.UTF_8)}.getOrDefault(emptyList())
  }
  val result=JSONArray()
  for(line in all.takeLast(maxRecords.coerceIn(1,120))){
   val obj=runCatching {JSONObject(line)}.getOrNull() ?: continue
   result.put(sanitize(obj))
  }
  return result
 }
 fun close(){writer.shutdown()}
 companion object {
  private val keys=setOf("event","elapsedMs","decodedVideo","displayedVideo","decodedAudio","playedAudioBuffers","demuxCorrupted","nativeState","nativeRate","requestedRate","bufferingPercent","surfaceRetained","surfaceRestores","selectedVideo","wantedPlaying","nativeVolume","selectedAudio","clientVersion","positionMs","version","playbackRate","bufferedPositionMs","playbackState","sourceKind","localBindingActive","code","errorCode","rendererType","mimeType","decoderMimeType","codecs","width","height","frameRate","httpStatus","category","recoverable","codecName","failedCodec","nextCodec","deviceModel","manufacturer","sdk","loadTimeMs","bytesLoaded","bitrateEstimate","droppedFrames","oldState","reason","sourceScheme","hdrHardwareSurfaceRequested","boundedHardwareTrial","colorTransfer","colorSpace")
  fun sanitize(input:JSONObject):JSONObject {
   val output=JSONObject()
   for(key in input.keys()){
    val value=input.opt(key)
    if(key=="details" && value is JSONObject){output.put(key,sanitize(value));continue}
    if(key !in keys)continue
    when(value){
     is Number,is Boolean->output.put(key,value)
     is String->if(value.length<=160 && !value.contains("://") && !value.contains('?') && !value.contains("Bearer ",true) && !value.startsWith('/'))output.put(key,value)
    }
   }
   return output
  }
 }
}
