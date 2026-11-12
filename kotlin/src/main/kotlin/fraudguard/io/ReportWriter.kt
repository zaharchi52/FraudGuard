package fraudguard.io

import fraudguard.csv.CsvCodec
import fraudguard.model.ALERTS_HEADER
import fraudguard.model.ERRORS_HEADER
import fraudguard.model.ProcessingError
import fraudguard.model.RESULTS_HEADER
import fraudguard.model.ScoredTransaction
import fraudguard.model.LiveTransactionRow
import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.nio.file.Path

object ReportWriter {
    fun writeBatchReports(outputDirectory: Path, results: List<ScoredTransaction>, errors: List<ProcessingError>) {
        Files.createDirectories(outputDirectory)
        val resultLines = mutableListOf(CsvCodec.encodeRow(RESULTS_HEADER))
        val alertLines = mutableListOf(CsvCodec.encodeRow(ALERTS_HEADER))

        results.forEach { scored ->
            val tx = scored.transaction
            val factors = scored.riskFactorsText
            resultLines += CsvCodec.encodeRow(
                listOf(tx.transactionId, tx.clientId, tx.timestampText, tx.amountText, tx.currency,
                    scored.riskScore.toString(), scored.decision, factors, scored.profileStatus.name, "OK")
            )
            if (scored.decision == "REVIEW" || scored.decision == "BLOCK") {
                alertLines += CsvCodec.encodeRow(
                    listOf(tx.transactionId, tx.clientId, tx.timestampText, tx.amountText, tx.currency,
                        scored.riskScore.toString(), scored.decision, factors)
                )
            }
        }

        val errorLines = mutableListOf(CsvCodec.encodeRow(ERRORS_HEADER))
        errors.forEach { error ->
            errorLines += CsvCodec.encodeRow(
                listOf(error.sourceFile, error.lineNumber.toString(), error.transactionId, error.errorCode, error.message)
            )
        }
        Files.writeString(outputDirectory.resolve("results.csv"), resultLines.joinToString("\n", postfix = "\n"), StandardCharsets.UTF_8)
        Files.writeString(outputDirectory.resolve("alerts.csv"), alertLines.joinToString("\n", postfix = "\n"), StandardCharsets.UTF_8)
        Files.writeString(outputDirectory.resolve("errors.csv"), errorLines.joinToString("\n", postfix = "\n"), StandardCharsets.UTF_8)
    }

    /** Rewritten throughout the demo, so operator decisions survive closing the window. */
    fun writeOperatorDecisions(outputDirectory: Path, rows: List<LiveTransactionRow>) {
        Files.createDirectories(outputDirectory)
        val header = listOf(
            "transaction_id", "client_id", "amount", "currency", "risk_score",
            "engine_decision", "operator_decision", "workflow_status", "risk_factors", "reviewed_at"
        )
        val lines = mutableListOf(CsvCodec.encodeRow(header))
        rows.forEach { row ->
            val scored = row.scored
            val tx = scored.transaction
            val operatorDecision = when (row.workflowStatus) {
                "APPROVED_BY_OPERATOR" -> "APPROVE"
                "REJECTED_BY_OPERATOR" -> "REJECT"
                else -> ""
            }
            lines += CsvCodec.encodeRow(
                listOf(tx.transactionId, tx.clientId, tx.amountText, tx.currency, scored.riskScore.toString(),
                    scored.decision, operatorDecision, row.workflowStatus, scored.riskFactorsText, row.reviewedAt)
            )
        }
        Files.writeString(outputDirectory.resolve("operator-decisions.csv"), lines.joinToString("\n", postfix = "\n"), StandardCharsets.UTF_8)
    }
}
