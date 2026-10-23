package dev.together.poc

import org.junit.Assert.assertEquals
import org.junit.Test

class LocalMovieRestorePolicyTest {
 private val room="two-people-room"
 private val first="http://usb-media.example.test:49185/media/usb-a/Film.mkv?expires=100&sig=old"
 private val renewed="http://usb-media.example.test:49185/media/usb-a/Film.mkv?expires=200&sig=new"

 @Test fun preservesLocalDocumentAcrossSignedUrlRefresh() {
  assertEquals(LocalMovieRestorePolicy.Action.RESTORE,
   LocalMovieRestorePolicy.decide(room,first,room,renewed,true))
 }
 @Test fun expiredSafGrantRequiresReselectInsteadOfHttpFallback() {
  assertEquals(LocalMovieRestorePolicy.Action.RESELECT,
   LocalMovieRestorePolicy.decide(room,first,room,renewed,false))
 }
 @Test fun differentMovieMustNotReusePreviousDocument() {
  assertEquals(LocalMovieRestorePolicy.Action.MOVIE_CHANGED,
   LocalMovieRestorePolicy.decide(room,first,room,"http://usb-media.example.test:49185/media/usb-a/Other.mkv",true))
 }
 @Test fun anotherRoomMustNotInheritSource() {
  assertEquals(LocalMovieRestorePolicy.Action.IGNORE,
   LocalMovieRestorePolicy.decide(room,first,"another-room",first,true))
 }
 @Test fun exactBaiduReferenceCanResumeLocalDocument() {
  val reference="baidu-file://fingerprint?size=123"
  assertEquals(LocalMovieRestorePolicy.Action.RESTORE,
   LocalMovieRestorePolicy.decide(room,reference,room,reference,true))
 }
}
