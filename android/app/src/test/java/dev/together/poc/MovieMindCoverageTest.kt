package dev.together.poc

import org.junit.Assert.*
import org.junit.Test

class MovieMindCoverageTest {
    @Test
    fun changingCatchupRatesStayInOneActualTimeBatch() {
        val c = MovieMindCoverage()
        c.sample(0, 0, true, 1.0)
        c.sample(1000, 1000, true, 1.0)
        c.sample(2500, 2000, true, 2.0)
        c.sample(4500, 3000, true, 2.0)
        val b = c.drain()!!
        assertEquals(3000, b.elapsedMs)
        assertEquals(listOf(MovieMindCoverage.Range(0, 4500)), b.ranges)
        assertEquals(2.0, b.rate, 0.0)
    }

    @Test
    fun seekJumpAndExplicitSmallSeekDoNotCount() {
        val c = MovieMindCoverage()
        c.sample(0, 0, true, 1.0)
        c.sample(1000, 1000, true, 1.0)
        c.discontinuity()
        c.sample(99000, 1100, true, 1.0)
        c.sample(100000, 2100, true, 1.0)
        val b = c.drain()!!
        assertEquals(
            listOf(MovieMindCoverage.Range(0, 1000), MovieMindCoverage.Range(99000, 100000)),
            b.ranges,
        )
        assertEquals(2000, b.elapsedMs)
    }

    @Test
    fun bufferingBackgroundAndLongGapsAreNotCounted() {
        val c = MovieMindCoverage()
        c.sample(0, 0, true, 1.0)
        c.sample(1000, 1000, false, 1.0)
        c.sample(9000, 9000, true, 1.0)
        assertNull(c.drain())
        c.sample(10000, 10000, true, 1.0)
        assertEquals(1000, c.drain()!!.elapsedMs)
    }

    @Test
    fun speedChangesSplitBatchesAndUseActualMediaTime() {
        val c = MovieMindCoverage()
        c.sample(0, 0, true, 2.0)
        c.sample(2000, 1000, true, 2.0)
        val b = c.drain()!!
        assertEquals(2000, b.ranges.single().end)
        assertEquals(1000, b.elapsedMs)
        assertEquals(2.0, b.rate, 0.0)
        c.discontinuity()
        c.sample(2000, 1000, true, 1.0)
        c.sample(3000, 2000, true, 1.0)
        assertEquals(1.0, c.drain()!!.rate, 0.0)
    }
}
