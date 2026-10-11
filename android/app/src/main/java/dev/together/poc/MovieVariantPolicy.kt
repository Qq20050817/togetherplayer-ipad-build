package dev.together.poc
import kotlin.math.abs
/** A transcode cannot pass byte identity. Require explicit confirmation and runtime duration. */
object MovieVariantPolicy {
 enum class DurationCheck { WAITING, COMPATIBLE, DIFFERENT }
 fun duration(localMs:Double,offsetMs:Double,roomMs:Double):DurationCheck {
  if(!localMs.isFinite() || !offsetMs.isFinite() || !roomMs.isFinite() || localMs<=0 || roomMs<=0 || localMs-offsetMs<=0)return DurationCheck.WAITING
  return if(abs(localMs-offsetMs-roomMs)<=5000)DurationCheck.COMPATIBLE else DurationCheck.DIFFERENT
 }
}
