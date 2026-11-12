package dev.together.poc

import android.app.Activity
import android.app.AlertDialog
import android.net.Uri
import android.widget.*
import org.json.JSONArray
import org.json.JSONObject

internal object MovieMindDialog {
    fun show(
        a: Activity,
        client: MovieMindClient,
        currentSource: Any?,
        actualDuration: Long,
        isHost: Boolean,
    ) {
        val body =
            LinearLayout(a).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(30, 20, 30, 20)
            }
        fun text(value: String) =
            TextView(a).apply {
                text = value
                body.addView(this)
            }
        fun button(value: String, action: () -> Unit) =
            Button(a).apply {
                text = value
                body.addView(this)
                setOnClickListener { action() }
            }
        fun toggle(value: String, checked: Boolean, action: (Boolean) -> Unit) =
            Switch(a).apply {
                text = value
                isChecked = checked
                body.addView(this)
                setOnCheckedChangeListener { _, v -> action(v) }
            }
        text("独立档案与真实评分；房间号不授予档案权限。")
        toggle("启用 MovieMind", client.enabled) { client.enabled = it }
        toggle("选片推荐入口", client.recommendationEnabled) { client.recommendationEnabled = it }
        toggle("实际播放区间记录（默认关闭）", client.watchEnabled) { client.watchEnabled = it }
        toggle("可跳过的片尾评分卡", client.ratingEnabled) { client.ratingEnabled = it }
        val status = text(client.status)
        client.stateChanged = { if (!a.isFinishing) status.text = client.status }
        val origin =
            EditText(a).apply {
                hint = "MovieMind 服务 HTTPS 地址"
                setText(client.baseURL)
                body.addView(this)
            }
        val name =
            EditText(a).apply {
                hint = "独立账号用户名"
                body.addView(this)
            }
        val password =
            EditText(a).apply {
                hint = "密码"
                inputType = 129
                body.addView(this)
            }
        button("登录此服务") {
            val secret = password.text.toString()
            client.login(origin.text.toString(), name.text.toString(), secret) { accepted ->
                if (accepted) password.text.clear()
            }
        }
        button("我的电影、评分与推荐") { MovieMindJournalDialog(a, client).show() }
        button("确认当前影片的作品与版本") {
            if (currentSource == null) {
                status.text = "请先通过现有选片入口加载本机影片"
                return@button
            }
            client.get("movies") { raw ->
                if (raw == null) return@get
                val movies = JSONArray(raw)
                val names =
                    (0 until movies.length())
                        .map {
                            val m = movies.getJSONObject(it)
                            "${m.getString("title")} (${m.getInt("year")}) · ${m.getString("id")}"
                        }
                        .toTypedArray()
                if (names.isEmpty()) {
                    status.text = "先在 App 的电影档案中添加作品并登记剪辑版本"
                    return@get
                }
                AlertDialog.Builder(a)
                    .setTitle("人工确认同一作品")
                    .setItems(names) { _, index ->
                        val m = movies.getJSONObject(index)
                        client.get("editions?movieId=" + Uri.encode(m.getString("id"))) { versions
                            ->
                            if (versions == null) return@get
                            val editions = JSONArray(versions)
                            if (editions.length() == 0) {
                                status.text = "请在 App 电影档案中登记这部作品的准确剪辑片长"
                                return@get
                            }
                            val labels =
                                (0 until editions.length())
                                    .map {
                                        val e = editions.getJSONObject(it)
                                        "${e.getString("label")} · ${e.getLong("durationMs")/1000} 秒"
                                    }
                                    .toTypedArray()
                            AlertDialog.Builder(a)
                                .setTitle("确认剪辑版与本机片源")
                                .setItems(labels) { _, n ->
                                    val e = editions.getJSONObject(n)
                                    AlertDialog.Builder(a)
                                        .setTitle("绑定本机正在播放的影片？")
                                        .setMessage(
                                            "版本：${e.getString("label")}\n本机时长：${actualDuration/1000} 秒。不同剪辑版必须分开记录。\n${if(isHost)"如从双人推荐选片，请先确认双方已同意，再通过原有播放按钮开始。" else "绑定只记录你自己，不会替房主换片或开始播放。"}"
                                        )
                                        .setPositiveButton("我确认是同一剪辑") { _, _ ->
                                            if (
                                                !client.bind(
                                                    m.getString("id"),
                                                    e.getString("id"),
                                                    e.getLong("durationMs"),
                                                    currentSource,
                                                    actualDuration,
                                                )
                                            )
                                                status.text = "时长不一致或片源未加载，未绑定；请核对版本"
                                        }
                                        .setNegativeButton("取消", null)
                                        .show()
                                }
                                .setNegativeButton("取消", null)
                                .show()
                        }
                    }
                    .setNegativeButton("取消", null)
                    .show()
            }
        }
        if (client.ratingEnabled)
            button("评分 / 确认已看") {
                if (client.boundMovie.isBlank()) status.text = "请先确认当前作品与版本"
                else rating(a, client, client.boundMovie)
            }
        button("重试待同步内容") { client.retry() }
        button("核对待同步草稿") {
            client.pending { items ->
                val labels =
                    (0 until items.length())
                        .map {
                            val r = items.getJSONObject(it)
                            "${r.optString("path")} · ${r.optString("state")}"
                        }
                        .toTypedArray()
                AlertDialog.Builder(a)
                    .setTitle("待同步（仅本机）")
                    .setItems(labels) { _, n ->
                        val row = items.getJSONObject(n)
                        val draft = row.getJSONObject("body").optJSONObject("record")
                        if (draft == null) {
                            AlertDialog.Builder(a)
                                .setMessage("观影事件将使用原 ID 重试，不重复累计区间。")
                                .setPositiveButton("重试") { _, _ -> client.retry() }
                                .show()
                        } else
                            client.get("records") { raw ->
                                val latest = raw?.let { JSONArray(it) }
                                var current: JSONObject? = null
                                if (latest != null)
                                    for (i in 0 until latest.length()) {
                                        val r = latest.getJSONObject(i)
                                        if (r.optString("movieId") == draft.optString("movieId"))
                                            current = r
                                    }
                                AlertDialog.Builder(a)
                                    .setTitle("核对并发评分")
                                    .setMessage(
                                        "本机草稿评分：${draft.opt("rating")}\n服务器当前评分：${current?.opt("rating")}\n本机短评：${draft.optString("comment")}\n服务器短评：${current?.optString("comment")}\n只合并本次评分、已看状态和短评，其余字段保留最新内容。"
                                    )
                                    .setPositiveButton("确认采用我的草稿") { _, _ ->
                                        if (raw != null)
                                            client.resolve(
                                                row.getString("queueId"),
                                                true,
                                                current?.optInt("revision", 0) ?: 0,
                                            )
                                    }
                                    .setNeutralButton("明确丢弃草稿") { _, _ ->
                                        client.resolve(row.getString("queueId"), false)
                                    }
                                    .setNegativeButton("保留待核对", null)
                                    .show()
                            }
                    }
                    .setPositiveButton("关闭", null)
                    .show()
            }
        }
        val scroll = ScrollView(a).apply { addView(body) }
        val dialog =
            AlertDialog.Builder(a)
                .setTitle("MovieMind")
                .setView(scroll)
                .setPositiveButton("关闭", null)
                .create()
        dialog.setOnDismissListener { client.stateChanged = null }
        dialog.show()
    }

    fun rating(a: Activity, client: MovieMindClient, movie: String, session: String? = null) {
        if (a.isFinishing || !client.ratingEnabled) return
        client.get("records") { raw ->
            if (a.isFinishing) return@get
            var original: JSONObject? = null
            if (raw != null) {
                val rows = JSONArray(raw)
                for (i in 0 until rows.length()) {
                    val r = rows.getJSONObject(i)
                    if (r.optString("movieId") == movie) original = r
                }
            }
            val snapshot = original
            val body =
                LinearLayout(a).apply {
                    orientation = LinearLayout.VERTICAL
                    setPadding(30, 20, 30, 20)
                }
            body.addView(TextView(a).apply { text = "作品 ID：$movie" })
            body.addView(TextView(a).apply { text = "可能已看完。是否已看和评分都由你确认；技术故障不会自动变成弃看或差评。" })
            val scores =
                Spinner(a).apply {
                    adapter =
                        ArrayAdapter(
                            a,
                            android.R.layout.simple_spinner_dropdown_item,
                            listOf("未评分") + (0..20).map { (it / 2.0).toString() },
                        )
                    if (snapshot != null && !snapshot.isNull("rating"))
                        setSelection((snapshot.getDouble("rating") * 2).toInt() + 1)
                    body.addView(this)
                }
            val comment =
                EditText(a).apply {
                    hint = "可选私人短评"
                    maxLines = 4
                    setText(snapshot?.optString("comment").orEmpty())
                    body.addView(this)
                }
            val together =
                CheckBox(a).apply {
                    text = "这次是共同观看"
                    isChecked = snapshot?.optBoolean("together") == true
                    body.addView(this)
                }
            val dialog =
                AlertDialog.Builder(a)
                    .setTitle("确认已看与评分（可跳过）")
                    .setView(body)
                    .setPositiveButton("确认已看并保存", null)
                    .setNegativeButton("暂时跳过", null)
                    .setNeutralButton("未看完") { _, _ -> client.completion(session, "rejected") }
                    .create()
            dialog.setOnShowListener {
                dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                    dialog.getButton(AlertDialog.BUTTON_POSITIVE).isEnabled = false
                    client.saveRating(
                        movie,
                        if (scores.selectedItemPosition == 0) null
                        else (scores.selectedItemPosition - 1) / 2.0,
                        comment.text.toString(),
                        together.isChecked,
                        snapshot,
                    ) { saved ->
                        dialog.getButton(AlertDialog.BUTTON_POSITIVE).isEnabled = true
                        if (saved) {
                            client.completion(session, "confirmed")
                            dialog.dismiss()
                        } else Toast.makeText(a, client.status, Toast.LENGTH_LONG).show()
                    }
                }
            }
            dialog.show()
        }
    }
}
