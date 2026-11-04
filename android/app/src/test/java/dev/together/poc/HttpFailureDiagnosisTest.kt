package dev.together.poc
import org.junit.Test
import org.junit.Assert.*
import androidx.media3.common.PlaybackException as P
class HttpFailureDiagnosisTest {
 @Test fun authAndMissingFilesAreNotMisreportedAsCodecErrors(){assertEquals("HTTP_AUTH",HttpFailureDiagnosis.classify(P.ERROR_CODE_IO_BAD_HTTP_STATUS,403).category);assertFalse(HttpFailureDiagnosis.classify(P.ERROR_CODE_IO_BAD_HTTP_STATUS,404).retryable)}
 @Test fun partialReadsTimeoutAndRangeAreRecoverable(){assertEquals("INCOMPLETE",HttpFailureDiagnosis.classify(P.ERROR_CODE_IO_UNSPECIFIED,null,setOf("EOFException")).category);assertTrue(HttpFailureDiagnosis.classify(P.ERROR_CODE_IO_NETWORK_CONNECTION_TIMEOUT,null).retryable);assertTrue(HttpFailureDiagnosis.classify(P.ERROR_CODE_IO_BAD_HTTP_STATUS,416).retryable)}
 @Test fun htmlAndPermanentStatusAreExplicitAndNotLooped(){assertEquals("UNEXPECTED_CONTENT",HttpFailureDiagnosis.classify(P.ERROR_CODE_IO_INVALID_HTTP_CONTENT_TYPE,null).category);assertFalse(HttpFailureDiagnosis.classify(P.ERROR_CODE_IO_BAD_HTTP_STATUS,400).retryable);assertTrue(HttpFailureDiagnosis.classify(P.ERROR_CODE_IO_BAD_HTTP_STATUS,503).retryable)}
 @Test fun decodingFailureIsNotMistakenForHttpReadFailure(){val result=HttpFailureDiagnosis.classify(P.ERROR_CODE_DECODING_FAILED,null);assertEquals("DECODER",result.category);assertFalse(result.retryable)}
}
