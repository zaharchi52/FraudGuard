package fraudguard

import fraudguard.csv.CsvCodec
import fraudguard.engine.ScoringEngine
import fraudguard.model.ProfileStatus
import fraudguard.service.ProjectPaths
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class ScoringEngineTest {
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
