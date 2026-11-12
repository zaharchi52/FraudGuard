package fraudguard.service

import fraudguard.csv.CsvCodec
import fraudguard.engine.ScoringEngine
import fraudguard.io.ReportWriter
import fraudguard.model.AnalysisResult
import fraudguard.model.ProcessingError
import java.nio.file.Files
import java.nio.file.Path

object FraudGuardService {
    fun analyze(
        transactionsPath: Path,
        historyPath: Path?,
        outputDirectory: Path
    ): AnalysisResult {
        val errors = mutableListOf<ProcessingError>()
        val seenIds = linkedSetOf<String>()
        var history = emptyList<fraudguard.model.Transaction>()

        if (historyPath != null && Files.exists(historyPath)) {
            val loadedHistory = CsvCodec.loadTransactions(historyPath, seenIds)
            errors += loadedHistory.errors
            if (loadedHistory.fileLoaded) {
                history = loadedHistory.transactions
            } else {
                // Matches C++ behaviour: a file-level history problem falls back to cold-start profiles.
                seenIds.clear()
                history = emptyList()
            }
        }

        val loadedCurrent = CsvCodec.loadTransactions(transactionsPath, seenIds)
        errors += loadedCurrent.errors
        val scored = ScoringEngine.scoreAll(history, loadedCurrent.transactions)
        ReportWriter.writeBatchReports(outputDirectory, scored, errors)

        return AnalysisResult(
            historyCount = history.size,
            scoredTransactions = scored,
            errors = errors,
            outputDirectory = outputDirectory.toAbsolutePath().normalize().toString(),
            currentFileLoaded = loadedCurrent.fileLoaded
        )
    }
}

object ProjectPaths {
    /** Finds the repository root even when the app is launched from the kotlin/ Gradle directory. */
    fun findProjectRoot(): Path {
        var current = Path.of(System.getProperty("user.dir")).toAbsolutePath().normalize()
        repeat(6) {
            if (Files.exists(current.resolve("data/transactions.csv")) || Files.exists(current.resolve("cpp/CMakeLists.txt"))) {
                return current
            }
            current = current.parent ?: return Path.of(System.getProperty("user.dir")).toAbsolutePath().normalize()
        }
        return Path.of(System.getProperty("user.dir")).toAbsolutePath().normalize()
    }
}
