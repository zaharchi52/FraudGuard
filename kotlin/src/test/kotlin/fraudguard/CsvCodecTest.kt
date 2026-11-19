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

    @Test
    fun `characters after a closing quote are rejected`() {
        val parsed = CsvCodec.parseText("a,b\n1,\"valid\"suffix\n")
        assertNotNull(parsed.errorMessage)
    }

    @Test
    fun `whitespace after a closing quote is ignored like C++`() {
        val parsed = CsvCodec.parseText("a,b\r\n1,\"value\"  \r\n")
        assertNull(parsed.errorMessage)
        assertEquals(listOf("1", "value"), parsed.records[1].fields)
    }

    @Test
    fun `UTF-8 BOM and CRLF input are accepted`() {
        val parsed = CsvCodec.parseText("\uFEFFa,b\r\n1,2\r\n")
        assertNull(parsed.errorMessage)
        assertEquals(listOf("1", "2"), parsed.records[1].fields)
    }
}
