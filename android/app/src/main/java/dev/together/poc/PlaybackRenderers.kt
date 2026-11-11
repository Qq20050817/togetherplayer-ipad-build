package dev.together.poc

import android.content.Context
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.mediacodec.MediaCodecSelector
import androidx.media3.exoplayer.mediacodec.MediaCodecAdapter

object PlaybackRenderers {
 fun create(context:Context,recovery:VideoDecoderRecovery=VideoDecoderRecovery(),
  report:(String,Map<String,Any>)->Unit={_,_->}):DefaultRenderersFactory = object:DefaultRenderersFactory(context){
   private var recoveryFactory:MediaCodecAdapter.Factory?=null
   override fun getCodecAdapterFactory():MediaCodecAdapter.Factory = recoveryFactory ?:
    HevcHardwareCodecAdapterFactory(super.getCodecAdapterFactory(),report=report).also {recoveryFactory=it}
  }
  .setEnableDecoderFallback(true)
  .setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_ON)
  .setMediaCodecSelector(MediaCodecSelector {mime,secure,tunneling->
   // Decode DTS/TrueHD with FFmpeg. Keep native DD+/AAC, preserving the
   // platform's spatial-audio path where supported. Video uses codec fallback.
   if(mime in listOf("audio/vnd.dts","audio/vnd.dts.hd","audio/true-hd"))emptyList()
   else MediaCodecSelector.DEFAULT.getDecoderInfos(mime,secure,tunneling).let {codecs->
    val offered=recovery.offeredToRenderer(mime,codecs.map {it.name}).toSet()
    codecs.filter {it.name in offered}
   }
  })
}
