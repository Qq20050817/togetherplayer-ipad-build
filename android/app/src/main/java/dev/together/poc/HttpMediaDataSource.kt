package dev.together.poc
import androidx.media3.datasource.DefaultHttpDataSource

/** Reject clearly structured error pages before a video extractor mislabels them. */
internal object HttpMediaDataSource {
 fun acceptsContentType(value:String?):Boolean {
  val mime=value?.substringBefore(';')?.trim()?.lowercase(java.util.Locale.ROOT).orEmpty()
  return mime !in setOf("text/html","application/xhtml+xml","application/json","application/problem+json")
 }
 fun factory(userAgent:String?=null)=DefaultHttpDataSource.Factory()
  .setUserAgent(userAgent).setContentTypePredicate{acceptsContentType(it)}
}
