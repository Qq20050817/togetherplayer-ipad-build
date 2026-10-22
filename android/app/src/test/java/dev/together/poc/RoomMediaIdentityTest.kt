package dev.together.poc

import org.junit.Assert.*
import org.junit.Test

class RoomMediaIdentityTest {
 @Test fun refreshedRouterSignatureStillTargetsSameMovie() {
  val first="http://usb-media.example.test:49185/media/usb-a/Film.2019.mkv?expires=100&sig=old"
  val second="http://usb-media.example.test:49185/media/usb-a/Film.2019.mkv?expires=200&sig=new"
  assertTrue(RoomMediaIdentity.sameHttpMovie(first,second))
  assertTrue(RoomMediaIdentity.sameHttpMovie(second,first))
 }
 @Test fun neverReusesLocalFileForAnotherMovie() {
  val old="http://usb-media.example.test:49185/media/usb-a/Film.2019.mkv?expires=100"
  assertFalse(RoomMediaIdentity.sameHttpMovie(old,"http://usb-media.example.test:49185/media/usb-a/Other.2019.mkv"))
  assertFalse(RoomMediaIdentity.sameHttpMovie(old,"http://another-host.example.test:49185/media/usb-a/Film.2019.mkv"))
  assertFalse(RoomMediaIdentity.sameHttpMovie(old,"http://usb-media.example.test:49186/media/usb-a/Film.2019.mkv"))
 }
 @Test fun rejectsUnrelatedOrInvalidSources() {
  assertTrue(RoomMediaIdentity.sameHttpMovie("content://document/123","content://document/123"))
  assertFalse(RoomMediaIdentity.sameHttpMovie("content://document/123","content://document/456"))
  assertFalse(RoomMediaIdentity.sameHttpMovie("",""))
  assertFalse(RoomMediaIdentity.sameHttpMovie("%%%","http://usb-media.example.test/media/a.mkv"))
  assertFalse(RoomMediaIdentity.sameHttpMovie("http://usb-media.example.test/","http://usb-media.example.test/?token=a"))
 }
}
