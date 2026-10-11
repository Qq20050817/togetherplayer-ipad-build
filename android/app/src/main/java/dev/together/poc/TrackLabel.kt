package dev.together.poc

import java.util.Locale

object TrackLabel {
 fun label(title:String?,language:String?,mime:String?,channels:Int=-1,ordinal:Int,subtitle:Boolean):String {
  val code=(language ?: "").lowercase().replace('_','-')
  val aliases=mapOf("eng" to "en","chi" to "zh","zho" to "zh","jpn" to "ja","kor" to "ko","fre" to "fr","fra" to "fr")
  val base=aliases[code.substringBefore('-')] ?: code.substringBefore('-')
  val translated=if(base.isNotEmpty() && base!="und")Locale.forLanguageTag(base).getDisplayLanguage(Locale.SIMPLIFIED_CHINESE) else "未标明语言"
  val raw=title?.trim().orEmpty();val hint="$raw $code".lowercase()
  val simplified=listOf("hans","simplified","chs","简体","簡體","zh-cn","zh-sg").any {hint.contains(it)}
  val traditional=listOf("hant","traditional","cht","繁体","繁體","zh-tw","zh-hk","zh-mo").any {hint.contains(it)}
  val name=when {simplified && !traditional->"简体中文";traditional && !simplified->"繁体中文";subtitle && base=="zh"->"中文（简繁未标明）";else->translated}
  val detail=when(mime){"audio/vnd.dts"->"DTS";"audio/vnd.dts.hd"->"DTS-HD";"audio/vnd.dts.hd;profile=lbr"->"DTS Express";"audio/true-hd"->"Dolby TrueHD";"audio/eac3-joc"->"Dolby Digital Plus Atmos";"audio/eac3"->"Dolby Digital Plus";"audio/ac3"->"Dolby Digital";"audio/mp4a-latm"->"AAC";"audio/flac"->"FLAC";"audio/raw"->"PCM";"application/pgs"->"PGS 图像字幕";"application/x-subrip"->"SRT";"text/vtt"->"WebVTT";"text/x-ssa"->"ASS / SSA";else->mime?.substringAfter('/')?.uppercase().orEmpty()}
  val parts=mutableListOf(name)
  if(raw.isNotEmpty() && !raw.equals(language,true) && !raw.equals("English",true) && !raw.equals("Chinese",true))parts.add(raw.replace("SDH","听障字幕",true).replace("Forced","强制字幕",true))
  if(detail.isNotEmpty())parts.add(detail)
  if(!subtitle && channels>0)parts.add(when(channels){1->"单声道";2->"立体声 2.0";6->"6声道（通常 5.1）";8->"8声道（通常 7.1）";else->"${channels}声道"})
  parts.add("${if(subtitle) "字幕" else "音轨"} $ordinal")
  return parts.joinToString(" · ")
 }
}
