package dev.together.poc

import java.net.URI
import java.util.Locale

/**
 * HTTP query parameters often carry temporary signatures that change after a router restart.
 * Match the immutable origin and escaped resource path, never the display title alone.
 */
internal object RoomMediaIdentity {
 fun sameHttpMovie(previous:String,next:String):Boolean {
  if(previous==next)return previous.isNotBlank()
  val old=runCatching { URI(previous) }.getOrNull() ?: return false
  val updated=runCatching { URI(next) }.getOrNull() ?: return false
  val oldScheme=old.scheme?.lowercase(Locale.ROOT) ?: return false
  val newScheme=updated.scheme?.lowercase(Locale.ROOT) ?: return false
  if(oldScheme !in setOf("http","https") || newScheme !in setOf("http","https"))return false
  val oldHost=old.host?.lowercase(Locale.ROOT) ?: return false
  val newHost=updated.host?.lowercase(Locale.ROOT) ?: return false
  val oldPath=old.rawPath?.takeIf { it.isNotEmpty() && it!="/" } ?: return false
  val newPath=updated.rawPath?.takeIf { it.isNotEmpty() && it!="/" } ?: return false
  return oldHost==newHost && old.port==updated.port && oldPath==newPath
 }
}
