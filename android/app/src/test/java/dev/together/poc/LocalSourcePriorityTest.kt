package dev.together.poc
import org.junit.Test
import org.junit.Assert.*
class LocalSourcePriorityTest {
 private val room="http://example.org:49185/usb/film.mkv?sig=old"
 private fun route(request:String=room,local:String="content://docs/film",missing:Boolean=false,bound:String="r",movie:String=room)=LocalSourcePriority.decide(request,"r",room,bound,movie,local,missing)
 @Test fun validLocalAlwaysWinsIncludingRenewedHttpQueries(){assertEquals(LocalSourcePriority.Action.LOCAL,route());assertEquals(LocalSourcePriority.Action.LOCAL,route(request=room.replace("old","new")))}
 @Test fun missingGrantRequiresExplicitReselectOrUnbind(){assertEquals(LocalSourcePriority.Action.RESELECT,route(local="",missing=true));assertEquals(LocalSourcePriority.Action.REQUESTED,route(local=""))}
 @Test fun noBindingUsesUsbAndOtherRoomCannotChangeThisSource(){assertEquals(LocalSourcePriority.Action.REQUESTED,route(bound="other"));assertEquals(LocalSourcePriority.Action.REQUESTED,route(movie="http://example.org/other.mkv"))}
 @Test fun localReadAndExplicitOtherSourceRemainDeviceLocal(){assertEquals(LocalSourcePriority.Action.REQUESTED,route(request="content://docs/film"));assertEquals(LocalSourcePriority.Action.REQUESTED,route(request="http://example.org/alternate.mp4"))}
}
