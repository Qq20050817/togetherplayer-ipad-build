package dev.together.poc
import org.junit.Assert.*
import org.junit.Test
class VoiceDanmakuTest {
 @Test fun noAutomaticSendAndEditBeforeExplicitConfirmation(){val gate=VoiceSendGate();val sent=mutableListOf<String>();gate.begin("r");gate.text="partial";assertFalse(gate.confirm("r"){sent.add(it);true});gate.finish();assertFalse(gate.confirm("r"){sent.add(it);true});gate.review("result");assertTrue(sent.isEmpty());gate.text="edited";assertTrue(gate.confirm("r"){sent.add(it);true});assertEquals(listOf("edited"),sent);assertFalse(gate.confirm("r"){sent.add(it);true})}
 @Test fun cancellationRoomChangeAndTransportFailure(){val gate=VoiceSendGate();gate.begin("r");gate.finish();gate.review("hello");assertFalse(gate.confirm("new"){throw AssertionError("wrong room")});assertFalse(gate.confirm("r"){false});assertEquals(VoiceSendGate.Phase.REVIEW,gate.phase);gate.cancel();gate.review("late callback");assertFalse(gate.confirm("r"){throw AssertionError("cancelled")})}
 @Test fun thresholdRejectsQuietButKeepsTwoHundredMsTail(){val filter=VoiceNoiseGate(0.02);assertFalse(filter.accepts(0.001,1000));assertTrue(filter.accepts(0.025,2000));assertTrue(filter.accepts(0.001,2100));assertFalse(filter.accepts(0.001,2201));assertFalse(filter.accepts(Double.NaN,2300))}
 @Test fun twentyConfirmationsWithoutDuplicateSend(){val gate=VoiceSendGate();val sent=mutableListOf<String>();repeat(20){gate.begin("r");gate.finish();gate.review("message $it");assertTrue(gate.confirm("r"){sent.add(it);true});assertFalse(gate.confirm("r"){sent.add(it);true})};assertEquals(20,sent.size);assertEquals(20,sent.toSet().size)}
 @Test fun emptyAndOversizedNotSent(){val gate=VoiceSendGate();gate.begin("r");gate.finish();gate.review(" ");assertFalse(gate.confirm("r"){throw AssertionError("empty")});gate.text="字".repeat(301);assertFalse(gate.confirm("r"){throw AssertionError("long")})}
}
