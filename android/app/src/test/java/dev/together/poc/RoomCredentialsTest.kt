package dev.together.poc

import org.junit.Test
import org.junit.Assert.*

class RoomCredentialsTest {
 @Test fun validCredentialsPreserveIdentity() {
  val c=RoomCredentials.parse("""{"roomId":"r","userId":"u","token":"test-token"}""")
  assertEquals("r",c.getString("roomId"));assertEquals("u",c.getString("userId"))
 }
 @Test fun malformedOrIncompleteCredentialsCannotReplaceSession() {
  for (body in listOf("not json","{}","""{"roomId":"r","userId":"u","token":""}""","""{"roomId":"r","userId":"u","token":null}""")) {
   try {RoomCredentials.parse(body);fail("Invalid response accepted")} catch (_: Exception) {}
  }
 }
}
