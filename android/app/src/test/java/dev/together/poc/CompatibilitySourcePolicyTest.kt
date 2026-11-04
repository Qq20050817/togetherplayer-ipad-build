package dev.together.poc
import org.junit.Test
import org.junit.Assert.*
class CompatibilitySourcePolicyTest {
 @Test fun localSourcesKeepExistingFallback(){assertTrue(CompatibilitySourcePolicy.allows("content://provider/movie",false));assertTrue(CompatibilitySourcePolicy.allows("file:///movie.mkv",false))}
 @Test fun ordinaryHttpRequiresExplicitRecoveryApproval(){assertFalse(CompatibilitySourcePolicy.allows("https://example.org/movie.mkv",false));assertTrue(CompatibilitySourcePolicy.allows("http://[2001:db8::1]:49185/movie.mkv?expires=1&signature=fixture",true))}
 @Test fun protectedAndInvalidSourcesNeverLoseRequiredHeaders(){for(url in listOf("https://user:password@example.org/movie","https://pan.baidu.com/movie","https://d.pcs.baidu.com/movie","https://d.baidupcs.com/movie","ftp://example.org/movie","https:///missing-host"))assertFalse(url,CompatibilitySourcePolicy.allows(url,true))}
}
