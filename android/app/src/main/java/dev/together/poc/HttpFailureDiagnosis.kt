package dev.together.poc
import androidx.media3.common.PlaybackException as P

/** Code-only, bounded diagnosis. No throwable messages, URLs or paths. */
internal object HttpFailureDiagnosis {
 data class Result(val category:String,val message:String,val retryable:Boolean)
 fun classify(code:Int,status:Int?,causes:Set<String> = emptySet()):Result = when {
  status==401 || status==403->Result("HTTP_AUTH","片源访问授权失效，请刷新片源",false)
  status==404 || status==410->Result("FILE_UNAVAILABLE","片源不存在或已不可访问",false)
  status==416 || code==P.ERROR_CODE_IO_READ_POSITION_OUT_OF_RANGE->Result("RANGE","HTTP读取范围与文件长度不一致",true)
  status==429->Result("HTTP_THROTTLED","片源服务暂时限制请求",true)
  status in setOf(500,502,503,504)->Result("HTTP_SERVER","片源服务暂时不可用",true)
  status!=null->Result("HTTP_STATUS","HTTP状态异常（$status）",false)
  code==P.ERROR_CODE_IO_NETWORK_CONNECTION_TIMEOUT || "SocketTimeoutException" in causes->Result("TIMEOUT","读取片源超时",true)
  "EOFException" in causes->Result("INCOMPLETE","片源响应数据不完整",true)
  code==P.ERROR_CODE_IO_NETWORK_CONNECTION_FAILED || "SocketException" in causes->Result("CONNECTION","片源连接中断",true)
  code==P.ERROR_CODE_IO_INVALID_HTTP_CONTENT_TYPE->Result("UNEXPECTED_CONTENT","服务端返回了非视频内容",false)
  code==P.ERROR_CODE_IO_FILE_NOT_FOUND || code==P.ERROR_CODE_IO_NO_PERMISSION->Result("LOCAL_UNAVAILABLE","本地文件不存在或读取权限失效，请重新选择或切回U盘",false)
  code==P.ERROR_CODE_PARSING_CONTAINER_MALFORMED || code==P.ERROR_CODE_PARSING_CONTAINER_UNSUPPORTED->Result("CONTAINER","影片封装无法解析，建议检查完整性或尝试无损重封装",false)
  code==P.ERROR_CODE_DECODING_FAILED->Result("DECODER","视频或音频轨道解码失败，可能存在格式或设备兼容问题",false)
  else->Result("OTHER","播放读取失败，请查看错误码与编码信息",false)
 }
}
