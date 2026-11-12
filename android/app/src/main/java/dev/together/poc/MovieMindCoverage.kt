package dev.together.poc

/** Pure, observation-only collector. Positions and monotonic time are milliseconds. */
internal class MovieMindCoverage {
    data class Range(val start: Long, val end: Long)

    data class Batch(val ranges: List<Range>, val elapsedMs: Long, val rate: Double)

    private data class Sample(
        val position: Long,
        val now: Long,
        val playing: Boolean,
        val rate: Double,
    )

    private var previous: Sample? = null
    private var ranges = mutableListOf<Range>()
    private var elapsed = 0L
    private var batchRate = 1.0

    fun discontinuity() {
        previous = null
    }

    fun sample(position: Long, now: Long, playing: Boolean, rate: Double) {
        if (position < 0 || !rate.isFinite() || rate !in .25..4.0) {
            previous = null
            return
        }
        val old = previous
        previous = Sample(position, now, playing, rate)
        if (old == null || !playing || !old.playing) return
        val dt = now - old.now
        val delta = position - old.position
        val maximumRate = maxOf(old.rate, rate)
        val expected = dt * (old.rate + rate) / 2
        if (
            dt !in 1..2000 ||
                delta <= 0 ||
                kotlin.math.abs(delta - expected) > maxOf(80.0, dt * maximumRate * .15)
        )
            return
        // The batch records actual media ranges. Its rate is only a conservative
        // validation bound; catch-up adjustments must not create upload bursts.
        batchRate = if (ranges.isEmpty()) maximumRate else maxOf(batchRate, maximumRate)
        elapsed += dt
        val tail = ranges.lastOrNull()
        if (tail != null && tail.end == old.position)
            ranges[ranges.lastIndex] = Range(tail.start, position)
        else ranges.add(Range(old.position, position))
    }

    fun drain(): Batch? {
        if (ranges.isEmpty()) return null
        val b = Batch(ranges.toList(), elapsed, batchRate)
        ranges = mutableListOf()
        elapsed = 0
        return b
    }
}
