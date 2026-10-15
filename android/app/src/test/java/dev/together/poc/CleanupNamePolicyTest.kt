package dev.together.poc
import org.junit.Assert.*
import org.junit.Test
class CleanupNamePolicyTest {
 @Test fun sameFilmLanguageTracksMatch() {
  for(name in listOf("Movie.srt","Movie.zh-Hans.srt","Movie.en.forced.ass","Movie.chs&eng.srt","Movie.简体中文.sup"))assertTrue(name,CleanupNamePolicy.associatedSubtitle(name,"Movie.mkv"))
 }
 @Test fun otherPartsAndUnrelatedFilesNeverMatch() {
  for(name in listOf("Movie.part2.srt","Movie2.srt","Movie.srt.backup","Movie.mkv","Other.zh.srt","Movie.commentary.srt"))assertFalse(name,CleanupNamePolicy.associatedSubtitle(name,"Movie.mkv"))
 }
 @Test fun unicodeNamesAndCapitalizedExtensionsMatch() {
  assertTrue(CleanupNamePolicy.associatedSubtitle("生化危机.繁体.SRT","生化危机.MKV"))
  assertFalse(CleanupNamePolicy.associatedSubtitle("生化危机2.SRT","生化危机.MKV"))
 }
}
