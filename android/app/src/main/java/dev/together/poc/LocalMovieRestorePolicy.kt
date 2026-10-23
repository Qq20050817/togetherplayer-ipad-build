package dev.together.poc

// Restore a previously selected SAF document only for the same room and movie.
// A missing persisted read grant must require a new picker, never silently use HTTP.
internal object LocalMovieRestorePolicy {
 enum class Action { IGNORE, MOVIE_CHANGED, RESELECT, RESTORE }
 fun decide(storedRoom:String,storedMedia:String,currentRoom:String,currentMedia:String,hasReadGrant:Boolean):Action {
  if(storedRoom.isBlank() || storedRoom!=currentRoom || storedMedia.isBlank())return Action.IGNORE
  if(!RoomMediaIdentity.sameHttpMovie(storedMedia,currentMedia))return Action.MOVIE_CHANGED
  return if(hasReadGrant)Action.RESTORE else Action.RESELECT
 }
}
