package app.wispel.phone

import org.junit.Assert.*
import org.junit.Test

class RulesTest {
    @Test
    fun missedCallOnlyOnFinalLine() {
        assertEquals("missedCall", Rules.classify("call", listOf("이름\r\n부재중 전화")))
        assertEquals("call", Rules.classify("call", listOf("부재중 전화 안내")))
        assertEquals("sms", Rules.classify("sms", listOf("부재중 전화")))
    }

    @Test
    fun timeBounds() {
        assertFalse(Rules.quiet(1, 60000))
        assertTrue(Rules.quiet(1, 60001))
        assertTrue(Rules.valid(5, Rules.DAY + 4))
        assertFalse(Rules.valid(5, Rules.DAY + 5))
    }

    @Test
    fun allKindsHaveLabels() {
        assertEquals(6, Rules.labels.size)
        assertEquals(6, Rules.labels.values.distinct().size)
    }
}
