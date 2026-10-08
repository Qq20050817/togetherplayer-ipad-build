package dev.together.poc
class VoiceNoiseGate(val threshold:Double) {
 private var openUntil=0L
 fun accepts(rms:Double,now:Long):Boolean {if(rms.isFinite() && rms>=threshold)openUntil=now+200;return now<openUntil}
}
class VoiceSendGate {
 enum class Phase { IDLE, RECORDING, FINISHING, REVIEW }
 var phase=Phase.IDLE;private set
 private var room=""
 var text="";var limit=300
 fun begin(room:String){this.room=room;text="";phase=Phase.RECORDING}
 fun finish(){if(phase==Phase.RECORDING)phase=Phase.FINISHING}
 fun review(value:String){if(phase==Phase.FINISHING){text=value.trim();phase=Phase.REVIEW}}
 fun cancel(){phase=Phase.IDLE;text="";room=""}
 fun confirm(currentRoom:String,send:(String)->Boolean):Boolean {
  val value=text.trim()
  if(phase!=Phase.REVIEW || room.isBlank() || currentRoom!=room || value.isBlank() || value.codePointCount(0,value.length)>limit)return false
  if(!send(value))return false
  cancel();return true
 }
}
