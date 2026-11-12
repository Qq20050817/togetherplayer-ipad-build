package dev.together.poc

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class MovieMindJournalPolicyTest {
    private fun record(
        rating: Double? = null,
        original: JSONObject? = null,
        status: String = "seen",
        deleted: Boolean = false,
    ) =
        MovieMindJournalPolicy.record(
            "tmdb:100",
            original,
            status,
            rating,
            "我的真实评价",
            "2026-11-12",
            true,
            "悬疑，反转,悬疑",
            "",
            "不恐怖",
            false,
            true,
            deleted,
        )

    @Test
    fun unratedExperienceAndReviewNeverInventScore() {
        val r = record().getJSONObject("record")
        assertTrue(r.isNull("rating"))
        assertEquals("不恐怖", r.getJSONArray("experience").getString(0))
        assertEquals("我的真实评价", r.getString("comment"))
        assertEquals(2, r.getJSONArray("likes").length())
    }

    @Test
    fun explicitHalfScoreKeepsOptimisticRevision() {
        val body =
            record(
                8.5,
                JSONObject()
                    .put("movieId", "tmdb:100")
                    .put("revision", 7)
                    .put("createdAt", "fixture-created"),
                "rewatch",
            )
        assertEquals(7, body.getInt("expectedRevision"))
        assertEquals(8.5, body.getJSONObject("record").getDouble("rating"), 0.0)
        assertEquals("fixture-created", body.getJSONObject("record").getString("createdAt"))
        assertNotEquals(record().getString("mutationId"), body.getString("mutationId"))
    }

    @Test
    fun nonHalfAndNonFiniteRatingsAreRejected() {
        for (rating in listOf(7.2, -0.5, 10.5, Double.NaN, Double.POSITIVE_INFINITY)) {
            assertTrue(runCatching { record(rating) }.isFailure)
        }
    }

    @Test
    fun allViewingStatesRemainExplicit() {
        for (status in MovieMindJournalPolicy.statuses) assertEquals(
            status,
            record(status = status).getJSONObject("record").getString("status"),
        )
        assertTrue(runCatching { record(status = "technical_failure") }.isFailure)
    }

    @Test
    fun withdrawalKeepsRevisionAndCannotReassignAnotherMovie() {
        val b =
            record(
                original = JSONObject().put("movieId", "tmdb:100").put("revision", 3),
                deleted = true,
            )
        assertEquals(3, b.getInt("expectedRevision"))
        assertTrue(b.getJSONObject("record").getBoolean("deleted"))
        assertTrue(
            runCatching { record(original = JSONObject().put("movieId", "tmdb:101")) }.isFailure
        )
    }

    @Test
    fun canonicalIdentityAndTriStateEvidenceDoNotUseTitleAlone() {
        val a = MovieMindJournalPolicy.work("manual:fixture_2000", "同名", "", 2000, 0, "悬疑", "血腥")
        val b = MovieMindJournalPolicy.work("manual:fixture_2020", "同名", "", 2020, 0, "悬疑", "")
        assertNotEquals(a.getString("id"), b.getString("id"))
        assertEquals("present", a.getJSONObject("tags").getJSONObject("悬疑").getString("state"))
        assertEquals("absent", a.getJSONObject("tags").getJSONObject("血腥").getString("state"))
        assertFalse(a.getJSONObject("tags").has("突脸"))
        assertTrue(
            runCatching {
                    MovieMindJournalPolicy.work(
                        "manual:fixture_2000",
                        "同名",
                        "",
                        2000,
                        90,
                        "血腥",
                        "血腥",
                    )
                }
                .isFailure
        )
        assertTrue(
            runCatching {
                    MovieMindJournalPolicy.work("/private/fixture.mkv", "同名", "", 2000, 90, "", "")
                }
                .isFailure
        )
    }

    @Test
    fun conflictMergeKeepsReviewTagsAndWithdrawalWithoutReplacingServerIdentity() {
        val current =
            JSONObject().put("movieId", "tmdb:100").put("revision", 5).put("source", "manual")
        val draft =
            JSONObject()
                .put("movieId", "tmdb:200")
                .put("revision", 1)
                .put("rating", JSONObject.NULL)
                .put("likes", org.json.JSONArray().put("反转"))
                .put("watchedOn", "2026-11-12")
                .put("deleted", true)
        val merged = MovieMindJournalPolicy.mergeDraft(current, draft)
        assertEquals("tmdb:100", merged.getString("movieId"))
        assertEquals(5, merged.getInt("revision"))
        assertTrue(merged.isNull("rating"))
        assertEquals("反转", merged.getJSONArray("likes").getString(0))
        assertEquals("2026-11-12", merged.getString("watchedOn"))
        assertTrue(merged.getBoolean("deleted"))
    }
}
