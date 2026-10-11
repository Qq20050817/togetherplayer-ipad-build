package dev.together.poc
import org.junit.Test
import org.junit.Assert.*
class MovieVariantPolicyTest {
 @Test fun sameEditTranscodeAllowsSmallContainerDurationDifferences(){assertEquals(MovieVariantPolicy.DurationCheck.COMPATIBLE,MovieVariantPolicy.duration(6001500.0,0.0,6000000.0))}
 @Test fun differentEditStaysBlocked(){assertEquals(MovieVariantPolicy.DurationCheck.DIFFERENT,MovieVariantPolicy.duration(6200000.0,0.0,6000000.0))}
 @Test fun unknownDurationNeverGrantsReadiness(){assertEquals(MovieVariantPolicy.DurationCheck.WAITING,MovieVariantPolicy.duration(6000000.0,0.0,0.0));assertEquals(MovieVariantPolicy.DurationCheck.WAITING,MovieVariantPolicy.duration(Double.NaN,0.0,6000000.0))}
 @Test fun timelineOffsetIsAppliedToDuration(){assertEquals(MovieVariantPolicy.DurationCheck.COMPATIBLE,MovieVariantPolicy.duration(6008000.0,8000.0,6000000.0))}
}
