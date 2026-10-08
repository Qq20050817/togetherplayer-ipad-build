package dev.together.poc

import android.content.Context
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.mediacodec.MediaCodecSelector

object PlaybackRenderers {
 fun create(context:Context):DefaultRenderersFactory = DefaultRenderersFactory(context)
  .setEnableDecoderFallback(true)
  .setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_ON)
  .setMediaCodecSelector(MediaCodecSelector {mime,secure,tunneling->
   // Decode DTS/TrueHD with FFmpeg. Keep native DD+/AAC, preserving the
   // platform's spatial-audio path where supported. Video uses codec fallback.
   if(mime in listOf("audio/vnd.dts","audio/vnd.dts.hd","audio/true-hd"))emptyList()
   else MediaCodecSelector.DEFAULT.getDecoderInfos(mime,secure,tunneling)
  })
}
