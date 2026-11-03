package dev.together.poc

/** Device-only routing. Room messages never choose a peer's actual source. */
internal object LocalSourcePriority {
 enum class Action { REQUESTED, LOCAL, RESELECT }
 fun decide(requested:String,roomId:String,roomMedia:String,boundRoom:String,boundMedia:String,localUri:String,permissionMissing:Boolean):Action {
  if(roomId.isBlank() || boundRoom!=roomId || !RoomMediaIdentity.sameHttpMovie(boundMedia,roomMedia))return Action.REQUESTED
  val roomRead=RoomMediaIdentity.sameHttpMovie(requested,roomMedia)
  if(permissionMissing && roomRead)return Action.RESELECT
  return if(localUri.isNotBlank() && roomRead)Action.LOCAL else Action.REQUESTED
 }
}
