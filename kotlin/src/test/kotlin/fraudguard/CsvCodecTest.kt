package fraudguard

import fraudguard.csv.CsvCodec
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull

class CsvCodecTest {
    @Test
    fun `quoted commas and escaped quotes are parsed`() {
        val parsed = CsvCodec.parseText("a,b,c\n1,\"two, parts\",\"say \"\"hello\"\"\"\n")
        assertNull(parsed.errorMessage)
        assertEquals(listOf("1", "two, parts", "say \"hello\""), parsed.records[1].fields)
    }

    @Test
    fun `unclosed quote is reported`() {
        val parsed = CsvCodec.parseText("a,b\n1,\"not closed\n")
        assertNotNull(parsed.errorMessage)
    }
}
