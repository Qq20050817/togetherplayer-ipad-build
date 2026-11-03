package dev.together.poc
import org.junit.Test
import org.junit.Assert.*
class HttpRetryBudgetTest {
 @Test fun pausedAndUnreadyIntervalsNeverRefillBudget(){
  val b=HttpRetryBudget();assertEquals(0,b.claim());b.observe(0,false);b.observe(60000,false);assertEquals(1,b.claim());b.observe(120000,false);assertNull(b.claim())
 }
 @Test fun recoveryMustAdvanceContinuouslyBeforeNewBudget(){
  val b=HttpRetryBudget();b.claim();b.claim();b.observe(0,true);b.observe(29000,true);assertEquals(2,b.attempts);b.observe(29999,false);b.observe(60000,true);b.observe(89999,true);assertEquals(2,b.attempts);b.observe(90000,true);assertEquals(0,b.attempts);assertEquals(0,b.claim())
 }
 @Test fun explicitRetryOrDifferentSourceCanStartNewBudget(){val b=HttpRetryBudget();b.claim();b.claim();assertNull(b.claim());b.reset();assertEquals(0,b.claim())}
}
