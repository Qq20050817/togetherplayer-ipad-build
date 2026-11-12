package dev.together.poc

import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class MovieMindIsolationInstrumentedTest {
    @Before
    fun startWithIndependentSyntheticAccountAndNoRoom() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        context.getSharedPreferences("moviemind", 0).edit().clear().commit()
        context.getSharedPreferences("MainActivity", 0).edit().clear().commit()
        context.getSharedPreferences(MainActivity::class.java.name, 0).edit().clear().commit()
        java.io.File(context.filesDir, "moviemind-outbox.json").delete()
    }

    @Test
    fun accountLoginRequiresEndingExistingViewingBinding() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val client = MovieMindClient(context)
        val server = MockWebServer()
        server.start()
        try {
            client.enabled = true
            client.watchEnabled = false
            val media = Any()
            assertTrue(client.bind("tmdb:99000009", "edition_account_123", 100000, media, 100000))
            val refused = CountDownLatch(1)
            val accepted = AtomicBoolean(true)
            client.login(server.url("/").toString(), "other_account", "test-only-password-123") {
                accepted.set(it)
                refused.countDown()
            }
            assertTrue(refused.await(10, TimeUnit.SECONDS))
            assertFalse(accepted.get())
            assertEquals(0, server.requestCount)
            assertEquals("tmdb:99000009", client.boundMovie)
            client.enabled = false
            assertEquals("", client.boundMovie)
            server.enqueue(
                MockResponse()
                    .setBody(
                        "{\"token\":\"native_other_token_123456789\",\"userId\":\"native_other_user_123\"}"
                    )
            )
            val allowed = CountDownLatch(1)
            client.login(server.url("/").toString(), "other_account", "test-only-password-123") {
                accepted.set(it)
                allowed.countDown()
            }
            assertTrue(allowed.await(10, TimeUnit.SECONDS))
            assertTrue(accepted.get())
            assertEquals("", client.boundMovie)
        } finally {
            client.close()
            server.shutdown()
        }
    }

    @Test
    fun pendingDraftSelectionSurvivesEarlierQueueRemoval() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        context.getSharedPreferences("moviemind", 0).edit().clear().commit()
        java.io.File(context.filesDir, "moviemind-outbox.json").delete()
        val client = MovieMindClient(context)
        client.enabled = false
        try {
            val saved = CountDownLatch(2)
            val durable = AtomicBoolean(true)
            for (movie in listOf("tmdb:99000004", "tmdb:99000005")) client.saveRating(
                movie,
                null,
                "synthetic draft",
                false,
                null,
            ) { ok ->
                if (!ok) durable.set(false)
                saved.countDown()
            }
            assertTrue(saved.await(10, TimeUnit.SECONDS))
            assertTrue(client.status, durable.get())
            val snapshot = CountDownLatch(1)
            val snapshotRows = AtomicReference<JSONArray>()
            client.pending { rows ->
                snapshotRows.set(rows)
                snapshot.countDown()
            }
            assertTrue(snapshot.await(10, TimeUnit.SECONDS))
            val rows = snapshotRows.get()
            assertEquals(2, rows.length())
            val ids = (0 until rows.length()).map { rows.getJSONObject(it).getString("queueId") }
            client.resolve(ids[0], false)
            client.resolve(ids[1], false)
            val checked = CountDownLatch(1)
            val remaining = java.util.concurrent.atomic.AtomicInteger(-1)
            client.pending { rows ->
                remaining.set(rows.length())
                checked.countDown()
            }
            assertTrue(checked.await(10, TimeUnit.SECONDS))
            assertEquals(0, remaining.get())
        } finally {
            client.close()
        }
    }

    @Test
    fun sharedOutboxSurvivesActivityRecreationAndKeepsAcceptingDrafts() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val client = MovieMindClient.shared(context)
        client.enabled = false
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            val first = CountDownLatch(1)
            val durable = AtomicBoolean(false)
            client.saveRating("tmdb:99000010", null, "first lifecycle draft", false, null) {
                durable.set(it)
                first.countDown()
            }
            assertTrue(first.await(10, TimeUnit.SECONDS))
            assertTrue(durable.get())
            scenario.recreate()
            scenario.onActivity { activity ->
                val delegate =
                    activity.javaClass
                        .getDeclaredField("movieMind\u0024delegate")
                        .apply { isAccessible = true }
                        .get(activity) as Lazy<*>
                assertSame(client, delegate.value)
            }
            val second = CountDownLatch(1)
            client.saveRating("tmdb:99000011", 7.5, "second lifecycle draft", false, null) {
                durable.set(it)
                second.countDown()
            }
            assertTrue(second.await(10, TimeUnit.SECONDS))
            assertTrue(durable.get())
            val loaded = CountDownLatch(1)
            val rows = AtomicReference<JSONArray>()
            client.pending {
                rows.set(it)
                loaded.countDown()
            }
            assertTrue(loaded.await(10, TimeUnit.SECONDS))
            assertEquals(2, rows.get().length())
            assertTrue(
                rows
                    .get()
                    .getJSONObject(0)
                    .getJSONObject("body")
                    .getJSONObject("record")
                    .isNull("rating")
            )
            for (i in 0 until rows.get().length()) client.resolve(
                rows.get().getJSONObject(i).getString("queueId"),
                false,
            )
            val cleared = CountDownLatch(1)
            val remaining = java.util.concurrent.atomic.AtomicInteger(-1)
            client.pending {
                remaining.set(it.length())
                cleared.countDown()
            }
            assertTrue(cleared.await(10, TimeUnit.SECONDS))
            assertEquals(0, remaining.get())
        }
    }

    @Test
    fun changingSourceClearsBindingEvenWhenObservationIsDisabled() {
        val client = MovieMindClient(InstrumentationRegistry.getInstrumentation().targetContext)
        try {
            client.enabled = true
            client.watchEnabled = false
            val original = Any()
            assertTrue(client.bind("tmdb:99000003", "edition_native_123", 100000, original, 100000))
            client.sample(Any(), 1000, 100000, false, 1.0, false, true, false)
            assertEquals("", client.boundMovie)
        } finally {
            client.enabled = false
            client.close()
        }
    }

    @Test
    fun offlineSettingsDoNotCreateRoomOrReplaceMedia() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val device = UiDevice.getInstance(instrumentation)
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            lateinit var client: MovieMindClient
            scenario.onActivity { a ->
                val playback =
                    a.javaClass.getDeclaredField("playback").apply { isAccessible = true }.get(a)
                        as CompatiblePlayback
                val before = playback.currentMediaItem
                client = MovieMindClient(a)
                client.enabled = false
                MovieMindDialog.show(a, client, before, playback.duration, false)
                assertSame(before, playback.currentMediaItem)
            }
            assertTrue(device.wait(Until.hasObject(By.text("MovieMind")), 10000))
            assertTrue(device.hasObject(By.text("实际播放区间记录（默认关闭）")))
            device.findObject(By.text("关闭")).click()
            scenario.onActivity { a ->
                assertNull(
                    a.javaClass.getDeclaredField("credentials").apply { isAccessible = true }.get(a)
                )
                val playback =
                    a.javaClass.getDeclaredField("playback").apply { isAccessible = true }.get(a)
                        as CompatiblePlayback
                assertNull(playback.currentMediaItem)
                client.close()
            }
        }
    }

    @Test
    fun malformedCatalogStaysIsolatedFromActivityAndMedia() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        context.getSharedPreferences("moviemind", 0).edit().clear().commit()
        java.io.File(context.filesDir, "moviemind-outbox.json").delete()
        val server = MockWebServer()
        server.start()
        val client = MovieMindClient(context)
        try {
            server.enqueue(
                MockResponse()
                    .setBody(
                        "{\"token\":\"native_test_token_123456789\",\"userId\":\"native_test_user_123\"}"
                    )
            )
            val login = CountDownLatch(1)
            val authenticated = AtomicBoolean(false)
            client.login(server.url("/").toString(), "native_test", "test-only-password-123") {
                authenticated.set(it)
                login.countDown()
            }
            assertTrue(login.await(10, TimeUnit.SECONDS))
            assertTrue(authenticated.get())
            server.takeRequest(5, TimeUnit.SECONDS)
            ActivityScenario.launch(MainActivity::class.java).use { scenario ->
                var before: Any? = null
                scenario.onActivity { a ->
                    val p =
                        a.javaClass
                            .getDeclaredField("playback")
                            .apply { isAccessible = true }
                            .get(a) as CompatiblePlayback
                    before = p.currentMediaItem
                }
                for (body in listOf("not JSON", "[{\"title\":\"incomplete metadata\"}]")) {
                    server.enqueue(MockResponse().setBody(body))
                    val returned = CountDownLatch(1)
                    val received = AtomicReference<String?>("not called")
                    client.get("movies") { value ->
                        received.set(value)
                        returned.countDown()
                    }
                    assertTrue(returned.await(10, TimeUnit.SECONDS))
                    assertNull(received.get())
                    server.takeRequest(5, TimeUnit.SECONDS)
                }
                scenario.onActivity { a ->
                    val p =
                        a.javaClass
                            .getDeclaredField("playback")
                            .apply { isAccessible = true }
                            .get(a) as CompatiblePlayback
                    assertSame(before, p.currentMediaItem)
                    assertNull(
                        a.javaClass
                            .getDeclaredField("credentials")
                            .apply { isAccessible = true }
                            .get(a)
                    )
                }
            }
        } finally {
            client.close()
            server.shutdown()
        }
    }

    @Test
    fun malformedSuccessKeepsRatingDraftAndStableRetryId() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        context.getSharedPreferences("moviemind", 0).edit().clear().commit()
        java.io.File(context.filesDir, "moviemind-outbox.json").delete()
        val server = MockWebServer()
        server.start()
        val client = MovieMindClient(context)
        client.enabled = true
        try {
            server.enqueue(
                MockResponse()
                    .setBody(
                        "{\"token\":\"native_test_token_123456789\",\"userId\":\"native_test_user_123\"}"
                    )
            )
            val login = CountDownLatch(1)
            val authenticated = AtomicBoolean(false)
            client.login(server.url("/").toString(), "native_test", "test-only-password-123") {
                authenticated.set(it)
                login.countDown()
            }
            assertTrue(login.await(10, TimeUnit.SECONDS))
            assertTrue(authenticated.get())
            server.takeRequest(5, TimeUnit.SECONDS)
            val requests = mutableListOf<JSONObject>()
            fun pendingCount(): Int {
                val latch = CountDownLatch(1)
                val count = java.util.concurrent.atomic.AtomicInteger(-1)
                client.pending {
                    count.set(it.length())
                    latch.countDown()
                }
                assertTrue(latch.await(10, TimeUnit.SECONDS))
                return count.get()
            }
            server.enqueue(MockResponse().setBody("not JSON"))
            client.saveRating("tmdb:99000006", null, "private retry fixture", false, null) {}
            requests.add(JSONObject(server.takeRequest(10, TimeUnit.SECONDS)!!.body.readUtf8()))
            assertEquals(1, pendingCount())
            server.enqueue(MockResponse().setBody("{\"movieId\":\"tmdb:1\",\"revision\":1}"))
            client.retry()
            requests.add(JSONObject(server.takeRequest(10, TimeUnit.SECONDS)!!.body.readUtf8()))
            assertEquals(1, pendingCount())
            server.enqueue(
                MockResponse()
                    .setBody(
                        JSONObject()
                            .put("movieId", "tmdb:99000006")
                            .put("revision", 1)
                            .put("mutationId", requests[0].getString("mutationId"))
                            .toString()
                    )
            )
            client.retry()
            requests.add(JSONObject(server.takeRequest(10, TimeUnit.SECONDS)!!.body.readUtf8()))
            assertEquals(0, pendingCount())
            assertEquals(1, requests.map { it.getString("mutationId") }.toSet().size)
            assertTrue(requests.all { it.getJSONObject("record").isNull("rating") })
        } finally {
            client.enabled = false
            client.close()
            server.shutdown()
        }
    }

    @Test
    fun ratingRetryKeepsOriginalMutationIdAfterServerError() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        // This test owns only the new client's isolated local storage.
        context.getSharedPreferences("moviemind", 0).edit().clear().commit()
        java.io.File(context.filesDir, "moviemind-outbox.json").delete()
        val server = MockWebServer()
        server.start()
        val client = MovieMindClient(context)
        client.enabled = true
        try {
            server.enqueue(
                MockResponse()
                    .setBody(
                        JSONObject()
                            .put("token", "native_test_token_123456789")
                            .put("userId", "native_test_user_123")
                            .toString()
                    )
            )
            val login = CountDownLatch(1)
            val authenticated = AtomicBoolean(false)
            client.login(server.url("/").toString(), "native_test", "test-only-password-123") {
                authenticated.set(it)
                login.countDown()
            }
            assertTrue(login.await(10, TimeUnit.SECONDS))
            assertTrue(client.status, authenticated.get())
            server.takeRequest(5, TimeUnit.SECONDS)
            server.enqueue(MockResponse().setResponseCode(503).setBody("{}"))
            client.saveRating("tmdb:99000002", 8.5, "synthetic private test note", false, null) {}
            val first = server.takeRequest(10, TimeUnit.SECONDS) ?: error("rating was not sent")
            assertEquals("/api/records/tmdb:99000002", first.path)
            val firstBody = JSONObject(first.body.readUtf8())
            server.enqueue(
                MockResponse()
                    .setBody(
                        JSONObject()
                            .put("movieId", "tmdb:99000002")
                            .put("revision", 1)
                            .put("mutationId", firstBody.getString("mutationId"))
                            .toString()
                    )
            )
            client.retry()
            val second =
                server.takeRequest(10, TimeUnit.SECONDS) ?: error("rating retry was not sent")
            val secondBody = JSONObject(second.body.readUtf8())
            assertEquals(firstBody.getString("mutationId"), secondBody.getString("mutationId"))
            assertEquals(8.5, secondBody.getJSONObject("record").getDouble("rating"), 0.0)
            val acknowledged = CountDownLatch(1)
            val pending = java.util.concurrent.atomic.AtomicInteger(-1)
            client.pending {
                pending.set(it.length())
                acknowledged.countDown()
            }
            assertTrue(acknowledged.await(10, TimeUnit.SECONDS))
            assertEquals(0, pending.get())
        } finally {
            client.close()
            server.shutdown()
        }
    }
}
