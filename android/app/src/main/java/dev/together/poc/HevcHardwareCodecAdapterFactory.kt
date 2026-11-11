package dev.together.poc

import android.media.MediaFormat
import android.os.Build
import androidx.media3.exoplayer.mediacodec.MediaCodecAdapter
import androidx.media3.exoplayer.mediacodec.SynchronousMediaCodecAdapter
import java.io.IOException

/** Retry a failed Main10 hardware configuration before abandoning MediaCodec. */
internal class HevcHardwareCodecAdapterFactory(
 private val standard:MediaCodecAdapter.Factory,
 private val synchronous:MediaCodecAdapter.Factory=SynchronousMediaCodecAdapter.Factory(),
 private val report:(String,Map<String,Any>)->Unit={_,_->}
):MediaCodecAdapter.Factory {
 override fun createAdapter(configuration:MediaCodecAdapter.Configuration):MediaCodecAdapter {
  val eligible=Build.VERSION.SDK_INT>=31 && configuration.codecInfo.hardwareAccelerated &&
   !configuration.codecInfo.softwareOnly && !configuration.codecInfo.secure &&
   configuration.crypto==null && configuration.format.drmInitData==null &&
   configuration.surface!=null && HevcHdrRecovery.knownMain10Within4K(configuration.format)
  // Snapshot before the first adapter can consume CSD buffers or change its configuration.
  val original=if(eligible)copyFormat(configuration.mediaFormat)else null
  try {return standard.createAdapter(configuration)}catch(first:Exception){
   if(original==null || (first !is IOException && first !is RuntimeException))throw first
   // Both Media3 factories release a partially created codec when initialization fails.
   // Drop scheduling/allocation hints, never MIME, dimensions, CSD or HDR/color metadata.
   for(key in optionalHints)original.removeKey(key)
   val retry=MediaCodecAdapter.Configuration.createForVideoDecoding(
    configuration.codecInfo,original,configuration.format,configuration.surface,configuration.crypto)
   fun facts(error:Throwable?=null)=linkedMapOf<String,Any>(
    "codecName" to configuration.codecInfo.name,"mimeType" to "video/hevc",
    "codecMode" to "synchronous-minimal").apply {if(error!=null)putAll(CodecInitializationFacts.read(error))}
   report("hevcHardwareInitializationRetry",facts(first))
   try {
    val adapter=synchronous.createAdapter(retry)
    report("hevcHardwareInitializationSucceeded",facts())
    return adapter
   }catch(second:Exception){
    report("hevcHardwareInitializationFailed",facts(second))
    // Keep both failures for Media3's existing bounded next-decoder recovery.
    if(second!==first)second.addSuppressed(first)
    throw second
   }
  }
 }
 companion object {
  private val optionalHints=listOf(MediaFormat.KEY_MAX_WIDTH,MediaFormat.KEY_MAX_HEIGHT,
   MediaFormat.KEY_MAX_INPUT_SIZE,MediaFormat.KEY_OPERATING_RATE,MediaFormat.KEY_PRIORITY)
  private fun copyFormat(source:MediaFormat):MediaFormat {
   val result=MediaFormat(source)
   for(key in source.keys.filter {it.startsWith("csd-")}){
    source.getByteBuffer(key)?.let {result.setByteBuffer(key,it.duplicate())}
   }
   return result
  }
 }
}
