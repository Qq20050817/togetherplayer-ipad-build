package dev.together.poc

import androidx.test.core.app.ActivityScenario
import androidx.test.espresso.Espresso.onView
import androidx.test.espresso.action.ViewActions.*
import androidx.test.espresso.matcher.ViewMatchers.withContentDescription
import androidx.test.espresso.matcher.ViewMatchers.withText
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.UiScrollable
import androidx.test.uiautomator.UiSelector
import androidx.test.uiautomator.Until
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class MovieMindNativeJournalInstrumentedTest {
    private val context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Before
    fun resetSyntheticAppState() {
        context.getSharedPreferences("moviemind", 0).edit().clear().commit()
        File(context.filesDir, "moviemind-outbox.json").delete()
    }

    private fun login(client: MovieMindClient, server: MockWebServer) {
        val latch = CountDownLatch(1)
        val accepted = AtomicBoolean(false)
        client.login(server.url("/").toString(), "fixture_user", "synthetic-native-password-731") {
            accepted.set(it)
            latch.countDown()
        }
        assertTrue(latch.await(12, TimeUnit.SECONDS))
        assertTrue(client.status, accepted.get())
    }

    private fun receipt() =
        MockResponse()
            .setBody(
                "{\"userId\":\"fixture-native-user\",\"token\":\"synthetic-native-session-20261112\"}"
            )

    private fun mutation() =
        MovieMindJournalPolicy.record(
            "tmdb:100",
            null,
            "seen",
            null,
            "synthetic review",
            "",
            false,
            "",
            "",
            "",
            false,
            false,
        )

    @Test
    fun oldAccountScreenCannotSendRequestsForNewAccount() {
        val server = MockWebServer()
        server.start()
        val client = MovieMindClient(context)
        try {
            server.enqueue(receipt())
            login(client, server)
            val scope = client.workspaceScope
            context
                .getSharedPreferences("moviemind", 0)
                .edit()
                .putString("userId", "different-fixture-user")
                .commit()
            val checked = CountDownLatch(1)
            val refused = AtomicBoolean(false)
            client.api(scope, "records") { raw, _ ->
                refused.set(raw == null)
                checked.countDown()
            }
            assertTrue(checked.await(10, TimeUnit.SECONDS))
            assertTrue(refused.get())
            assertEquals(1, server.requestCount)
        } finally {
            client.close()
            server.shutdown()
        }
    }

    @Test
    fun manuallySavedUnratedReviewRetriesWithSameMutationWhenPlaybackHooksAreDisabled() {
        val server = MockWebServer()
        val attempts = AtomicInteger()
        val first = CountDownLatch(1)
        val identities = mutableListOf<String>()
        server.dispatcher =
            object : Dispatcher() {
                override fun dispatch(request: RecordedRequest): MockResponse {
                    if (request.path == "/api/auth/login") return receipt()
                    if (request.path == "/api/records/tmdb:100") {
                        val body = JSONObject(request.body.readUtf8())
                        identities.add(body.getString("mutationId"))
                        assertTrue(body.getJSONObject("record").isNull("rating"))
                        if (attempts.incrementAndGet() == 1) {
                            first.countDown()
                            return MockResponse().setResponseCode(503).setBody("{}")
                        }
                        return MockResponse()
                            .setBody(
                                JSONObject()
                                    .put("mutationId", body.getString("mutationId"))
                                    .put("movieId", "tmdb:100")
                                    .put("revision", 1)
                                    .toString()
                            )
                    }
                    return MockResponse().setResponseCode(404)
                }
            }
        server.start()
        val client = MovieMindClient(context)
        try {
            client.enabled = false
            client.watchEnabled = false
            client.ratingEnabled = false
            login(client, server)
            val saved = CountDownLatch(1)
            val accepted = AtomicBoolean(false)
            client.saveJournal(client.workspaceScope, mutation()) {
                accepted.set(it)
                saved.countDown()
            }
            assertTrue(saved.await(10, TimeUnit.SECONDS))
            assertTrue(accepted.get())
            assertTrue(first.await(10, TimeUnit.SECONDS))
            client.retry()
            val verified = CountDownLatch(1)
            val remaining = AtomicInteger(-1)
            client.pending { rows ->
                remaining.set(rows.length())
                verified.countDown()
            }
            assertTrue(verified.await(12, TimeUnit.SECONDS))
            assertEquals(0, remaining.get())
            assertEquals(2, attempts.get())
            assertEquals(identities.first(), identities.last())
        } finally {
            client.close()
            server.shutdown()
        }
    }

    @Test
    fun persistentScopedSessionIsRestoredByNewClientWithoutPassword() {
        val server = MockWebServer()
        server.start()
        val first = MovieMindClient(context)
        try {
            server.enqueue(receipt())
            login(first, server)
            val scope = first.workspaceScope
            first.close()
            val second = MovieMindClient(context)
            try {
                server.enqueue(MockResponse().setBody("[]"))
                val done = CountDownLatch(1)
                val success = AtomicBoolean(false)
                second.api(scope, "records") { raw, _ ->
                    success.set(raw == "[]")
                    done.countDown()
                }
                assertTrue(done.await(10, TimeUnit.SECONDS))
                assertTrue(success.get())
                server.takeRequest(2, TimeUnit.SECONDS)
                val request = server.takeRequest(2, TimeUnit.SECONDS)!!
                assertEquals(
                    "Bearer synthetic-native-session-20261112",
                    request.getHeader("Authorization"),
                )
                assertEquals(scope.account, request.getHeader("X-MovieMind-Account"))
            } finally {
                second.close()
            }
        } finally {
            server.shutdown()
        }
    }

    @Test
    fun nativeJournalWritesReviewEditsScoreAndShowsRecommendationsInsideActivity() {
        val server = MockWebServer()
        val work =
            JSONObject()
                .put("id", "manual:fixture_ui_seen")
                .put("title", "仅用于原生界面测试的电影")
                .put("year", 2020)
                .put("runtime", 95)
                .put("source", "manual")
        val next =
            JSONObject(work.toString())
                .put("id", "manual:fixture_ui_next")
                .put("title", "仅用于原生界面测试的下一部")
        val rows = linkedMapOf<String, JSONObject>()
        server.dispatcher =
            object : Dispatcher() {
                override fun dispatch(request: RecordedRequest): MockResponse {
                    val path = request.path.orEmpty()
                    if (path == "/api/auth/login") return receipt()
                    if (
                        request.getHeader("Authorization") !=
                            "Bearer synthetic-native-session-20261112"
                    )
                        return MockResponse().setResponseCode(401)
                    val reply: Any =
                        when (path) {
                            "/api/movies" -> JSONArray().put(work)
                            "/api/records" -> JSONArray(rows.values.toList())
                            "/api/me" ->
                                JSONObject()
                                    .put("userId", "fixture-native-user")
                                    .put("preferences", JSONObject())
                            "/api/pair" -> JSONObject().put("paired", false)
                            "/api/recommend" ->
                                JSONObject()
                                    .put(
                                        "candidates",
                                        JSONArray()
                                            .put(
                                                JSONObject()
                                                    .put("movie", next)
                                                    .put("label", "值得尝试")
                                                    .put("reasons", JSONArray().put("此内容仅用于界面测试"))
                                                    .put("gaps", JSONArray())
                                            ),
                                    )
                                    .put("pending", JSONArray())
                                    .put("hasMore", false)
                                    .put("mode", "rules")
                            "/api/records/manual:fixture_ui_seen" -> {
                                val body = JSONObject(request.body.readUtf8())
                                val record = body.getJSONObject("record")
                                val revision = (rows[work.getString("id")]?.optInt("revision") ?: 0)
                                if (body.getInt("expectedRevision") != revision)
                                    return MockResponse().setResponseCode(409)
                                record.put("revision", revision + 1)
                                rows[work.getString("id")] = record
                                JSONObject(record.toString())
                                    .put("mutationId", body.getString("mutationId"))
                            }
                            else -> return MockResponse().setResponseCode(404)
                        }
                    return MockResponse().setBody(reply.toString())
                }
            }
        server.start()
        val client = MovieMindClient(context)
        try {
            login(client, server)
            ActivityScenario.launch(MainActivity::class.java).use { scenario ->
                scenario.onActivity { MovieMindJournalDialog(it, client).show() }
                val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
                assertTrue(device.wait(Until.hasObject(By.text("添加已看电影")), 15000))
                onView(withText("添加已看电影")).perform(click())
                onView(withText("从已有电影资料选择")).perform(scrollTo(), click())
                onView(withText("仅用于原生界面测试的电影（2020）")).perform(click())
                onView(withContentDescription("私人评价（可选）"))
                    .perform(scrollTo(), replaceText("节奏紧张，喜欢反转。仅用于测试。"), closeSoftKeyboard())
                onView(withText("保存我的记录")).perform(click())
                assertTrue(device.wait(Until.hasObject(By.textContains("已看 · 未评分")), 15000))
                onView(withText(org.hamcrest.Matchers.containsString("已看 · 未评分")))
                    .perform(scrollTo(), click())
                onView(withContentDescription("个人评分")).perform(scrollTo(), click())
                val scoreList = UiScrollable(UiSelector().className("android.widget.ListView"))
                assertTrue(scoreList.scrollIntoView(UiSelector().text("8.5")))
                device.findObject(By.text("8.5")).click()
                onView(withText("保存我的记录")).perform(click())
                assertTrue(device.wait(Until.hasObject(By.textContains("已看 · 8.5 分")), 15000))
                onView(withText("推荐下一部")).perform(click())
                assertTrue(device.wait(Until.hasObject(By.text("按真实反馈推荐")), 15000))
                onView(withText("按真实反馈推荐")).perform(scrollTo(), click())
                assertTrue(device.wait(Until.hasObject(By.textContains("仅用于原生界面测试的下一部")), 15000))
                assertEquals(BuildConfig.APPLICATION_ID, device.currentPackageName)
                val saved = rows[work.getString("id")]!!
                assertEquals(8.5, saved.getDouble("rating"), 0.0)
                assertEquals("节奏紧张，喜欢反转。仅用于测试。", saved.getString("comment"))
            }
        } finally {
            client.close()
            server.shutdown()
        }
    }
}
