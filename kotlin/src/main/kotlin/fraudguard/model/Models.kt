package fraudguard.model

import java.math.BigDecimal
import java.time.Instant

const val MIN_HISTORY_SIZE = 5
const val VELOCITY_WINDOW_MILLIS = 10 * 60 * 1000L

val TRANSACTION_HEADER = listOf(
    "transaction_id", "client_id", "timestamp", "amount",
    "currency", "country", "merchant_category", "device_id"
)

val RESULTS_HEADER = listOf(
    "transaction_id", "client_id", "timestamp", "amount", "currency",
    "risk_score", "decision", "risk_factors", "profile_status", "processing_status"
)
val ALERTS_HEADER = listOf(
    "transaction_id", "client_id", "timestamp", "amount", "currency",
    "risk_score", "decision", "risk_factors"
)
val ERRORS_HEADER = listOf("source_file", "line_number", "transaction_id", "error_code", "message")

/** Validated transaction. The original amount text is kept for predictable CSV output. */
data class Transaction(
    val transactionId: String,
    val clientId: String,
    val timestampText: String,
    val amountText: String,
    val currency: String,
    val country: String,
    val merchantCategory: String,
    val deviceId: String,
    val amount: BigDecimal,
    val timestamp: Instant,
    val lineNumber: Int
)

enum class ProfileStatus {
    COLD_START,
    LIMITED_HISTORY,
    READY
}

data class ClientProfile(
    val clientId: String,
    val currency: String,
    val transactionCount: Int,
    val status: ProfileStatus,
    val medianAmount: BigDecimal?,
    val p95Amount: BigDecimal?,
    val countries: Set<String>,
    val devices: Set<String>,
    val categories: Set<String>
)

data class RiskFactor(val code: String, val points: Int)

data class ScoredTransaction(
    val transaction: Transaction,
    val riskScore: Int,
    val decision: String,
    val profileStatus: ProfileStatus,
    val factors: List<RiskFactor>
) {
    val riskFactorsText: String get() = factors.joinToString(";") { it.code }
}

data class ProcessingError(
    val sourceFile: String,
    val lineNumber: Int,
    val transactionId: String,
    val errorCode: String,
    val message: String
)

data class CsvRecord(val lineNumber: Int, val fields: List<String>)
data class CsvReadResult(
    val records: List<CsvRecord>,
    val errorMessage: String? = null,
    val errorLine: Int = 0
)
data class LoadedTransactions(
    val transactions: List<Transaction>,
    val errors: List<ProcessingError>,
    val fileLoaded: Boolean
)
data class AnalysisResult(
    val historyCount: Int,
    val scoredTransactions: List<ScoredTransaction>,
    val errors: List<ProcessingError>,
    val outputDirectory: String,
    val currentFileLoaded: Boolean
)

/** Workflow state kept separate from the engine's original recommendation. */
data class LiveTransactionRow(
    val scored: ScoredTransaction,
    var workflowStatus: String,
    var reviewedAt: String = ""
) {
    /** Applies an operator decision once, and only to a transaction awaiting review. */
    fun resolveReview(approve: Boolean, timestamp: String): Boolean {
        if (workflowStatus != "PENDING_REVIEW") return false
        workflowStatus = if (approve) "APPROVED_BY_OPERATOR" else "REJECTED_BY_OPERATOR"
        reviewedAt = timestamp
        return true
    }
}
