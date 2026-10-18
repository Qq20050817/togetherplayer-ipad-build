package dev.together.poc

import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import org.json.JSONObject

/**
 * Finds signed, same-film USB subtitle sidecars through the opt-in read-only
 * subtitles=1 representation of an already-authorized /media/... video URL.
 * The router returns separately signed URLs for the discovered files.
 */
data class UsbSubtitleOption(val name: String, val url: String)

object UsbSubtitleCatalog {
 const val MAX_MANIFEST_BYTES = 32 * 1024
 private val TEXT_EXTENSIONS = setOf("srt", "vtt", "ass", "ssa")

 fun manifestUrl(videoUrl: String): String? {
  val url = videoUrl.toHttpUrlOrNull() ?: return null
  if (!authorizedVideoPath(url) ||
      url.queryParameter("expires").isNullOrBlank() ||
      url.queryParameter("sig").isNullOrBlank() ||
      url.queryParameter("subtitles") != null) return null
  return url.newBuilder().addQueryParameter("subtitles", "1").build().toString()
 }

 private fun authorizedVideoPath(url: HttpUrl): Boolean =
  url.encodedPathSegments.size == 3 &&
  url.encodedPathSegments[0] == "media" &&
  url.encodedPathSegments[1].isNotBlank() &&
  url.encodedPathSegments[2].isNotBlank()

 fun parse(videoUrl: String, json: String): List<UsbSubtitleOption> {
  val video = videoUrl.toHttpUrlOrNull() ?: return emptyList()
  if (!authorizedVideoPath(video)) return emptyList()
  val list = JSONObject(json).optJSONArray("subtitles") ?: return emptyList()
  val found = LinkedHashMap<String, UsbSubtitleOption>()
  for (i in 0 until minOf(list.length(), 48)) {
   val record = list.optJSONObject(i) ?: continue
   val name = record.optString("name").trim()
   val extension = name.substringAfterLast('.', "").lowercase()
   if (name.isBlank() || '/' in name || '\\' in name ||
       name.length > 240 || extension !in TEXT_EXTENSIONS) continue
   val raw = record.optString("url")
   // OkHttp's resolve accepts a path supplied by this router, and never
   // accepts redirects/URLs on an unrelated authority as subtitle entries.
   val candidate = video.resolve(raw) ?: continue
   if (candidate.scheme != video.scheme || candidate.host != video.host ||
       candidate.port != video.port ||
       candidate.encodedPathSegments.size != 3 ||
       candidate.encodedPathSegments[0] != "media" ||
       candidate.encodedPathSegments[1] != video.encodedPathSegments[1] ||
       candidate.queryParameter("expires").isNullOrBlank() ||
       candidate.queryParameter("sig").isNullOrBlank()) continue
   found.putIfAbsent(candidate.toString(), UsbSubtitleOption(name, candidate.toString()))
   if (found.size >= 24) break
  }
  return found.values.toList()
 }
}
