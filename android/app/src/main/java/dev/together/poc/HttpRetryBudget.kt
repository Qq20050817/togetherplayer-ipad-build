package dev.together.poc
/** Consecutive failures cannot gain new attempts from a room pause or reload. */
internal class HttpRetryBudget {
 var attempts=0;private set
 private var stableSince:Long?=null
 fun claim():Int? {
  stableSince=null
  if(attempts>=2)return null
  return attempts++
 }
 fun observe(now:Long,advancing:Boolean){
  if(!advancing){stableSince=null;return}
  val start=stableSince
  if(start==null)stableSince=now
  else if(now-start>=30_000){attempts=0;stableSince=now}
 }
 fun reset(){attempts=0;stableSince=null}
}
