package fraudguard.engine

import fraudguard.model.ClientProfile
import fraudguard.model.MIN_HISTORY_SIZE
import fraudguard.model.ProfileStatus
import fraudguard.model.RiskFactor
import fraudguard.model.ScoredTransaction
import fraudguard.model.Transaction
import fraudguard.model.VELOCITY_WINDOW_MILLIS
import java.math.BigDecimal
import java.math.RoundingMode
import kotlin.math.ceil

/** Kotlin port of the C++ scoring rules. Constants and comparison boundaries intentionally match. */
object ScoringEngine {
    fun median(values: List<BigDecimal>): BigDecimal {
        require(values.isNotEmpty()) { "median() requires at least one value" }
        val sorted = values.sorted()
        val mid = sorted.size / 2
        return if (sorted.size % 2 == 1) sorted[mid]
        else sorted[mid - 1].add(sorted[mid]).divide(BigDecimal("2"))
    }

    /** 95th percentile using nearest-rank: sorted[ceil(0.95 * n) - 1]. */
    fun percentile95NearestRank(values: List<BigDecimal>): BigDecimal {
        require(values.isNotEmpty()) { "percentile95NearestRank() requires at least one value" }
        val sorted = values.sorted()
        val rank = ceil(0.95 * sorted.size).toInt().coerceAtLeast(1)
        return sorted[rank - 1]
    }

    fun decisionForScore(score: Int): String {
        require(score in 0..100) { "score must be in range 0..100" }
        return when {
            score < 30 -> "APPROVE"
            score < 60 -> "REVIEW"
            else -> "BLOCK"
        }
    }

    fun buildProfile(history: List<Transaction>, clientId: String, currency: String): ClientProfile {
        val matching = history.filter { it.clientId == clientId && it.currency == currency }
        val countries = matching.map { it.country }.toCollection(linkedSetOf())
        val devices = matching.map { it.deviceId }.toCollection(linkedSetOf())
        val categories = matching.map { it.merchantCategory }.toCollection(linkedSetOf())
        val status = when {
            matching.isEmpty() -> ProfileStatus.COLD_START
            matching.size < MIN_HISTORY_SIZE -> ProfileStatus.LIMITED_HISTORY
            else -> ProfileStatus.READY
        }
        val amounts = matching.map { it.amount }
        return ClientProfile(
            clientId = clientId,
            currency = currency,
            transactionCount = matching.size,
            status = status,
            medianAmount = if (status == ProfileStatus.READY) median(amounts) else null,
            p95Amount = if (status == ProfileStatus.READY) percentile95NearestRank(amounts) else null,
            countries = countries,
            devices = devices,
            categories = categories
        )
    }

    fun evaluateRisk(transaction: Transaction, profile: ClientProfile, velocityCount: Int): List<RiskFactor> {
        val factors = mutableListOf<RiskFactor>()
        if (profile.status == ProfileStatus.READY) {
            val median = requireNotNull(profile.medianAmount)
            val p95 = requireNotNull(profile.p95Amount)
            if (transaction.amount >= median.multiply(BigDecimal("5"))) {
                factors += RiskFactor("HIGH_AMOUNT", 30)
            } else if (transaction.amount > p95) {
                factors += RiskFactor("UNUSUAL_AMOUNT", 15)
            }
        }
        if (velocityCount >= 5) factors += RiskFactor("HIGH_VELOCITY", 25)
        if (profile.status == ProfileStatus.READY) {
            if (transaction.country !in profile.countries) factors += RiskFactor("NEW_COUNTRY", 20)
            if (transaction.deviceId !in profile.devices) factors += RiskFactor("NEW_DEVICE", 15)
            if (transaction.merchantCategory !in profile.categories) factors += RiskFactor("NEW_CATEGORY", 10)
        }
        return factors
    }

    fun scoreForFactors(factors: List<RiskFactor>): Int = factors.sumOf { it.points }.coerceAtMost(100)

    /**
     * Scores a complete batch. Velocity is computed over all valid batch rows, counting
     * the inclusive [timestamp - 10 minutes, timestamp] window, just like the C++ engine.
     */
    fun scoreAll(history: List<Transaction>, currentTransactions: List<Transaction>): List<ScoredTransaction> {
        val timesByClient = currentTransactions
            .groupBy { it.clientId }
            .mapValues { (_, transactions) -> transactions.map { it.timestamp.toEpochMilli() }.sorted() }

        return currentTransactions.map { transaction ->
            val profile = buildProfile(history, transaction.clientId, transaction.currency)
            val times = timesByClient[transaction.clientId].orEmpty()
            val pointInTime = transaction.timestamp.toEpochMilli()
            val lower = pointInTime - VELOCITY_WINDOW_MILLIS
            val velocityCount = times.count { it >= lower && it <= pointInTime }
            val factors = evaluateRisk(transaction, profile, velocityCount)
            val score = scoreForFactors(factors)
            ScoredTransaction(transaction, score, decisionForScore(score), profile.status, factors)
        }
    }
}
