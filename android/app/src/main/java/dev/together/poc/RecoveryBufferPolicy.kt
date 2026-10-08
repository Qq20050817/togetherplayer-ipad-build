package dev.together.poc

object RecoveryBufferPolicy {
 fun ready(prepared: Boolean,bufferedMs: Long,positionMs: Long,durationMs: Long,recovering: Boolean): Boolean {
  if(!prepared)return false
  if(!recovering)return true
  val remaining=if(durationMs>0)(durationMs-positionMs).coerceAtLeast(0) else 12000L
  val required=minOf(12000L,remaining)
  return bufferedMs.coerceAtLeast(0)>= (required-50).coerceAtLeast(0)
 }
}
