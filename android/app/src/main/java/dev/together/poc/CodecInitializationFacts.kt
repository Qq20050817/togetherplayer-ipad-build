package dev.together.poc

import android.media.MediaCodec

/** Export fixed codec error facts, never exception messages or source addresses. */
internal object CodecInitializationFacts {
 fun read(error:Throwable):Map<String,Any> {
  val result=linkedMapOf<String,Any>()
  val seen=java.util.Collections.newSetFromMap(java.util.IdentityHashMap<Throwable,Boolean>())
  var cause:Throwable?=error
  repeat(12){
   val current=cause ?: return result
   if(!seen.add(current))return result
   result["codecFailureClass"]=current.javaClass.simpleName
   if(current is MediaCodec.CodecException){
    result["codecErrorCode"]=current.errorCode
    result["codecRecoverable"]=current.isRecoverable
    result["codecTransient"]=current.isTransient
    current.diagnosticInfo?.takeIf {it.matches(Regex("[A-Za-z0-9_.:-]{1,120}"))}
     ?.let {result["codecDiagnosticInfo"]=it}
    return result
   }
   cause=current.cause
  }
  return result
 }
}
