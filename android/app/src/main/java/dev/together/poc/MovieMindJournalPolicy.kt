package dev.together.poc

import java.time.Instant
import java.time.LocalDate
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject

internal data class MovieMindAccountScope(val origin: String, val account: String) {
    val configured: Boolean
        get() = origin.isNotBlank() && account.isNotBlank()
}

internal object MovieMindJournalPolicy {
    val statuses = listOf("want", "watching", "seen", "hold", "dropped", "rewatch")
    val statusNames = listOf("想看", "观看中", "已看", "暂时搁置", "弃看", "重看")
    private val identity =
        Regex("^(tmdb:[1-9][0-9]{0,11}|imdb:tt[0-9]{5,12}|manual:[A-Za-z0-9_-]{8,80})$")
    private val keys =
        setOf(
            "movieId",
            "status",
            "favorite",
            "watchedOn",
            "together",
            "sharedWish",
            "rating",
            "likes",
            "dislikes",
            "experience",
            "comment",
            "source",
            "revision",
            "createdAt",
            "updatedAt",
            "deleted",
        )

    fun tags(text: String): List<String> =
        text.split(',', '，', '\n').map { it.trim() }.filter { it.isNotEmpty() }.distinct()

    private fun validTags(values: List<String>) =
        values.size <= 40 && values.all { it.toByteArray(Charsets.UTF_8).size <= 100 }

    fun record(
        movie: String,
        original: JSONObject?,
        status: String,
        rating: Double?,
        comment: String,
        date: String,
        together: Boolean,
        likes: String,
        dislikes: String,
        experience: String,
        favorite: Boolean,
        sharedWish: Boolean,
        deleted: Boolean = false,
    ): JSONObject {
        val positive = tags(likes)
        val negative = tags(dislikes)
        val features = tags(experience)
        require(
            identity.matches(movie) &&
                status in statuses &&
                comment.toByteArray(Charsets.UTF_8).size <= 2000
        )
        require(
            rating == null || (rating.isFinite() && rating in 0.0..10.0 && rating * 2 % 1.0 == 0.0)
        )
        require(validTags(positive) && validTags(negative) && validTags(features))
        if (date.isNotEmpty()) require(LocalDate.parse(date).toString() == date)
        val revision = original?.optInt("revision", 0) ?: 0
        require(revision >= 0 && (original?.optString("movieId", movie) ?: movie) == movie)
        val record = JSONObject()
        original?.keys()?.forEach { if (it in keys) record.put(it, original.opt(it)) }
        record
            .put("movieId", movie)
            .put("source", original?.optString("source", "manual") ?: "manual")
            .put("status", status)
            .put("rating", rating ?: JSONObject.NULL)
            .put("comment", comment)
            .put("watchedOn", date)
            .put("together", together)
            .put("likes", JSONArray(positive))
            .put("dislikes", JSONArray(negative))
            .put("experience", JSONArray(features))
            .put("favorite", favorite)
            .put("sharedWish", sharedWish)
            .put("deleted", deleted)
        return JSONObject()
            .put("record", record)
            .put("expectedRevision", revision)
            .put("mutationId", UUID.randomUUID().toString())
    }

    fun mergeDraft(current: JSONObject?, draft: JSONObject): JSONObject {
        val merged =
            current?.let { JSONObject(it.toString()) }
                ?: JSONObject().put("movieId", draft.getString("movieId")).put("source", "manual")
        for (key in
            listOf(
                "status",
                "rating",
                "comment",
                "together",
                "watchedOn",
                "likes",
                "dislikes",
                "experience",
                "favorite",
                "sharedWish",
                "deleted",
            )) {
            if (draft.has(key)) merged.put(key, draft.opt(key))
        }
        return merged
    }

    fun work(
        id: String,
        title: String,
        originalTitle: String,
        year: Int,
        runtime: Int,
        present: String,
        absent: String,
    ): JSONObject {
        val positive = tags(present)
        val negative = tags(absent)
        require(
            identity.matches(id) &&
                title.isNotBlank() &&
                title.toByteArray(Charsets.UTF_8).size <= 300
        )
        require(
            originalTitle.toByteArray(Charsets.UTF_8).size <= 300 &&
                year in 1880..2200 &&
                runtime in 0..1000
        )
        require(
            validTags(positive) &&
                validTags(negative) &&
                positive.intersect(negative.toSet()).isEmpty()
        )
        val evidence = JSONObject()
        for ((values, state) in listOf(positive to "present", negative to "absent")) {
            for (tag in values) evidence.put(
                tag,
                JSONObject()
                    .put("state", state)
                    .put("source", "本人确认")
                    .put("method", "human")
                    .put("reliability", .9)
                    .put("updatedAt", Instant.now().toString()),
            )
        }
        return JSONObject()
            .put("id", id)
            .put("title", title.trim())
            .put("originalTitle", originalTitle)
            .put("year", year)
            .put("runtime", runtime)
            .put("poster", "")
            .put("aliases", JSONArray())
            .put("tags", evidence)
            .put("source", "manual")
            .put("revision", 0)
    }
}
