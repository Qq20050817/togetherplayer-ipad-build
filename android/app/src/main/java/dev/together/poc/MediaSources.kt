package dev.together.poc
import java.net.URI
class HlsSource: MediaSourceAdapter {override fun resolve(url: String)=HTTPSource().resolve(url)}
class WebDAVSource: MediaSourceAdapter {override fun resolve(url: String)=HTTPSource().resolve(url.replaceFirst("webdavs://","https://").replaceFirst("webdav://","http://"))}
object MediaSources {
 fun resolve(value: String): String {val url=WebDAVSource().resolve(value.trim());val u=URI(url);require(!u.host.isNullOrBlank() && u.scheme in listOf("http","https"));return url}
 fun canShare(value: String): Boolean=try {val u=URI(resolve(value));u.userInfo==null && (u.rawQuery ?: "").split('&').none {java.net.URLDecoder.decode(it.substringBefore('='),"UTF-8").lowercase() in listOf("access_token","refresh_token","cookie","password")}}catch(e: Exception){false}
}
