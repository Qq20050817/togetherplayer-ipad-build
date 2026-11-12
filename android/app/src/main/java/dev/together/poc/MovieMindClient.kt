package dev.together.poc

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject

/**
 * Room credentials, media URLs, file paths, subtitles and video data are never serialized or
 * transmitted.
 */
internal class MovieMindClient(context: Context) {
    companion object {
        @Volatile private var sharedInstance: MovieMindClient? = null

        fun shared(context: Context): MovieMindClient =
            sharedInstance
                ?: synchronized(this) {
                    sharedInstance
                        ?: MovieMindClient(context.applicationContext).also { sharedInstance = it }
                }
    }

    private val app = context.applicationContext
    private val prefs = app.getSharedPreferences("moviemind", Context.MODE_PRIVATE)
    private val main = Handler(Looper.getMainLooper())
    private val worker =
        Executors.newSingleThreadScheduledExecutor { r ->
            Thread(r, "moviemind-outbox").apply { isDaemon = true }
        }
    private val http =
        okhttp3.OkHttpClient.Builder()
            .callTimeout(3, TimeUnit.SECONDS)
            .connectTimeout(2, TimeUnit.SECONDS)
            .readTimeout(2, TimeUnit.SECONDS)
            .followRedirects(false)
            .followSslRedirects(false)
            .build()
    private val outboxFile = File(app.filesDir, "moviemind-outbox.json")
    private var outbox = JSONArray()
    private var blockedStore = false
    private var source: java.lang.ref.WeakReference<Any>? = null
    private var movieId = ""
    private var bindingAccount: String? = null
    private var bindingOrigin = ""
    private var editionId = ""
    private var duration = 0L
    private var sessionId = ""
    private var lastFlush = 0L
    private var wasEnded = false
    private var collector = MovieMindCoverage()
    private var suggestionShown = false
    @Volatile
    var status = "MovieMind 未连接"
        private set

    var stateChanged: (() -> Unit)? = null
    var possibleFinished: ((String, String) -> Unit)? = null
    var enabled: Boolean
        get() = prefs.getBoolean("enabled", false)
        set(value) {
            prefs.edit().putBoolean("enabled", value).apply()
            if (!value) {
                source = null
                movieId = ""
                collector = MovieMindCoverage()
            } else retry()
            publish(if (value) "MovieMind 已开启" else "MovieMind 已关闭")
        }

    var watchEnabled: Boolean
        get() = prefs.getBoolean("watchEnabled", false)
        set(value) {
            prefs.edit().putBoolean("watchEnabled", value).apply()
            collector = MovieMindCoverage()
        }

    var ratingEnabled: Boolean
        get() = prefs.getBoolean("ratingEnabled", true)
        set(value) {
            prefs.edit().putBoolean("ratingEnabled", value).apply()
        }

    var recommendationEnabled: Boolean
        get() = prefs.getBoolean("recommendationEnabled", true)
        set(value) {
            prefs.edit().putBoolean("recommendationEnabled", value).apply()
        }

    val baseURL: String
        get() = prefs.getString("origin", "").orEmpty()

    val boundMovie: String
        get() = movieId

    init {
        worker.execute {
            try {
                if (outboxFile.exists()) {
                    val restored = JSONArray(outboxFile.readText())
                    require(restored.length() <= 1000)
                    var changed = false
                    for (i in 0 until restored.length()) {
                        val row = restored.getJSONObject(i)
                        row.getString("path")
                        row.getString("method")
                        row.getJSONObject("body")
                        if (row.optString("queueId").isBlank()) {
                            row.put("queueId", UUID.randomUUID().toString())
                            changed = true
                        }
                    }
                    outbox = restored
                    if (changed) persist()
                }
                publish(if (outbox.length() > 0) "有 ${outbox.length()} 项待同步" else "MovieMind 已就绪")
            } catch (_: Exception) {
                blockedStore = true
                publish("待同步文件损坏，原文件已保留；请先导出核对")
            }
        }
        worker.scheduleWithFixedDelay(
            { if (enabled) runCatching { flushWorker() } },
            30,
            30,
            TimeUnit.SECONDS,
        )
    }

    private fun publish(text: String) {
        status = text
        main.post { stateChanged?.invoke() }
    }

    private fun key(): SecretKey {
        val ks = java.security.KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        return (ks.getKey("moviemind-auth", null) as? SecretKey)
            ?: KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
                .apply {
                    init(
                        KeyGenParameterSpec.Builder(
                                "moviemind-auth",
                                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
                            )
                            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                            .build()
                    )
                }
                .generateKey()
    }

    private fun token(): String {
        val raw = prefs.getString("auth", null) ?: return ""
        val data = Base64.decode(raw, Base64.NO_WRAP)
        return Cipher.getInstance("AES/GCM/NoPadding").run {
            init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, data.copyOfRange(0, 12)))
            String(doFinal(data.copyOfRange(12, data.size)), Charsets.UTF_8)
        }
    }

    private fun saveToken(value: String) {
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.ENCRYPT_MODE, key())
        prefs
            .edit()
            .putString(
                "auth",
                Base64.encodeToString(c.iv + c.doFinal(value.toByteArray()), Base64.NO_WRAP),
            )
            .apply()
    }

    private fun persist() {
        check(!blockedStore)
        val temp = File(outboxFile.path + ".tmp")
        temp.outputStream().use {
            it.write(outbox.toString().toByteArray())
            it.fd.sync()
        }
        check(temp.renameTo(outboxFile))
    }

    private fun origin(raw: String): String {
        val u = java.net.URI(raw.trim())
        require(
            u.rawUserInfo == null &&
                u.rawQuery == null &&
                u.rawFragment == null &&
                (u.path.isNullOrEmpty() || u.path == "/")
        )
        require(
            u.scheme == "https" ||
                BuildConfig.DEBUG &&
                    u.scheme == "http" &&
                    u.host in listOf("127.0.0.1", "localhost", "10.0.2.2")
        )
        return u.toString().trimEnd('/')
    }

    private class APIError(val code: Int) : Exception()

    private fun request(
        path: String,
        body: JSONObject? = null,
        method: String = if (body == null) "GET" else "POST",
        auth: String? = null,
    ): String {
        val base = baseURL
        check(base.isNotBlank())
        val token = auth ?: token()
        val b =
            okhttp3.Request.Builder()
                .url(base + "/api/" + path)
                .header("X-MovieMind", "1")
                .header("X-MovieMind-Client", "native")
                .header("X-MovieMind-Account", prefs.getString("userId", null).orEmpty())
        if (token.isNotBlank()) b.header("Authorization", "Bearer $token")
        b.method(
            method,
            if (method == "GET") null
            else (body ?: JSONObject()).toString().toRequestBody("application/json".toMediaType()),
        )
        return http.newCall(b.build()).execute().use { r ->
            if (!r.isSuccessful) throw APIError(r.code)
            val text = r.body?.string() ?: throw java.io.IOException()
            require(text.length <= 2 * 1024 * 1024)
            text
        }
    }

    fun login(raw: String, name: String, password: String, done: (Boolean) -> Unit) {
        if (movieId.isNotBlank()) {
            publish("请先关闭 MovieMind 结束当前观影绑定，再登录账号；播放继续")
            main.post { done(false) }
            return
        }
        worker.execute {
            val before = baseURL
            try {
                val target = origin(raw)
                if (outbox.length() > 0 && (before.isBlank() || before != target))
                    throw IllegalStateException()
                prefs.edit().putString("origin", target).apply()
                val result =
                    JSONObject(
                        request(
                            "auth/login",
                            JSONObject().put("name", name).put("password", password),
                            auth = "",
                        )
                    )
                val user = result.getString("userId")
                if (outbox.length() > 0 && prefs.getString("userId", null) != user)
                    throw IllegalStateException()
                saveToken(result.getString("token"))
                prefs.edit().putString("userId", user).apply()
                publish("已登录独立 MovieMind 账号")
                main.post { done(true) }
                flushWorker()
            } catch (_: Exception) {
                prefs.edit().putString("origin", before).apply()
                publish("登录失败；检查地址与账号。待同步内容只能同步到原账号和服务。")
                main.post { done(false) }
            }
        }
    }

    val workspaceScope: MovieMindAccountScope
        get() = MovieMindAccountScope(baseURL, prefs.getString("userId", null).orEmpty())

    fun api(
        scope: MovieMindAccountScope,
        path: String,
        body: JSONObject? = null,
        method: String = "GET",
        done: (String?, String?) -> Unit,
    ) {
        worker.execute {
            var error: String? = null
            val result =
                try {
                    check(scope.configured && scope == workspaceScope)
                    request(path, body, method)
                } catch (e: Exception) {
                    error =
                        when {
                            scope != workspaceScope -> "账号或服务已改变，请重新打开电影档案"
                            e is APIError && e.code == 401 -> "登录已过期，请回到账号页重新登录；草稿保留"
                            e is APIError && e.code == 409 -> "资料在其他设备有修改，请刷新核对；原输入保留"
                            e is APIError && e.code == 403 -> "操作尚未获授权，请核对登录与配对状态"
                            e is APIError && e.code == 429 -> "操作较频繁，请稍后重试"
                            else -> "暂时无法连接 MovieMind，原输入保留，请稍后重试"
                        }
                    null
                }
            main.post {
                if (scope != workspaceScope) done(null, "账号或服务已改变，请重新打开电影档案")
                else runCatching { done(result, error) }.onFailure { publish("电影资料无法显示，原内容保留") }
            }
        }
    }

    fun saveJournal(scope: MovieMindAccountScope, body: JSONObject, done: (Boolean) -> Unit) {
        if (!scope.configured || scope != workspaceScope) {
            publish("账号或服务已改变，尚未保存；请核对原草稿")
            main.post { done(false) }
            return
        }
        enqueue(
            "records/" + body.getJSONObject("record").getString("movieId"),
            body,
            "PUT",
            onSaved = done,
            userInitiated = true,
            expectedScope = scope,
        )
    }

    fun get(path: String, done: (String?) -> Unit) {
        val account = prefs.getString("userId", null)
        val target = baseURL
        worker.execute {
            val result =
                runCatching {
                        check(account == prefs.getString("userId", null) && target == baseURL)
                        request(path).also { raw ->
                            val rows = JSONArray(raw)
                            for (i in 0 until rows.length()) {
                                val row = rows.getJSONObject(i)
                                when {
                                    path == "movies" -> {
                                        row.getString("id")
                                        row.getString("title")
                                        row.getInt("year")
                                    }
                                    path.startsWith("editions?") -> {
                                        row.getString("id")
                                        row.getString("movieId")
                                        row.getString("label")
                                        require(row.getLong("durationMs") > 0)
                                    }
                                    path == "records" -> {
                                        row.getString("movieId")
                                        if (!row.isNull("rating")) {
                                            val rating = row.getDouble("rating")
                                            require(
                                                rating.isFinite() &&
                                                    rating in 0.0..10.0 &&
                                                    rating * 2 % 1 == 0.0
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .getOrNull()
            if (result == null) publish("MovieMind 资料暂不可用或格式异常，播放不受影响")
            main.post {
                if (account != prefs.getString("userId", null) || target != baseURL) {
                    publish("账号或服务已改变，请重新打开 MovieMind")
                    return@post
                }
                runCatching { done(result) }.onFailure { publish("MovieMind 资料无法显示，播放不受影响") }
            }
        }
    }

    fun bind(
        movie: String,
        edition: String,
        milliseconds: Long,
        currentSource: Any?,
        actualDuration: Long,
    ): Boolean {
        if (
            currentSource == null ||
                actualDuration <= 0 ||
                kotlin.math.abs(actualDuration - milliseconds) > 1000
        )
            return false
        flush()
        source = java.lang.ref.WeakReference(currentSource)
        movieId = movie
        bindingAccount = prefs.getString("userId", null)
        bindingOrigin = baseURL
        editionId = edition
        duration = milliseconds
        sessionId = UUID.randomUUID().toString()
        collector = MovieMindCoverage()
        suggestionShown = false
        wasEnded = false
        publish("已确认作品与剪辑版本（仅本机绑定）")
        return true
    }

    fun discontinuity() {
        collector.discontinuity()
    }

    fun sample(
        currentSource: Any?,
        position: Long,
        actualDuration: Long,
        playing: Boolean,
        rate: Double,
        seeking: Boolean,
        foreground: Boolean,
        ended: Boolean,
    ) {
        if (!enabled) return
        if (
            movieId.isNotBlank() &&
                (bindingAccount != prefs.getString("userId", null) || bindingOrigin != baseURL)
        ) {
            source = null
            movieId = ""
            collector = MovieMindCoverage()
            publish("账号或服务已改变，请重新确认作品与版本")
            return
        }
        if (source?.get() == null || currentSource !== source?.get()) {
            if (movieId.isNotBlank()) {
                flush()
                source = null
                movieId = ""
                publish("片源实例已改变，请重新确认作品与版本")
            }
            return
        }
        if (!watchEnabled) return
        val now = android.os.SystemClock.elapsedRealtime()

        if (seeking || !foreground || kotlin.math.abs(actualDuration - duration) > 1000)
            collector.discontinuity()
        collector.sample(position, now, playing && !seeking && foreground, rate)
        if (now - lastFlush >= 30000 || ended && !wasEnded) {
            flush(ended)
            lastFlush = now
        }
        wasEnded = ended
    }

    fun flush(ended: Boolean = false) {
        val batch = collector.drain()
        if (batch != null && sessionId.isNotBlank()) {
            val intervals = JSONArray()
            batch.ranges.forEach {
                intervals.put(JSONObject().put("start", it.start).put("end", it.end))
            }
            val event =
                JSONObject()
                    .put("id", UUID.randomUUID().toString())
                    .put("sessionId", sessionId)
                    .put("editionId", editionId)
                    .put("intervals", intervals)
                    .put("elapsedMs", batch.elapsedMs)
                    .put("rate", batch.rate)
                    .put("ended", ended)
            enqueue("watch/events", event, "POST", movieId)
        } else retry()
    }

    private fun enqueue(
        path: String,
        body: JSONObject,
        method: String,
        work: String = "",
        onSaved: ((Boolean) -> Unit)? = null,
        userInitiated: Boolean = false,
        expectedScope: MovieMindAccountScope? = null,
    ) {
        val account = expectedScope?.account ?: prefs.getString("userId", null)
        val target = expectedScope?.origin ?: baseURL
        worker.execute {
            if (account != prefs.getString("userId", null) || target != baseURL) {
                publish("账号或服务已改变，尚未保存；请核对原评分草稿")
                main.post { onSaved?.invoke(false) }
                return@execute
            }
            try {
                if (outbox.length() >= 1000) {
                    publish("待同步队列已满，请先同步；观影记录暂不继续写入")
                    main.post { onSaved?.invoke(false) }
                    return@execute
                }
                outbox.put(
                    JSONObject()
                        .put("queueId", UUID.randomUUID().toString())
                        .put("path", path)
                        .put("body", body)
                        .put("method", method)
                        .put("state", "pending")
                        .put("movieId", work)
                        .put("userInitiated", userInitiated)
                )
                persist()
                publish("已保存在本机，等待同步")
                main.post { onSaved?.invoke(true) }
                flushWorker()
            } catch (_: Exception) {
                blockedStore = true
                publish("无法可靠保存待同步内容，请保留原文件；播放不受影响")
                main.post { onSaved?.invoke(false) }
            }
        }
    }

    fun saveRating(
        movie: String,
        rating: Double?,
        comment: String,
        together: Boolean,
        original: JSONObject?,
        done: (Boolean) -> Unit,
    ) {
        val r =
            original?.let { JSONObject(it.toString()) }
                ?: JSONObject().put("movieId", movie).put("source", "manual")
        val rev = r.optInt("revision", 0)
        r.put("status", "seen")
            .put("rating", rating ?: JSONObject.NULL)
            .put("comment", comment)
            .put("together", together)
            .put("deleted", false)
        val body =
            JSONObject()
                .put("record", r)
                .put("expectedRevision", rev)
                .put("mutationId", UUID.randomUUID().toString())
        enqueue("records/$movie", body, "PUT", onSaved = done)
    }

    fun completion(session: String?, decision: String) {
        if (!session.isNullOrBlank())
            enqueue(
                "watch/sessions/$session/completion",
                JSONObject().put("decision", decision),
                "PUT",
            )
    }

    private fun flushWorker() {
        if (blockedStore) return
        var index = 0
        while (index < outbox.length()) {
            val row = outbox.getJSONObject(index)
            if (row.optString("state") == "conflict") {
                index++
                continue
            }
            val path = row.getString("path")
            if (!enabled && !row.optBoolean("userInitiated")) {
                index++
                continue
            }
            if (
                path == "watch/events" && !watchEnabled ||
                    path.startsWith("records/") &&
                        !ratingEnabled &&
                        !row.optBoolean("userInitiated")
            ) {
                index++
                continue
            }
            try {
                val body = row.getJSONObject("body")
                val reply = JSONObject(request(path, body, row.getString("method")))
                when {
                    path.startsWith("records/") -> {
                        require(reply.getString("mutationId") == body.getString("mutationId"))
                        require(
                            reply.getString("movieId") ==
                                body.getJSONObject("record").getString("movieId")
                        )
                        require(reply.getInt("revision") > 0)
                    }
                    path == "watch/events" -> {
                        require(reply.getString("eventId") == body.getString("id"))
                        require(reply.getString("id") == body.getString("sessionId"))
                        require(reply.getString("editionId") == body.getString("editionId"))
                        require(reply.getLong("coveredMs") >= 0)
                        reply.getBoolean("possibleFinished")
                    }
                    else -> require(reply.getBoolean("saved"))
                }
                outbox.remove(index)
                persist()
                if (
                    path == "watch/events" &&
                        reply.optBoolean("possibleFinished") &&
                        !suggestionShown
                ) {
                    suggestionShown = true
                    val movie = row.optString("movieId")
                    val session = row.getJSONObject("body").optString("sessionId")
                    main.post { if (ratingEnabled) possibleFinished?.invoke(movie, session) }
                }
            } catch (e: APIError) {
                if (e.code == 409) {
                    row.put("state", "conflict")
                    persist()
                    publish("并发编辑冲突已保留，请核对待同步草稿")
                    index++
                } else {
                    publish("待同步（HTTP ${e.code}），稍后仍使用原事件 ID 重试")
                    return
                }
            } catch (_: Exception) {
                publish("服务未确认保存（离线、超时或回执异常），待同步内容已保留；播放不受影响")
                return
            }
        }
        publish(if (outbox.length() == 0) "MovieMind 已同步" else "有 ${outbox.length()} 项需要核对或启用相应接入点")
    }

    fun close() {
        worker.shutdown()
    }

    fun retry() {
        worker.execute { runCatching { flushWorker() }.onFailure { publish("待同步内容已保留，请重试") } }
    }

    fun pending(done: (JSONArray) -> Unit) {
        worker.execute {
            val copy = JSONArray(outbox.toString())
            main.post { runCatching { done(copy) }.onFailure { publish("待同步内容无法显示，原文件已保留") } }
        }
    }

    fun resolve(queueId: String, overwrite: Boolean, expectedRevision: Int? = null) {
        worker.execute {
            try {
                val index =
                    (0 until outbox.length()).firstOrNull {
                        outbox.getJSONObject(it).optString("queueId") == queueId
                    } ?: return@execute
                val row = outbox.getJSONObject(index)
                if (!overwrite) {
                    outbox.remove(index)
                    persist()
                    publish("已明确丢弃草稿")
                    return@execute
                }
                val path = row.getString("path")
                if (!path.startsWith("records/")) return@execute
                val latest = JSONArray(request("records"))
                val draft = row.getJSONObject("body").getJSONObject("record")
                var current: JSONObject? = null
                for (i in 0 until latest.length()) {
                    val r = latest.getJSONObject(i)
                    if (r.optString("movieId") == draft.optString("movieId")) current = r
                }
                if (
                    expectedRevision == null ||
                        (current?.optInt("revision", 0) ?: 0) != expectedRevision
                ) {
                    publish("服务器记录又有变化，请重新核对；草稿仍保留")
                    return@execute
                }
                val merged = MovieMindJournalPolicy.mergeDraft(current, draft)
                row.put(
                        "body",
                        JSONObject()
                            .put("record", merged)
                            .put("expectedRevision", current?.optInt("revision", 0) ?: 0)
                            .put("mutationId", UUID.randomUUID().toString()),
                    )
                    .put("state", "pending")
                persist()
                flushWorker()
            } catch (_: Exception) {
                publish("未能合并，草稿仍保留")
            }
        }
    }
}
