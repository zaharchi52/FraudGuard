import 'package:decimal/decimal.dart';

import 'models.dart';

/// Dart implementation of the same scoring rules used by the C++ and Kotlin engines.
class ScoringEngine {
  static String decisionForScore(int score) {
    if (score < 0 || score > 100) {
      throw RangeError.range(score, 0, 100, 'score');
    }
    if (score < 30) return 'APPROVE';
    if (score < 60) return 'REVIEW';
    return 'BLOCK';
  }

  static ClientProfile buildProfile(
    List<Transaction> history,
    String clientId,
    String currency,
  ) {
    final matching = history
        .where((tx) => tx.clientId == clientId && tx.currency == currency)
        .toList(growable: false);
    final status = matching.isEmpty
        ? ProfileStatus.coldStart
        : matching.length < minHistorySize
        ? ProfileStatus.limitedHistory
        : ProfileStatus.ready;
    final amounts = matching.map((tx) => tx.amount).toList()..sort();
    final p95 = status == ProfileStatus.ready
        ? _percentile95NearestRank(amounts)
        : null;

    return ClientProfile(
      clientId: clientId,
      currency: currency,
      transactionCount: matching.length,
      status: status,
      amountsSorted: List<Decimal>.unmodifiable(amounts),
      p95Amount: p95,
      countries: matching.map((tx) => tx.country).toSet(),
      devices: matching.map((tx) => tx.deviceId).toSet(),
      categories: matching.map((tx) => tx.merchantCategory).toSet(),
    );
  }

  static Decimal _percentile95NearestRank(List<Decimal> sorted) {
    if (sorted.isEmpty) throw ArgumentError('p95 requires at least one value');
    final rank = ((95 * sorted.length) + 99) ~/ 100;
    return sorted[rank - 1];
  }

  /// Avoids division in the even-sized median case while retaining exact decimals:
  /// amount >= ((middleLeft + middleRight) / 2) * 5
  /// is equivalent to amount * 2 >= (middleLeft + middleRight) * 5.
  static bool _isHighAmount(Decimal amount, List<Decimal> sortedAmounts) {
    final middle = sortedAmounts.length ~/ 2;
    if (sortedAmounts.length.isOdd) {
      return amount >= sortedAmounts[middle] * Decimal.fromInt(5);
    }
    final middleSum = sortedAmounts[middle - 1] + sortedAmounts[middle];
    return amount * Decimal.fromInt(2) >= middleSum * Decimal.fromInt(5);
  }

  static List<RiskFactor> evaluateRisk(
    Transaction transaction,
    ClientProfile profile,
    int velocityCount,
  ) {
    final factors = <RiskFactor>[];
    if (profile.status == ProfileStatus.ready) {
      if (_isHighAmount(transaction.amount, profile.amountsSorted)) {
        factors.add(const RiskFactor('HIGH_AMOUNT', 30));
      } else if (transaction.amount > profile.p95Amount!) {
        factors.add(const RiskFactor('UNUSUAL_AMOUNT', 15));
      }
    }

    if (velocityCount >= 5) {
      factors.add(const RiskFactor('HIGH_VELOCITY', 25));
    }

    if (profile.status == ProfileStatus.ready) {
      if (!profile.countries.contains(transaction.country)) {
        factors.add(const RiskFactor('NEW_COUNTRY', 20));
      }
      if (!profile.devices.contains(transaction.deviceId)) {
        factors.add(const RiskFactor('NEW_DEVICE', 15));
      }
      if (!profile.categories.contains(transaction.merchantCategory)) {
        factors.add(const RiskFactor('NEW_CATEGORY', 10));
      }
    }
    return List<RiskFactor>.unmodifiable(factors);
  }

  static int scoreForFactors(List<RiskFactor> factors) {
    final total = factors.fold<int>(0, (sum, factor) => sum + factor.points);
    return total > 100 ? 100 : total;
  }

  /// Velocity is calculated over all valid current rows and uses the inclusive
  /// [timestamp - 10 minutes, timestamp] window, matching C++ and Kotlin.
  static List<ScoredTransaction> scoreAll(
    List<Transaction> history,
    List<Transaction> currentTransactions,
  ) {
    final timesByClient = <String, List<DateTime>>{};
    for (final transaction in currentTransactions) {
      timesByClient
          .putIfAbsent(transaction.clientId, () => <DateTime>[])
          .add(transaction.timestamp);
    }
    for (final times in timesByClient.values) {
      times.sort();
    }

    return currentTransactions
        .map((transaction) {
          final profile = buildProfile(
            history,
            transaction.clientId,
            transaction.currency,
          );
          final currentTime = transaction.timestamp;
          final lowerBound = currentTime.subtract(velocityWindow);
          final velocityCount =
              (timesByClient[transaction.clientId] ?? const <DateTime>[])
                  .where(
                    (time) =>
                        !time.isBefore(lowerBound) &&
                        !time.isAfter(currentTime),
                  )
                  .length;
          final factors = evaluateRisk(transaction, profile, velocityCount);
          final score = scoreForFactors(factors);
          return ScoredTransaction(
            transaction: transaction,
            riskScore: score,
            decision: decisionForScore(score),
            profileStatus: profile.status,
            factors: factors,
          );
        })
        .toList(growable: false);
  }
}
