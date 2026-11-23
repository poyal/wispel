package app.wispel.phone

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class PhoneTest {
    private val ctx = InstrumentationRegistry.getInstrumentation().targetContext

    @Test
    fun idempotencyAndHistory() {
        val db = Events.get(ctx)
        val owner = UUID.randomUUID().toString()
        val e =
            json(
                "sourceId" to "a",
                "eventId" to "1",
                "sourceName" to "서브폰",
                "kind" to "sms",
                "occurredAt" to System.currentTimeMillis(),
            )
        assertTrue(db.remember(owner, e, true, true))
        db.done(owner, e)
        assertFalse(db.remember(owner, e, true, true))
        assertEquals(1, db.tiles(owner).single().count)
        db.clearHistory(owner)
        assertTrue(db.tiles(owner).isEmpty())
        assertFalse(db.remember(owner, e, true, true))
    }

    @Test
    fun tlsInviteValidation() {
        val raw =
            "wispel://pair?server=https%3A%2F%2F192.168.0.7%3A7443&pin=" +
                "a".repeat(64) +
                "&role=receive&code=" +
                "1".repeat(64)
        assertEquals("receive", Invite.parse(raw).role)
        assertTrue(runCatching { Invite.parse(raw.replace("https", "http")) }.isFailure)
    }

    @Test
    fun independentSourcesAndDisabledHistory() {
        val db = Events.get(ctx)
        val owner = UUID.randomUUID().toString()
        fun event(source: String) =
            json(
                "sourceId" to source,
                "eventId" to "same",
                "sourceName" to source,
                "kind" to "mail",
                "occurredAt" to System.currentTimeMillis(),
            )
        for (source in listOf("A", "B")) {
            val e = event(source)
            assertTrue(db.remember(owner, e, true, true))
            db.done(owner, e)
        }
        assertEquals(setOf("A", "B"), db.tiles(owner).map { it.source }.toSet())
        val hidden = event("C")
        assertFalse(db.remember(owner, hidden, false, false))
        db.done(owner, hidden)
        assertEquals(2, db.tiles(owner).size)
        assertFalse(db.remember(owner, hidden, true, true))
    }
}
