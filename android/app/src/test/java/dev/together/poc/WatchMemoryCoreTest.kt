package dev.together.poc
import org.junit.Test
import org.junit.Assert.*
class WatchMemoryCoreTest {
 private val mystery=MemoryFilm("m","悬疑候选",2000,emptyList(),listOf("悬疑"),"查案")
 private val comedy=MemoryFilm("c","喜剧候选",2001,emptyList(),listOf("喜剧"),"日常")
 @Test fun identityAndRemake(){val f=MemoryFilm("g","罪人",2018,listOf("The Guilty"),listOf("悬疑"),"电话案件");assertEquals("g",FilmTaste.match("The.Guilty.2018.DANISH.1080p.mkv",listOf(f))?.id);assertNull(FilmTaste.match("The Guilty 2021",listOf(f)))}
 @Test fun emptyHistoryHasNoPretendPersonalization(){assertTrue(FilmTaste.suggestions(emptyList(),listOf(mystery),emptySet()).isEmpty())}
 @Test fun ratingsChangeRanking(){val r=MemoryRecord("seen","看过的电影",0,5,listOf("悬疑"));assertEquals("m",FilmTaste.suggestions(listOf(r),listOf(mystery,comedy),emptySet()).first().film.id);assertEquals("c",FilmTaste.suggestions(listOf(r.copy(rating=1)),listOf(mystery,comedy),emptySet()).first().film.id)}
 @Test fun watchedAndDismissedExcluded(){val r=MemoryRecord("m","悬疑候选",0,5,listOf("悬疑"));assertTrue(FilmTaste.suggestions(listOf(r),listOf(mystery,comedy),setOf("c")).isEmpty())}
 @Test fun unratedIsNotDescribedAsLiked(){val r=MemoryRecord("seen","看过的电影",0,tags=listOf("悬疑"));assertFalse(FilmTaste.suggestions(listOf(r),listOf(mystery),emptySet()).first().reason.contains("较高评价"))}
 @Test fun scrubDoesNotComplete(){val c=WatchCoverage();assertFalse(c.sample("a",0.0,100.0,true,0.0));assertFalse(c.sample("a",100.0,100.0,true,1.0));for(t in 2..100)assertFalse(c.sample("a",100.0,100.0,false,t.toDouble()));assertFalse(c.sample("b",100.0,100.0,true,101.0))}
 @Test fun continuousPlaybackCompletes(){val c=WatchCoverage();for(t in 0..96)assertFalse(c.sample("a",t.toDouble(),100.0,true,t.toDouble()));assertTrue(c.sample("a",97.0,100.0,true,97.0))}
 @Test fun replayCannotInflateCoverage(){val c=WatchCoverage();for(lap in 0..4)for(p in 0..20)c.sample("a",p.toDouble(),100.0,true,(lap*21+p).toDouble());assertFalse(c.sample("a",100.0,100.0,true,106.0))}
}
