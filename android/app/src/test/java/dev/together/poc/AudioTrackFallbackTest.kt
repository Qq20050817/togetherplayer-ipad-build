package dev.together.poc
import org.junit.Test
import org.junit.Assert.*

class AudioTrackFallbackTest {
 @Test fun englishDtsFallsBackToEnglishAc3WithoutSwitchingLanguage(){
  val tracks=listOf(
   AudioTrackFallback.Option("audio/vnd.dts.hd","eng",true),
   AudioTrackFallback.Option("audio/ac3","fre",true),
   AudioTrackFallback.Option("audio/ac3","eng",true))
  assertEquals(2,AudioTrackFallback.select("audio/vnd.dts.hd","eng",tracks))
 }
 @Test fun cannotAutomaticallySelectWrongLanguageOrUnsupportedTrack(){
  val tracks=listOf(AudioTrackFallback.Option("audio/ac3","fre",true),AudioTrackFallback.Option("audio/ac3","eng",false))
  assertNull(AudioTrackFallback.select("audio/vnd.dts","eng",tracks))
  assertNull(AudioTrackFallback.select("audio/vnd.dts","und",tracks))
  assertNull(AudioTrackFallback.select("video/hevc","eng",tracks))
 }
}
