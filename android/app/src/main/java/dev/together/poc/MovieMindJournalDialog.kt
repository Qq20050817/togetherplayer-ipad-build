package dev.together.poc

import android.app.Activity
import android.app.AlertDialog
import android.app.Dialog
import android.os.Handler
import android.os.Looper
import android.text.Editable
import android.text.TextWatcher
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.*
import java.util.Locale
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject

/** Native account-scoped pages. No browser, WebView, media path or playback operation. */
internal class MovieMindJournalDialog(
    private val activity: Activity,
    private val client: MovieMindClient,
) {
    private val scope = client.workspaceScope
    private val dialog = Dialog(activity)
    private lateinit var body: LinearLayout
    private var page = "library"
    private var epoch = 0
    private var movies = JSONArray()
    private var records = JSONArray()
    private var preferences = JSONObject()
    private var paired = false
    private var wishlist = JSONArray()
    private var votes = JSONObject()
    private var recommendations: JSONObject? = null
    private var activeQuery = JSONObject()
    private var invite = ""
    private var message = ""

    fun show() {
        val outer = column()
        text(outer, "MovieMind · 我的电影", 22f)
        val navigation = LinearLayout(activity)
        for ((key, label) in listOf("library" to "我的电影", "recommend" to "推荐下一部", "pair" to "一起选")) {
            val button =
                Button(activity).apply {
                    text = label
                    setOnClickListener {
                        page = key
                        load()
                    }
                }
            navigation.addView(
                button,
                LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f),
            )
        }
        outer.addView(navigation)
        body = column()
        val scroll = ScrollView(activity).apply { addView(body) }
        outer.addView(scroll, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
        button(outer, "返回播放器") { dialog.dismiss() }
        dialog.setContentView(outer)
        dialog.setOnDismissListener { epoch++ }
        dialog.show()
        dialog.window?.setLayout(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT,
        )
        dialog.window?.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
        load()
    }

    private fun column() =
        LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(24, 12, 24, 12)
        }

    private fun text(parent: LinearLayout, value: String, size: Float = 15f) =
        TextView(activity).apply {
            text = value
            textSize = size
            setPadding(0, 8, 0, 8)
            parent.addView(this)
        }

    private fun button(parent: LinearLayout, label: String, action: () -> Unit) =
        Button(activity).apply {
            text = label
            parent.addView(this)
            setOnClickListener { action() }
        }

    private fun field(
        parent: LinearLayout,
        label: String,
        value: String = "",
        multiline: Boolean = false,
        numeric: Boolean = false,
    ): EditText {
        text(parent, label)
        return EditText(activity).apply {
            hint = label
            contentDescription = label
            setText(value)
            inputType = if (numeric) 8194 else if (multiline) 131073 else 1
            if (multiline) minLines = 3
            parent.addView(this)
        }
    }

    private fun toggle(parent: LinearLayout, label: String, value: Boolean) =
        Switch(activity).apply {
            text = label
            isChecked = value
            parent.addView(this)
        }

    private fun spinner(
        parent: LinearLayout,
        label: String,
        labels: List<String>,
        selection: Int,
    ): Spinner {
        text(parent, label)
        return Spinner(activity).apply {
            contentDescription = label
            adapter = ArrayAdapter(activity, android.R.layout.simple_spinner_dropdown_item, labels)
            setSelection(selection.coerceAtLeast(0))
            parent.addView(this)
        }
    }

    private fun list(array: JSONArray): List<JSONObject> =
        (0 until array.length()).map { array.getJSONObject(it) }

    private fun record(id: String): JSONObject? =
        list(records).firstOrNull { it.optString("movieId") == id }

    private fun valid() =
        dialog.isShowing && !activity.isFinishing && scope == client.workspaceScope

    private fun api(
        path: String,
        payload: JSONObject? = null,
        method: String = "GET",
        done: (String) -> Unit,
    ) {
        val started = epoch
        client.api(scope, path, payload, method) { raw, error ->
            if (!valid() || started != epoch) return@api
            if (raw == null) {
                message = error ?: "暂时无法读取电影资料"
                render()
                return@api
            }
            runCatching { done(raw) }
                .onFailure {
                    message = "电影资料格式异常，原内容保留"
                    render()
                }
        }
    }

    private fun load() {
        epoch++
        body.removeAllViews()
        if (!scope.configured) {
            text(body, "请先返回 MovieMind 账号页，用自己的账号登录。")
            return
        }
        text(body, "正在读取电影档案…")
        api("movies") { works ->
            movies = JSONArray(works)
            api("records") { rows ->
                records = JSONArray(rows)
                api("me") { me ->
                    preferences = JSONObject(me).optJSONObject("preferences") ?: JSONObject()
                    api("pair") { pairing ->
                        paired = JSONObject(pairing).optBoolean("paired")
                        if (!paired) {
                            recommendations = null
                            wishlist = JSONArray()
                            votes = JSONObject()
                            render()
                        } else
                            api("pair/wishlist") { wishes ->
                                wishlist = JSONArray(wishes)
                                api("pair/votes") { choices ->
                                    votes = JSONObject(choices)
                                    render()
                                }
                            }
                    }
                }
            }
        }
    }

    private fun render() {
        if (!dialog.isShowing) return
        body.removeAllViews()
        if (scope != client.workspaceScope) {
            text(body, "账号或服务已改变，请关闭后重新打开电影档案")
            return
        }
        if (message.isNotBlank()) {
            text(body, message)
            button(body, "刷新核对") {
                message = ""
                load()
            }
        }
        when (page) {
            "library" -> library()
            "recommend" -> discover()
            "pair" -> pairing()
        }
        text(body, client.status)
        button(body, "重试待同步评分") {
            client.retry()
            Handler(Looper.getMainLooper())
                .postDelayed(
                    {
                        if (valid()) {
                            message = client.status
                            render()
                        }
                    },
                    500,
                )
        }
        button(body, "核对待同步草稿") { pending() }
    }

    private fun library() {
        text(body, "各自记录已看电影、评分和私人评价，再按真实反馈推荐下一部。", 18f)
        button(body, "添加已看电影") { edit(null, "seen") }
        button(body, "添加想看候选") { edit(null, "want") }
        button(body, "我的口味与雷区") { editPreferences() }
        val search = field(body, "搜索片名、译名或标准 ID")
        val all = toggle(body, "显示全部电影资料", false)
        val rows = column()
        body.addView(rows)
        fun draw() {
            rows.removeAllViews()
            val query = search.text.toString().trim()
            val filtered =
                list(movies).filter { work ->
                    val own = record(work.getString("id"))
                    val haystack =
                        work.optString("title") +
                            " " +
                            work.optString("originalTitle") +
                            " " +
                            work.getString("id") +
                            " " +
                            work.optJSONArray("aliases")?.toString().orEmpty()
                    (all.isChecked || own != null && !own.optBoolean("deleted")) &&
                        haystack.contains(query, true)
                }
            if (filtered.isEmpty()) text(rows, "还没有匹配的记录，可以添加电影或显示全部资料后选择已有作品。")
            for (work in filtered) {
                val own = record(work.getString("id"))
                val label =
                    "${work.getString("title")} · ${work.getInt("year")}" +
                        if (own == null || own.optBoolean("deleted")) "\n添加到我的档案"
                        else
                            "\n${statusName(own.optString("status"))} · ${score(own)}\n${own.optString("comment")}"
                                .take(260)
                button(rows, label) { edit(work, "seen") }
            }
        }
        search.addTextChangedListener(
            object : TextWatcher {
                override fun beforeTextChanged(
                    s: CharSequence?,
                    start: Int,
                    count: Int,
                    after: Int,
                ) {}

                override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {
                    draw()
                }

                override fun afterTextChanged(s: Editable?) {}
            }
        )
        all.setOnCheckedChangeListener { _, _ -> draw() }
        draw()
    }

    private fun statusName(value: String): String =
        MovieMindJournalPolicy.statusNames.getOrNull(MovieMindJournalPolicy.statuses.indexOf(value))
            ?: value

    private fun score(row: JSONObject): String =
        if (row.isNull("rating")) "未评分"
        else String.format(Locale.ROOT, "%.1f 分", row.optDouble("rating"))

    private fun tags(row: JSONObject?, name: String): String =
        row?.optJSONArray(name)
            ?.let { values -> (0 until values.length()).joinToString("，") { values.getString(it) } }
            .orEmpty()

    private fun edit(work: JSONObject?, initialStatus: String) {
        val fields = column()
        var selected = work
        var original = work?.let { record(it.getString("id")) }
        val manualId = "manual:" + UUID.randomUUID().toString()
        val title = field(fields, "中文片名（必填）", work?.optString("title").orEmpty())
        val year =
            field(fields, "年份（必填）", work?.optInt("year")?.toString().orEmpty(), numeric = true)
        val originalTitle = field(fields, "原名（可选）", work?.optString("originalTitle").orEmpty())
        val runtime =
            field(
                fields,
                "片长分钟（未知可留空）",
                work?.optInt("runtime")?.takeIf { it > 0 }?.toString().orEmpty(),
                numeric = true,
            )
        val id = field(fields, "已有 TMDB/IMDb 标准 ID（可选）", work?.optString("id").orEmpty())
        val present = field(fields, "我核实出现的类型或元素（可选，逗号分隔）")
        val absent = field(fields, "有证据确认未出现的内容（可选）")
        text(fields, "同一电影优先选择已有资料。未填写的关键内容保持未知，不凭简介保证没有血腥或突脸。")
        fun disableMetadata() {
            for (view in listOf(title, year, originalTitle, runtime, id, present, absent)) view
                .isEnabled = false
        }
        if (work != null) disableMetadata()
        var selectExisting: (() -> Unit)? = null
        if (work == null) button(fields, "从已有电影资料选择") { selectExisting?.invoke() }
        val status =
            spinner(
                fields,
                "观看状态",
                MovieMindJournalPolicy.statusNames,
                MovieMindJournalPolicy.statuses.indexOf(
                    original?.optString("status") ?: initialStatus
                ),
            )
        val scores = listOf("未评分") + (0..20).map { String.format(Locale.ROOT, "%.1f", it / 2.0) }
        val rating =
            spinner(
                fields,
                "个人评分",
                scores,
                if (original == null || original!!.isNull("rating")) 0
                else (original!!.getDouble("rating") * 2).toInt() + 1,
            )
        val comment =
            field(fields, "私人评价（可选）", original?.optString("comment").orEmpty(), multiline = true)
        val date = field(fields, "观影日期（可选，YYYY-MM-DD）", original?.optString("watchedOn").orEmpty())
        val together = toggle(fields, "这次是共同观看", original?.optBoolean("together") ?: false)
        val favorite = toggle(fields, "收藏电影", original?.optBoolean("favorite") ?: false)
        val shared = toggle(fields, "主动共享这部想看电影", original?.optBoolean("sharedWish") ?: false)
        val likes = field(fields, "我喜欢的元素，逗号分隔", tags(original, "likes"))
        val dislikes = field(fields, "我不喜欢的元素，逗号分隔", tags(original, "dislikes"))
        val experience = field(fields, "体验描述，逗号分隔", tags(original, "experience"))
        text(fields, "体验和技术故障不会自动变成评分，双方各自保存自己的评价。")
        val feedback = text(fields, "")
        val editor =
            AlertDialog.Builder(activity)
                .setTitle("记录与评价")
                .setView(ScrollView(activity).apply { addView(fields) })
                .setPositiveButton("保存我的记录", null)
                .setNegativeButton("取消", null)
                .create()
        selectExisting = {
            AlertDialog.Builder(activity)
                .setTitle("确认同一作品")
                .setItems(
                    list(movies)
                        .map { "${it.getString("title")}（${it.getInt("year")}）" }
                        .toTypedArray()
                ) { _, which ->
                    selected = movies.getJSONObject(which)
                    original = record(selected!!.getString("id"))
                    title.setText(selected!!.getString("title"))
                    year.setText(selected!!.getInt("year").toString())
                    id.setText(selected!!.getString("id"))
                    disableMetadata()
                    status.setSelection(
                        MovieMindJournalPolicy.statuses
                            .indexOf(original?.optString("status") ?: initialStatus)
                            .coerceAtLeast(0)
                    )
                    rating.setSelection(
                        if (original == null || original!!.isNull("rating")) 0
                        else (original!!.getDouble("rating") * 2).toInt() + 1
                    )
                    comment.setText(original?.optString("comment").orEmpty())
                    date.setText(original?.optString("watchedOn").orEmpty())
                    together.isChecked = original?.optBoolean("together") ?: false
                    favorite.isChecked = original?.optBoolean("favorite") ?: false
                    shared.isChecked = original?.optBoolean("sharedWish") ?: false
                    likes.setText(tags(original, "likes"))
                    dislikes.setText(tags(original, "dislikes"))
                    experience.setText(tags(original, "experience"))
                }
                .show()
        }
        fun save(deleted: Boolean) {
            if (!valid()) {
                feedback.text = "账号或服务已改变，原输入保留"
                return
            }
            val movieId = selected?.getString("id") ?: id.text.toString().ifBlank { manualId }
            val mutation =
                runCatching {
                        MovieMindJournalPolicy.record(
                            movieId,
                            original,
                            MovieMindJournalPolicy.statuses[status.selectedItemPosition],
                            if (rating.selectedItemPosition == 0) null
                            else (rating.selectedItemPosition - 1) / 2.0,
                            comment.text.toString(),
                            date.text.toString(),
                            together.isChecked,
                            likes.text.toString(),
                            dislikes.text.toString(),
                            experience.text.toString(),
                            favorite.isChecked,
                            shared.isChecked,
                            deleted,
                        )
                    }
                    .getOrElse {
                        feedback.text = "请核对日期、半分评分和标签，评价过长时请缩短后保存"
                        return
                    }
            val saveButton = editor.getButton(AlertDialog.BUTTON_POSITIVE)
            saveButton.isEnabled = false
            fun enqueue() {
                client.saveJournal(scope, mutation) { accepted ->
                    if (!editor.isShowing) return@saveJournal
                    saveButton.isEnabled = true
                    if (accepted) {
                        editor.dismiss()
                        message = client.status
                        load()
                    } else feedback.text = client.status
                }
            }
            if (selected != null) {
                enqueue()
                return
            }
            val metadata =
                runCatching {
                        MovieMindJournalPolicy.work(
                            movieId,
                            title.text.toString(),
                            originalTitle.text.toString(),
                            year.text.toString().toInt(),
                            runtime.text.toString().ifBlank { "0" }.toInt(),
                            present.text.toString(),
                            absent.text.toString(),
                        )
                    }
                    .getOrElse {
                        saveButton.isEnabled = true
                        feedback.text = "请填写片名、有效年份和片长，并核对内容标签"
                        return
                    }
            client.api(scope, "movies/$movieId", metadata, "PUT") { raw, error ->
                if (!editor.isShowing) return@api
                saveButton.isEnabled = true
                if (raw == null) {
                    feedback.text = error
                    return@api
                }
                val saved =
                    runCatching { JSONObject(raw).also { require(it.getString("id") == movieId) } }
                        .getOrNull()
                if (saved == null) {
                    feedback.text = "资料回执异常，请刷新核对；原输入保留"
                    return@api
                }
                selected = saved
                disableMetadata()
                enqueue()
            }
        }
        if (original != null)
            button(fields, "撤回这条观影记录") {
                AlertDialog.Builder(activity)
                    .setTitle("确认撤回？")
                    .setMessage("保留电影资料和修订历史，不再用这条记录学习口味。")
                    .setNegativeButton("取消", null)
                    .setPositiveButton("确认撤回") { _, _ -> save(true) }
                    .show()
            }
        if (work != null) button(fields, "登记这部电影的剪辑版本") { createEdition(work) }
        editor.setOnShowListener {
            editor.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener { save(false) }
        }
        editor.show()
    }

    private fun editPreferences() {
        val form = column()
        text(form, "只修改你自己的口味，不给另一位观众套用。硬雷区未知内容会进入待核实。")
        val likes = field(form, "喜欢的元素，逗号分隔", tags(preferences, "likes"))
        val avoid = field(form, "硬性避开的内容，逗号分隔", tags(preferences, "hardAvoid"))
        val anchor =
            field(
                form,
                "我的评分锚点（可选，0到10）",
                if (preferences.isNull("ratingAnchor")) ""
                else preferences.optDouble("ratingAnchor").toString(),
                numeric = true,
            )
        val status = text(form, "")
        val editor =
            AlertDialog.Builder(activity)
                .setTitle("我的口味与雷区")
                .setView(ScrollView(activity).apply { addView(form) })
                .setPositiveButton("保存", null)
                .setNegativeButton("取消", null)
                .create()
        editor.setOnShowListener {
            editor.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                val value = anchor.text.toString().takeIf { it.isNotBlank() }?.toDoubleOrNull()
                if (
                    anchor.text.isNotBlank() &&
                        (value == null || !value.isFinite() || value !in 0.0..10.0)
                ) {
                    status.text = "评分锚点需在0到10之间"
                    return@setOnClickListener
                }
                val payload =
                    JSONObject()
                        .put("likes", JSONArray(MovieMindJournalPolicy.tags(likes.text.toString())))
                        .put(
                            "hardAvoid",
                            JSONArray(MovieMindJournalPolicy.tags(avoid.text.toString())),
                        )
                        .put("ratingAnchor", value ?: JSONObject.NULL)
                        .put("revision", preferences.optInt("revision"))
                client.api(scope, "preferences", payload, "PUT") { raw, error ->
                    if (raw == null) status.text = error
                    else {
                        editor.dismiss()
                        load()
                    }
                }
            }
        }
        editor.show()
    }

    private fun discover() {
        text(body, "根据真实评分、评价元素和个人偏好推荐；已看默认排除。", 18f)
        text(body, "候选来自服务中已添加的电影资料，可以先添加想看电影。资料少时保守推荐，不显示预测分。")
        val minutes =
            field(
                body,
                "最长片长（分钟，可选）",
                activeQuery.optInt("maxMinutes").takeIf { it > 0 }?.toString().orEmpty(),
                numeric = true,
            )
        val mood = field(body, "这次想看的元素，逗号分隔", tags(activeQuery, "mood"))
        val avoid = field(body, "这次避开的内容，逗号分隔", tags(activeQuery, "tonightAvoid"))
        val rewatch = toggle(body, "这次愿意重看", activeQuery.optBoolean("rewatch"))
        val pair = if (paired) toggle(body, "同时满足我们两个人", activeQuery.optBoolean("pair")) else null
        val unknown = toggle(body, "仅本次接受雷区信息未知", activeQuery.optBoolean("acceptUnknown"))
        button(body, "按真实反馈推荐") {
            val duration = minutes.text.toString().ifBlank { "0" }.toIntOrNull()
            if (duration == null || duration !in 0..1000) {
                message = "请填写0到1000之间的分钟数"
                render()
                return@button
            }
            val query =
                JSONObject()
                    .put("pair", pair?.isChecked ?: false)
                    .put("rewatch", rewatch.isChecked)
                    .put("acceptUnknown", unknown.isChecked)
                    .put("maxMinutes", duration)
                    .put("mood", JSONArray(MovieMindJournalPolicy.tags(mood.text.toString())))
                    .put(
                        "tonightAvoid",
                        JSONArray(MovieMindJournalPolicy.tags(avoid.text.toString())),
                    )
                    .put("offset", 0)
            recommend(query, false)
        }
        recommendations?.let { result ->
            if (result.optString("mode") == "vote") text(body, "双方评价资料还不够，先投票选择愿意看、都可以或跳过。")
            val candidates = result.optJSONArray("candidates") ?: JSONArray()
            if (candidates.length() == 0) text(body, "暂无符合条件的候选，可以添加想看电影或调整本次条件。")
            for (candidate in list(candidates)) candidate(candidate, false)
            if (result.optBoolean("hasMore"))
                button(body, "查看更多候选") {
                    recommend(
                        JSONObject(activeQuery.toString())
                            .put("offset", activeQuery.optInt("offset") + 5),
                        true,
                    )
                }
            val pending = result.optJSONArray("pending") ?: JSONArray()
            if (pending.length() > 0)
                button(body, "待核实内容 · ${pending.length()} 部") {
                    val content = column()
                    for (candidate in list(pending)) {
                        text(content, candidate.getJSONObject("movie").getString("title"), 18f)
                        text(content, tags(candidate, "gaps"))
                    }
                    AlertDialog.Builder(activity)
                        .setTitle("关键内容资料未知")
                        .setView(ScrollView(activity).apply { addView(content) })
                        .setPositiveButton("保留严格过滤", null)
                        .show()
                }
        }
    }

    private fun recommend(query: JSONObject, more: Boolean) {
        api("recommend", query, "POST") { raw ->
            val result = JSONObject(raw)
            if (more && recommendations != null) {
                val old = recommendations!!.getJSONArray("candidates")
                val ids = list(old).map { it.getJSONObject("movie").getString("id") }.toSet()
                for (item in list(result.getJSONArray("candidates"))) if (
                    item.getJSONObject("movie").getString("id") !in ids
                )
                    old.put(item)
                result.put("candidates", old)
            }
            recommendations = result
            activeQuery = JSONObject(query.toString())
            message = ""
            render()
        }
    }

    private fun candidate(candidate: JSONObject, pending: Boolean) {
        val movie = candidate.getJSONObject("movie")
        text(body, "${movie.getString("title")} · ${movie.getInt("year")}", 19f)
        text(body, candidate.optString("label"))
        text(body, tags(candidate, "reasons"))
        text(body, tags(candidate, "gaps"))
        button(body, "加入想看 · ${movie.getString("title")}") { edit(movie, "want") }
        if (activeQuery.optBoolean("pair") && !pending) {
            for ((value, label) in listOf("yes" to "愿意看", "maybe" to "都可以", "skip" to "跳过")) button(
                body,
                label,
            ) {
                api(
                    "pair/vote",
                    JSONObject()
                        .put("movieId", movie.getString("id"))
                        .put("value", value)
                        .put("acceptUnknown", activeQuery.optBoolean("acceptUnknown"))
                        .put("rewatch", activeQuery.optBoolean("rewatch")),
                    "POST",
                ) {
                    api("pair/votes") { raw ->
                        votes = JSONObject(raw)
                        render()
                    }
                }
            }
            text(body, votesLabel(movie.getString("id")))
        }
    }

    private fun voteName(value: String) =
        mapOf("yes" to "愿意看", "maybe" to "都可以", "skip" to "跳过")[value.substringBefore('_')]
            ?: "尚未投票"

    private fun votesLabel(id: String): String {
        val value = votes.optJSONObject(id) ?: JSONObject()
        return "我的选择：${voteName(value.optString("mine"))} · 对方：${voteName(value.optString("partner"))}"
    }

    private fun pairing() {
        text(body, "双方各自记录和评分，只共享主动公开的共同想看和候选投票。", 18f)
        if (!paired) {
            button(body, "我同意配对，生成10分钟邀请") {
                api("invites", JSONObject(), "POST") { raw ->
                    invite = JSONObject(raw).getString("token")
                    render()
                }
            }
            if (invite.isNotBlank()) {
                text(body, invite).setTextIsSelectable(true)
                button(body, "撤销我的邀请") {
                    api("invites", method = "DELETE") {
                        invite = ""
                        render()
                    }
                }
            }
            val token = field(body, "粘贴对方的邀请凭证")
            button(body, "核对并接受邀请") {
                if (token.text.isBlank()) return@button
                AlertDialog.Builder(activity)
                    .setTitle("确认双方同意配对？")
                    .setMessage("个人完整历史、具体评分和私人短评仍独立保存。")
                    .setNegativeButton("取消", null)
                    .setPositiveButton("确认接受") { _, _ ->
                        api(
                            "pair/accept",
                            JSONObject().put("token", token.text.toString()).put("confirm", true),
                            "POST",
                        ) {
                            invite = ""
                            load()
                        }
                    }
                    .show()
            }
        } else {
            text(body, "已配对 · 共同想看", 20f)
            for (work in list(wishlist)) {
                text(body, work.getString("title"))
                text(body, votesLabel(work.getString("id")))
            }
            if (wishlist.length() == 0) text(body, "双方都将同一电影设为想看并主动共享后，会显示在这里。")
            text(body, "双方同意后，由房主在原有选片入口确认片源和播放，不自动换片。")
            button(body, "解除配对") {
                AlertDialog.Builder(activity)
                    .setTitle("解除配对？")
                    .setMessage("共同选片权限立即结束，个人记录和评价保留。")
                    .setNegativeButton("取消", null)
                    .setPositiveButton("解除配对") { _, _ ->
                        api("pair", method = "DELETE") {
                            epoch++
                            paired = false
                            recommendations = null
                            votes = JSONObject()
                            wishlist = JSONArray()
                            render()
                        }
                    }
                    .show()
            }
        }
    }

    private fun createEdition(work: JSONObject) {
        val form = column()
        text(form, work.getString("title"))
        text(form, "不同清晰度可用同一剪辑版本；剪辑不同请分别登记。")
        val label = field(form, "版本名称，例如院线版")
        val seconds = field(form, "准确片长（秒，可带小数）", numeric = true)
        val message = text(form, "")
        val id = UUID.randomUUID().toString()
        val editor =
            AlertDialog.Builder(activity)
                .setTitle("确认剪辑版本")
                .setView(form)
                .setPositiveButton("确认保存", null)
                .setNegativeButton("取消", null)
                .create()
        editor.setOnShowListener {
            editor.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                val duration = seconds.text.toString().toDoubleOrNull()
                if (
                    duration == null ||
                        !duration.isFinite() ||
                        duration <= 0 ||
                        duration > 86400 ||
                        label.text.isBlank()
                ) {
                    message.text = "请填写版本名称和有效片长"
                    return@setOnClickListener
                }
                client.api(
                    scope,
                    "editions",
                    JSONObject()
                        .put("id", id)
                        .put("movieId", work.getString("id"))
                        .put("label", label.text.toString())
                        .put("durationMs", (duration * 1000).toLong()),
                    "POST",
                ) { raw, error ->
                    if (raw == null) message.text = error
                    else {
                        editor.dismiss()
                        this.message = "版本已保存，返回作品绑定入口确认本机影片"
                        render()
                    }
                }
            }
        }
        editor.show()
    }

    private fun pending() {
        client.pending { rows ->
            if (!valid()) return@pending
            if (rows.length() == 0) {
                message = "当前没有待同步草稿"
                render()
                return@pending
            }
            AlertDialog.Builder(activity)
                .setTitle("核对本机草稿")
                .setItems(
                    list(rows)
                        .map {
                            (if (it.optString("state") == "conflict") "并发冲突 · " else "待同步 · ") +
                                it.optString("path")
                        }
                        .toTypedArray()
                ) { _, index ->
                    val item = rows.getJSONObject(index)
                    val draft = item.getJSONObject("body").optJSONObject("record")
                    if (draft == null) {
                        client.retry()
                        return@setItems
                    }
                    api("records") { raw ->
                        val latest =
                            list(JSONArray(raw)).firstOrNull {
                                it.optString("movieId") == draft.getString("movieId")
                            }
                        AlertDialog.Builder(activity)
                            .setTitle("核对评分与评价")
                            .setMessage(
                                "本机：${score(draft)}\n${draft.optString("comment")}\n当前：${latest?.let { score(it) } ?: "未记录"}\n${latest?.optString("comment").orEmpty()}"
                            )
                            .setNegativeButton("保留草稿", null)
                            .setNeutralButton("明确丢弃") { _, _ ->
                                client.resolve(item.getString("queueId"), false)
                            }
                            .setPositiveButton("采用我的草稿") { _, _ ->
                                client.resolve(
                                    item.getString("queueId"),
                                    true,
                                    latest?.optInt("revision") ?: 0,
                                )
                            }
                            .show()
                    }
                }
                .setNegativeButton("关闭", null)
                .show()
        }
    }
}
