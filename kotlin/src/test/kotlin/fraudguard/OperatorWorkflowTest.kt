package fraudguard

import fraudguard.model.LiveTransactionRow
import fraudguard.model.ProfileStatus
import fraudguard.model.ScoredTransaction
import fraudguard.model.Transaction
import org.junit.jupiter.api.Test
import java.math.BigDecimal
import java.time.Instant
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class OperatorWorkflowTest {
    private fun scored(decision: String) = ScoredTransaction(
        transaction = Transaction(
            transactionId = "TX-REVIEW",
            clientId = "C-1",
            timestampText = "2026-11-01T10:00:00Z",
            amountText = "100.00",
            currency = "EUR",
            country = "DE",
            merchantCategory = "groceries",
            deviceId = "D1",
            amount = BigDecimal("100.00"),
            timestamp = Instant.parse("2026-11-01T10:00:00Z"),
            lineNumber = 2
        ),
        riskScore = 45,
        decision = decision,
        profileStatus = ProfileStatus.READY,
        factors = emptyList()
    )

    @Test
    fun `review transaction can be approved only once`() {
        val row = LiveTransactionRow(scored("REVIEW"), "PENDING_REVIEW")
        assertTrue(row.resolveReview(approve = true, timestamp = "2026-11-01T10:05:00Z"))
        assertEquals("APPROVED_BY_OPERATOR", row.workflowStatus)
        assertEquals("2026-11-01T10:05:00Z", row.reviewedAt)
        assertFalse(row.resolveReview(approve = false, timestamp = "2026-11-01T10:06:00Z"))
        assertEquals("APPROVED_BY_OPERATOR", row.workflowStatus)
    }

    @Test
    fun `review can be rejected and automatic decisions are not operator review items`() {
        val review = LiveTransactionRow(scored("REVIEW"), "PENDING_REVIEW")
        assertTrue(review.resolveReview(approve = false, timestamp = "2026-11-01T10:05:00Z"))
        assertEquals("REJECTED_BY_OPERATOR", review.workflowStatus)

        val automatic = LiveTransactionRow(scored("APPROVE"), "AUTO_APPROVED")
        assertFalse(automatic.resolveReview(approve = true, timestamp = "2026-11-01T10:05:00Z"))
        assertEquals("AUTO_APPROVED", automatic.workflowStatus)
    }
}
