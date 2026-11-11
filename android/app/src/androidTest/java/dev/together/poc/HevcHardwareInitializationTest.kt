package dev.together.poc

import android.graphics.SurfaceTexture
import android.media.MediaFormat
import android.view.Surface
import androidx.media3.common.C
import androidx.media3.common.ColorInfo
import androidx.media3.common.Format
import androidx.media3.exoplayer.mediacodec.MediaCodecAdapter
import androidx.media3.exoplayer.mediacodec.MediaCodecInfo
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.lang.reflect.Proxy
import java.nio.ByteBuffer
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class HevcHardwareInitializationTest {
 private fun movie()=Format.Builder().setSampleMimeType("video/hevc").setCodecs("hvc1.2.4.L150.90")
  .setWidth(3840).setHeight(1600).setFrameRate(24f).setInitializationData(listOf(byteArrayOf(1,2,3,4)))
  .setColorInfo(ColorInfo.Builder().setColorSpace(C.COLOR_SPACE_BT2020)
   .setColorTransfer(C.COLOR_TRANSFER_ST2084).setHdrStaticInfo(byteArrayOf(9,8,7)).build()).build()
 private val adapter get()=Proxy.newProxyInstance(MediaCodecAdapter::class.java.classLoader,
  arrayOf(MediaCodecAdapter::class.java)){_,_,_->null} as MediaCodecAdapter
 private inline fun withSurface(block:(Surface)->Unit){
  val texture=SurfaceTexture(false);val surface=Surface(texture)
  try {block(surface)}finally {surface.release();texture.release()}
 }
 private fun config(surface:Surface?,format:Format=movie(),hardware:Boolean=true,secure:Boolean=false):MediaCodecAdapter.Configuration {
  val codec=MediaCodecInfo.newInstance("test.vendor.hevc","video/hevc","video/hevc",null,hardware,!hardware,true,false,secure)
  val media=MediaFormat.createVideoFormat(format.sampleMimeType!!,format.width,format.height)
  media.setByteBuffer("csd-0",ByteBuffer.wrap(byteArrayOf(1,2,3,4)))
  media.setInteger(MediaFormat.KEY_COLOR_STANDARD,6);media.setInteger(MediaFormat.KEY_COLOR_TRANSFER,6)
  media.setByteBuffer(MediaFormat.KEY_HDR_STATIC_INFO,ByteBuffer.wrap(byteArrayOf(9,8,7)))
  media.setInteger(MediaFormat.KEY_MAX_WIDTH,4096);media.setInteger(MediaFormat.KEY_MAX_HEIGHT,2160)
  media.setInteger(MediaFormat.KEY_MAX_INPUT_SIZE,4194304);media.setFloat(MediaFormat.KEY_OPERATING_RATE,48f)
  media.setInteger(MediaFormat.KEY_PRIORITY,0)
  return MediaCodecAdapter.Configuration.createForVideoDecoding(codec,media,format,surface,null)
 }
 @Test fun successfulDefaultInitializationIsNeverReconfigured()=withSurface {surface->
  val c=config(surface);val expected=adapter;var firstCalls=0;var retryCalls=0
  val factory=HevcHardwareCodecAdapterFactory(
   MediaCodecAdapter.Factory {seen->firstCalls++;assertSame(c,seen);expected},
   MediaCodecAdapter.Factory {retryCalls++;throw AssertionError("Unnecessary retry")})
  assertSame(expected,factory.createAdapter(c));assertEquals(1,firstCalls);assertEquals(0,retryCalls)
 }
 @Test fun failedHardwareRetriesSameBitstreamHdrAndSurfaceWithoutSchedulingHints()=withSurface {surface->
  val c=config(surface);val expected=adapter;val events=mutableListOf<String>();var retries=0
  val factory=HevcHardwareCodecAdapterFactory(
   MediaCodecAdapter.Factory {seen->
    seen.mediaFormat.getByteBuffer("csd-0")!!.position(2)
    throw IllegalArgumentException("private-source?token=never-export")
   },MediaCodecAdapter.Factory {seen->
    retries++;assertSame(c.codecInfo,seen.codecInfo);assertSame(c.format,seen.format);assertSame(surface,seen.surface)
    assertNull(seen.crypto);assertNotSame(c.mediaFormat,seen.mediaFormat)
    assertEquals("video/hevc",seen.mediaFormat.getString(MediaFormat.KEY_MIME))
    assertEquals(3840,seen.mediaFormat.getInteger(MediaFormat.KEY_WIDTH));assertEquals(1600,seen.mediaFormat.getInteger(MediaFormat.KEY_HEIGHT))
    assertEquals(6,seen.mediaFormat.getInteger(MediaFormat.KEY_COLOR_TRANSFER));assertEquals(6,seen.mediaFormat.getInteger(MediaFormat.KEY_COLOR_STANDARD))
    assertEquals(ByteBuffer.wrap(byteArrayOf(9,8,7)),seen.mediaFormat.getByteBuffer(MediaFormat.KEY_HDR_STATIC_INFO))
    assertEquals(ByteBuffer.wrap(byteArrayOf(1,2,3,4)),seen.mediaFormat.getByteBuffer("csd-0"))
    for(key in listOf(MediaFormat.KEY_MAX_WIDTH,MediaFormat.KEY_MAX_HEIGHT,MediaFormat.KEY_MAX_INPUT_SIZE,MediaFormat.KEY_OPERATING_RATE,MediaFormat.KEY_PRIORITY)){
     assertFalse(seen.mediaFormat.containsKey(key));assertTrue(c.mediaFormat.containsKey(key))
    }
    expected
   }){event,facts->events.add(event);assertFalse(facts.toString().contains("never-export"))}
  assertSame(expected,factory.createAdapter(c));assertEquals(1,retries)
  assertEquals(listOf("hevcHardwareInitializationRetry","hevcHardwareInitializationSucceeded"),events)
 }
 @Test fun secondFailureReturnsToExistingDecoderRecoveryWithoutAnInnerLoop()=withSurface {surface->
  val first=IllegalStateException("first");val second=java.io.IOException("second");var retries=0
  val factory=HevcHardwareCodecAdapterFactory(MediaCodecAdapter.Factory {throw first},MediaCodecAdapter.Factory {retries++;throw second})
  try {factory.createAdapter(config(surface));fail("Must propagate the second initialization failure")}
  catch(error:java.io.IOException){assertSame(second,error);assertArrayEquals(arrayOf(first),error.suppressed)}
  assertEquals(1,retries)
 }
 @Test fun unrelatedFormatsSoftwareSecureAndMissingSurfaceDoNotGetHardwareRetry()=withSurface {surface->
  val original=IllegalArgumentException("default rejected configuration");var retries=0
  val factory=HevcHardwareCodecAdapterFactory(MediaCodecAdapter.Factory {throw original},
   MediaCodecAdapter.Factory {retries++;throw AssertionError("Ineligible retry")})
  val f=movie()
  val cases=listOf(config(surface,hardware=false),config(surface,secure=true),config(null),
   config(surface,f.buildUpon().setCodecs(null).build()),
   config(surface,f.buildUpon().setCodecs("hvc1.1.4.L150.90").build()),
   config(surface,f.buildUpon().setSampleMimeType("video/avc").setCodecs("avc1.640028").build()),
   config(surface,f.buildUpon().setSampleMimeType("audio/eac3").build()),
   config(surface,f.buildUpon().setWidth(7680).build()))
  for(c in cases){try {factory.createAdapter(c);fail("Must preserve the original failure")}
   catch(error:IllegalArgumentException){assertSame(original,error)}}
  assertEquals(0,retries)
 }
 @Test fun diagnosticFactsNeverCopyExceptionMessagesOrAddresses(){
  val error=IllegalStateException("http://private.invalid/movie?token=SECRET",java.io.IOException("SECRET"))
  val facts=CodecInitializationFacts.read(error)
  assertEquals("IOException",facts["codecFailureClass"])
  assertFalse(facts.toString().contains("SECRET"));assertFalse(facts.toString().contains("private.invalid"))
 }
}
