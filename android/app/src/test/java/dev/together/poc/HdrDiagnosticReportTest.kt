package dev.together.poc

import androidx.media3.common.C
import androidx.media3.common.ColorInfo
import androidx.media3.common.Format
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class HdrDiagnosticReportTest {
 @Test fun localReportKeepsHdrAndDecoderFactsButNeverExportsMediaUrlsOrTokens(){
  val format=Format.Builder().setSampleMimeType("video/hevc")
   .setCodecs("hvc1.2.4.L150.90").setWidth(3840).setHeight(2160)
   .setColorInfo(ColorInfo.Builder().setColorTransfer(C.COLOR_TRANSFER_ST2084)
    .setColorSpace(C.COLOR_SPACE_BT2020).build()).build()
  val events=JSONArray().put(JSONObject().put("event","independentPlaybackStats")
   .put("elapsedMs",12000).put("mediaUrl","http://private.example/movie?token=SECRET")
   .put("details",JSONObject().put("decodedVideo",200).put("displayedVideo",100)
    .put("authorization","Bearer SECRET").put("codecName","c2.qti.hevc.decoder")))
  val candidates=JSONArray().put(JSONObject().put("name","c2.qti.hevc.decoder")
   .put("hardware",true).put("file","private.mkv"))
  val report=HdrDiagnosticReport.create("0.6.60.19","Xiaomi","Pad 7",35,format,
   "c2.qti.hevc.decoder","c2.android.aac.decoder",true,true,3,42420L,"http",
   mapOf("decodedVideo" to 200,"hdrHardwareSurfaceRequested" to true,
    "mediaUrl" to "http://private.example/movie?token=SECRET"),
   events,candidates)
  val serialized=report.toString()
  assertEquals(C.COLOR_TRANSFER_ST2084,report.getJSONObject("videoFormat").getInt("colorTransfer"))
  assertTrue(report.getJSONObject("vlcOutput").getBoolean("hdrHardwareSurfaceRequested"))
  assertEquals(100,report.getJSONArray("recentEvents").getJSONObject(0).getJSONObject("details").getInt("displayedVideo"))
  assertFalse(serialized.contains("SECRET"));assertFalse(serialized.contains("private.example"))
  assertFalse(serialized.contains("private.mkv"));assertFalse(serialized.contains("mediaUrl"))
  assertFalse(serialized.contains("authorization"))
 }
}
