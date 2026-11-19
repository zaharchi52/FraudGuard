package fraudguard

import fraudguard.io.ReportWriter
import fraudguard.model.LiveTransactionRow
import fraudguard.model.ProfileStatus
import fraudguard.model.ScoredTransaction
import fraudguard.model.Transaction
import org.junit.jupiter.api.Test
import java.math.BigDecimal
import java.nio.file.Files
import java.time.Instant
import kotlin.test.assertTrue

class ReportWriterTest {
    @Test
    fun `operator report keeps engine recommendation and final operator decision separately`() {
        val tx = Transaction(
            transactionId = "TX-1", clientId = "C-1", timestampText = "2026-11-01T10:00:00Z",
            amountText = "100.00", currency = "EUR", country = "DE", merchantCategory = "groceries",
            deviceId = "D1", amount = BigDecimal("100.00"), timestamp = Instant.parse("2026-11-01T10:00:00Z"), lineNumber = 2
        )
        val scored = ScoredTransaction(tx, 45, "REVIEW", ProfileStatus.READY, emptyList())
        val row = LiveTransactionRow(scored, "PENDING_REVIEW")
        assertTrue(row.resolveReview(approve = true, timestamp = "2026-11-01T10:05:00Z"))
        val output = Files.createTempDirectory("fraudguard-operator-test")
        try {
            ReportWriter.writeOperatorDecisions(output, listOf(row))
            val report = Files.readString(output.resolve("operator-decisions.csv"))
            assertTrue(report.contains("TX-1,C-1,100.00,EUR,45,REVIEW,APPROVE,APPROVED_BY_OPERATOR"))
        } finally {
            output.toFile().deleteRecursively()
        }
    }
}
