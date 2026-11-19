package fraudguard

import fraudguard.csv.CsvCodec
import fraudguard.engine.ScoringEngine
import fraudguard.model.ProfileStatus
import fraudguard.service.ProjectPaths
import org.junit.jupiter.api.Test
import java.math.BigDecimal
import java.time.Instant
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class ScoringEngineTest {

    private fun tx(
        id: String,
        client: String = "C-TEST",
        timestamp: String,
        amount: String = "20.00",
        currency: String = "EUR",
        country: String = "DE",
        category: String = "groceries",
        device: String = "D-TEST"
    ) = fraudguard.model.Transaction(
        transactionId = id,
        clientId = client,
        timestampText = timestamp,
        amountText = amount,
        currency = currency,
        country = country,
        merchantCategory = category,
        deviceId = device,
        amount = BigDecimal(amount),
        timestamp = Instant.parse(timestamp),
        lineNumber = 1
    )

    @Test
    fun `conformance edge fixture matches C++ and Dart golden results`() {
        val root = ProjectPaths.findProjectRoot()
        val history = CsvCodec.loadTransactions(root.resolve("data/conformance/history.csv"), linkedSetOf()).transactions
        val current = CsvCodec.loadTransactions(root.resolve("data/conformance/transactions.csv"), linkedSetOf()).transactions
        val expectedRecords = CsvCodec.readRecords(root.resolve("data/conformance/expected-results.csv")).records.drop(1)
        val expected = expectedRecords.associate { record ->
            record.fields[0] to record.fields.drop(1)
        }
        val actual = ScoringEngine.scoreAll(history, current)
        assertEquals(expected.size, actual.size)
        actual.forEach { scored ->
            assertEquals(expected.getValue(scored.transaction.transactionId), listOf(
                scored.riskScore.toString(), scored.decision, scored.riskFactorsText, scored.profileStatus.name
            ), "conformance for ${scored.transaction.transactionId}")
        }
    }

    @Test
    fun `velocity counts transactions in an inclusive ten minute window`() {
        val current = listOf(
            tx("V5", client = "V", timestamp = "2026-11-01T12:10:00Z"),
            tx("V2", client = "V", timestamp = "2026-11-01T12:02:00Z"),
            tx("V1", client = "V", timestamp = "2026-11-01T12:00:00Z"),
            tx("V4", client = "V", timestamp = "2026-11-01T12:06:00Z"),
            tx("V3", client = "V", timestamp = "2026-11-01T12:04:00Z"),
            tx("V6", client = "V", timestamp = "2026-11-01T12:20:01Z")
        )
        val scored = ScoringEngine.scoreAll(emptyList(), current).associateBy { it.transaction.transactionId }
        assertTrue(scored.getValue("V5").factors.any { it.code == "HIGH_VELOCITY" })
        assertFalse(scored.getValue("V6").factors.any { it.code == "HIGH_VELOCITY" })
    }

    @Test
    fun `profile is scoped by both client and currency`() {
        val history = listOf(
            tx("H1", client = "A", timestamp = "2026-10-31T09:00:00Z", amount = "10", currency = "EUR"),
            tx("H2", client = "A", timestamp = "2026-10-31T09:01:00Z", amount = "20", currency = "EUR"),
            tx("H3", client = "A", timestamp = "2026-10-31T09:02:00Z", amount = "30", currency = "EUR"),
            tx("H4", client = "A", timestamp = "2026-10-31T09:03:00Z", amount = "40", currency = "EUR"),
            tx("H5", client = "A", timestamp = "2026-10-31T09:04:00Z", amount = "50", currency = "EUR"),
        )
        assertEquals(ProfileStatus.READY, ScoringEngine.buildProfile(history, "A", "EUR").status)
        assertEquals(ProfileStatus.COLD_START, ScoringEngine.buildProfile(history, "A", "USD").status)
        assertEquals(ProfileStatus.COLD_START, ScoringEngine.buildProfile(history, "B", "EUR").status)
    }

    @Test
    fun `high amount boundary is inclusive and unusual amount boundary is strict`() {
        val profileHistory = listOf("20", "25", "30", "35", "40").mapIndexed { index, amount ->
            tx("H$index", timestamp = "2026-10-31T09:0${index}:00Z", amount = amount)
        }
        val profile = ScoringEngine.buildProfile(profileHistory, "C-TEST", "EUR")
        val highBoundary = ScoringEngine.evaluateRisk(tx("HIGH", timestamp = "2026-11-01T10:00:00Z", amount = "150"), profile, 1)
        val p95Boundary = ScoringEngine.evaluateRisk(tx("P95", timestamp = "2026-11-01T10:00:00Z", amount = "40"), profile, 1)
        assertEquals(listOf("HIGH_AMOUNT"), highBoundary.map { it.code })
        assertTrue(p95Boundary.isEmpty())
    }
    @Test
    fun `Kotlin port matches C++ expected results fixture`() {
        val root = ProjectPaths.findProjectRoot()
        val seen = linkedSetOf<String>()
        val historyLoad = CsvCodec.loadTransactions(root.resolve("data/history.csv"), seen)
        val currentLoad = CsvCodec.loadTransactions(root.resolve("data/transactions.csv"), seen)
        assertTrue(historyLoad.fileLoaded)
        assertTrue(currentLoad.fileLoaded)
        assertTrue(historyLoad.errors.isEmpty())
        assertTrue(currentLoad.errors.isEmpty())

        val actual = ScoringEngine.scoreAll(historyLoad.transactions, currentLoad.transactions)
        val expectedRecords = CsvCodec.readRecords(root.resolve("data/expected-results.csv")).records.drop(1)
        val expected = expectedRecords.associate { record ->
            record.fields[0] to listOf(record.fields[1], record.fields[2], record.fields[3], record.fields[4])
        }
        assertEquals(expected.size, actual.size)
        actual.forEach { scored ->
            val row = expected.getValue(scored.transaction.transactionId)
            assertEquals(row[0], scored.riskScore.toString(), "score for ${scored.transaction.transactionId}")
            assertEquals(row[1], scored.decision, "decision for ${scored.transaction.transactionId}")
            assertEquals(row[2], scored.riskFactorsText, "factors for ${scored.transaction.transactionId}")
            assertEquals(row[3], scored.profileStatus.name, "profile for ${scored.transaction.transactionId}")
        }
    }

    @Test
    fun `cold start does not apply profile-only rules`() {
        val root = ProjectPaths.findProjectRoot()
        val seen = linkedSetOf<String>()
        val transactions = CsvCodec.loadTransactions(root.resolve("data/transactions.csv"), seen).transactions
        val tx = transactions.first()
        val profile = ScoringEngine.buildProfile(emptyList(), tx.clientId, tx.currency)
        assertEquals(ProfileStatus.COLD_START, profile.status)
        assertTrue(ScoringEngine.evaluateRisk(tx, profile, velocityCount = 1).isEmpty())
    }

    @Test
    fun `score thresholds match required decisions`() {
        assertEquals("APPROVE", ScoringEngine.decisionForScore(29))
        assertEquals("REVIEW", ScoringEngine.decisionForScore(30))
        assertEquals("REVIEW", ScoringEngine.decisionForScore(59))
        assertEquals("BLOCK", ScoringEngine.decisionForScore(60))
        assertEquals("BLOCK", ScoringEngine.decisionForScore(100))
    }

    @Test
    fun `median and nearest-rank p95 use the C++ definitions`() {
        val values = listOf("20", "25", "30", "35", "40").map { java.math.BigDecimal(it) }
        assertEquals(java.math.BigDecimal("30"), ScoringEngine.median(values))
        assertEquals(java.math.BigDecimal("40"), ScoringEngine.percentile95NearestRank(values))
    }
}
