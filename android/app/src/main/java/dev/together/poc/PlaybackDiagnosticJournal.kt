package dev.together.poc
import java.io.File
import java.util.concurrent.*
import org.json.JSONObject

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
 fun close(){writer.shutdown()}
 companion object {
  private val keys=setOf("clientVersion","positionMs","version","playbackRate","bufferedPositionMs","playbackState","sourceKind","localBindingActive","code","errorCode","rendererType","mimeType","decoderMimeType","codecs","width","height","frameRate","httpStatus","category","recoverable","codecName","failedCodec","nextCodec","deviceModel","manufacturer","sdk","loadTimeMs","bytesLoaded","bitrateEstimate","droppedFrames","oldState","reason","sourceScheme","hdrHardwareSurfaceRequested","boundedHardwareTrial","colorTransfer","colorSpace")
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
