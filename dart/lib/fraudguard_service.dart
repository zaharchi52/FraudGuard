import 'csv_codec.dart';
import 'models.dart';
import 'scoring_engine.dart';

class FraudGuardService {
  static AnalysisBatch analyze({
    required String transactionsCsv,
    required String transactionsFileName,
    String? historyCsv,
    String historyFileName = 'history.csv',
  }) {
    final errors = <ProcessingError>[];
    final seenIds = <String>{};
    var history = <Transaction>[];

    if (historyCsv != null && historyCsv.trim().isNotEmpty) {
      final loadedHistory = CsvCodec.loadTransactions(
        contents: historyCsv,
        sourceName: historyFileName,
        seenIds: seenIds,
      );
      errors.addAll(loadedHistory.errors);
      if (loadedHistory.fileLoaded) {
        history = loadedHistory.transactions;
      } else {
        // Same fallback as C++/Kotlin: a file-level history error means cold-start.
        seenIds.clear();
        history = <Transaction>[];
      }
    }

    final loadedCurrent = CsvCodec.loadTransactions(
      contents: transactionsCsv,
      sourceName: transactionsFileName,
      seenIds: seenIds,
    );
    errors.addAll(loadedCurrent.errors);
    final scored = ScoringEngine.scoreAll(history, loadedCurrent.transactions);

    return AnalysisBatch(
      historyCount: history.length,
      scoredTransactions: scored,
      errors: List<ProcessingError>.unmodifiable(errors),
      currentFileLoaded: loadedCurrent.fileLoaded,
    );
  }
}
