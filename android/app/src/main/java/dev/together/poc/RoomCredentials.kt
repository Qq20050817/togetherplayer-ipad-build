package dev.together.poc

import org.json.JSONObject

object RoomCredentials {
 fun parse(text: String): JSONObject {
  val credentials=JSONObject(text)
  for (key in listOf("roomId","userId","token")) {
   require(credentials.getString(key).isNotBlank()) { "Missing $key" }
  }
  return credentials
 }
}
