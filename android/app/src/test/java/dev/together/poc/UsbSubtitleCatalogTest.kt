package dev.together.poc

import org.junit.Assert.*
import org.junit.Test

class UsbSubtitleCatalogTest {
 private val video = "http://usb-media.example:49185/media/usb-123/Example.Movie.2020.mkv?expires=1800000000&sig=movie-signature"
 @Test fun unsignedVideoUsesLocalSameFolderSidecars() {
  val movie = "http://usb-media.example:49185/usb-files/高清/Example.Movie.mkv"
  assertEquals("$movie?subtitles=1", UsbSubtitleCatalog.manifestUrl(movie))
  val json = """{"subtitles":[
   {"name":"Example.Movie.zh.srt","url":"/usb-files/%E9%AB%98%E6%B8%85/Example.Movie.zh.srt"},
   {"name":"wrong.srt","url":"/usb-files/elsewhere/wrong.srt"},
   {"name":"evil.srt","url":"http://attacker.example/usb-files/高清/evil.srt"},
   {"name":"bad.exe","url":"/usb-files/高清/bad.exe"}
  ]}"""
  val found=UsbSubtitleCatalog.parse(movie,json)
  assertEquals(listOf("Example.Movie.zh.srt"),found.map {it.name})
 }

 @Test fun signedVideoHasCatalogRepresentation() {
  assertEquals(
   "http://usb-media.example:49185/media/usb-123/Example.Movie.2020.mkv?expires=1800000000&sig=movie-signature&subtitles=1",
   UsbSubtitleCatalog.manifestUrl(video)
  )
  assertNull(UsbSubtitleCatalog.manifestUrl("file:///storage/Movie.mkv"))
  assertNull(UsbSubtitleCatalog.manifestUrl("https://example.com/movie.mkv"))
 }

 @Test fun signedSidecarsAreSelectableAndOtherOriginsRejected() {
  val json = """{"subtitles":[
    {"name":"Example.Movie.2020.简体.srt","url":"/media/usb-123/Example.Movie.2020.%E7%AE%80%E4%BD%93.srt?expires=1800000000&sig=s1"},
    {"name":"Example.Movie.2020.繁体.ass","url":"/media/usb-123/Example.Movie.2020.ass?expires=1800000000&sig=s2"},
    {"name":"evil.srt","url":"https://attacker.example/evil.srt?expires=1800000000&sig=x"},
    {"name":"wrong.srt","url":"/media/usb-OTHER/wrong.srt?expires=1800000000&sig=x"},
    {"name":"wrong.zip","url":"/media/usb-123/wrong.zip?expires=1800000000&sig=x"},
    {"name":"unsigned.srt","url":"/media/usb-123/unsigned.srt"},
    {"name":"../traversal.srt","url":"/media/usb-123/x.srt?expires=1800000000&sig=x"}
  ]}"""
  val subtitles = UsbSubtitleCatalog.parse(video, json)
  assertEquals(2, subtitles.size)
  assertEquals("Example.Movie.2020.简体.srt", subtitles[0].name)
  assertEquals("Example.Movie.2020.繁体.ass", subtitles[1].name)
 }

 @Test fun malformedCatalogDoesNotProduceEntries() {
  assertTrue(UsbSubtitleCatalog.parse(video, """{"subtitles": []}""").isEmpty())
  assertTrue(UsbSubtitleCatalog.parse(video, """{"foo":1}""").isEmpty())
 }
}
