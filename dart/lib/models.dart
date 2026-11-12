import 'package:decimal/decimal.dart';

const minHistorySize = 5;
const velocityWindow = Duration(minutes: 10);

const transactionHeader = <String>[
  'transaction_id',
  'client_id',
  'timestamp',
  'amount',
  'currency',
  'country',
  'merchant_category',
  'device_id',
];

const resultsHeader = <String>[
  'transaction_id',
  'client_id',
  'timestamp',
  'amount',
  'currency',
  'risk_score',
  'decision',
  'risk_factors',
  'profile_status',
  'processing_status',
];

const alertsHeader = <String>[
  'transaction_id',
  'client_id',
  'timestamp',
  'amount',
  'currency',
  'risk_score',
  'decision',
  'risk_factors',
];

const errorsHeader = <String>[
  'source_file',
  'line_number',
  'transaction_id',
  'error_code',
  'message',
];

class Transaction {
  const Transaction({
    required this.transactionId,
    required this.clientId,
    required this.timestampText,
    required this.amountText,
    required this.currency,
    required this.country,
    required this.merchantCategory,
    required this.deviceId,
    required this.amount,
    required this.timestamp,
    required this.lineNumber,
  });

  final String transactionId;
  final String clientId;
  final String timestampText;
  final String amountText;
  final String currency;
  final String country;
  final String merchantCategory;
  final String deviceId;
  final Decimal amount;
  final DateTime timestamp;
  final int lineNumber;
}

enum ProfileStatus { coldStart, limitedHistory, ready }

extension ProfileStatusLabel on ProfileStatus {
  String get csvValue => switch (this) {
        ProfileStatus.coldStart => 'COLD_START',
        ProfileStatus.limitedHistory => 'LIMITED_HISTORY',
        ProfileStatus.ready => 'READY',
      };
}

class ClientProfile {
  const ClientProfile({
    required this.clientId,
    required this.currency,
    required this.transactionCount,
    required this.status,
    required this.amountsSorted,
    required this.p95Amount,
    required this.countries,
    required this.devices,
    required this.categories,
  });

  final String clientId;
  final String currency;
  final int transactionCount;
  final ProfileStatus status;
  final List<Decimal> amountsSorted;
  final Decimal? p95Amount;
  final Set<String> countries;
  final Set<String> devices;
  final Set<String> categories;
}

class RiskFactor {
  const RiskFactor(this.code, this.points);
  final String code;
  final int points;
}

class ScoredTransaction {
  const ScoredTransaction({
    required this.transaction,
    required this.riskScore,
    required this.decision,
    required this.profileStatus,
    required this.factors,
  });

  final Transaction transaction;
  final int riskScore;
  final String decision;
  final ProfileStatus profileStatus;
  final List<RiskFactor> factors;

  String get riskFactorsText => factors.map((factor) => factor.code).join(';');
}

class ProcessingError {
  const ProcessingError({
    required this.sourceFile,
    required this.lineNumber,
    required this.transactionId,
    required this.errorCode,
    required this.message,
  });

  final String sourceFile;
  final int lineNumber;
  final String transactionId;
  final String errorCode;
  final String message;
}

class CsvRecord {
  const CsvRecord(this.lineNumber, this.fields);
  final int lineNumber;
  final List<String> fields;
}

class CsvParseResult {
  const CsvParseResult({
    required this.records,
    this.errorMessage,
    this.errorLine = 0,
  });

  final List<CsvRecord> records;
  final String? errorMessage;
  final int errorLine;
}

class LoadedTransactions {
  const LoadedTransactions({
    required this.transactions,
    required this.errors,
    required this.fileLoaded,
  });

  final List<Transaction> transactions;
  final List<ProcessingError> errors;
  final bool fileLoaded;
}

class AnalysisBatch {
  const AnalysisBatch({
    required this.historyCount,
    required this.scoredTransactions,
    required this.errors,
    required this.currentFileLoaded,
  });

  final int historyCount;
  final List<ScoredTransaction> scoredTransactions;
  final List<ProcessingError> errors;
  final bool currentFileLoaded;
}

class LiveTransactionRow {
  LiveTransactionRow(this.scored)
      : workflowStatus = switch (scored.decision) {
          'APPROVE' => 'AUTO_APPROVED',
          'BLOCK' => 'AUTO_BLOCKED',
          _ => 'PENDING_REVIEW',
        };

  final ScoredTransaction scored;
  String workflowStatus;
  String reviewedAt = '';

  bool get isPending => workflowStatus == 'PENDING_REVIEW';
  bool get isBlocked =>
      workflowStatus == 'AUTO_BLOCKED' || workflowStatus == 'REJECTED_BY_OPERATOR';
}
