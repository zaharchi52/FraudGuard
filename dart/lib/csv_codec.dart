import 'package:decimal/decimal.dart';

import 'models.dart';

class CsvCodec {
  static CsvParseResult parseText(String input) {
    final text = input
        .replaceFirst('\uFEFF', '')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    if (text.isEmpty) return const CsvParseResult(records: []);

    final records = <CsvRecord>[];
    var fields = <String>[];
    final field = StringBuffer();
    var inQuotes = false;
    var fieldWasQuoted = false;
    var lineNumber = 1;
    var recordStartLine = 1;
    var index = 0;

    void finishField() {
      fields.add(field.toString());
      field.clear();
      fieldWasQuoted = false;
    }

    void finishRecord() {
      finishField();
      if (!(fields.length == 1 && fields.first.trim().isEmpty)) {
        records.add(CsvRecord(recordStartLine, List<String>.unmodifiable(fields)));
      }
      fields = <String>[];
      recordStartLine = lineNumber + 1;
    }

    while (index < text.length) {
      final character = text[index];
      if (inQuotes) {
        if (character == '"') {
          if (index + 1 < text.length && text[index + 1] == '"') {
            field.write('"');
            index++;
          } else {
            inQuotes = false;
          }
        } else {
          field.write(character);
          if (character == '\n') lineNumber++;
        }
      } else {
        switch (character) {
          case ',':
            finishField();
            break;
          case '\n':
            finishRecord();
            lineNumber++;
            recordStartLine = lineNumber;
            break;
          case '"':
            if (field.isNotEmpty || fieldWasQuoted) {
              return CsvParseResult(
                records: const [],
                errorMessage: 'Кавычка в неожиданной позиции',
                errorLine: lineNumber,
              );
            }
            inQuotes = true;
            fieldWasQuoted = true;
            break;
          default:
            field.write(character);
            break;
        }
      }
      index++;
    }

    if (inQuotes) {
      return CsvParseResult(
        records: const [],
        errorMessage: 'Незакрытая кавычка в CSV',
        errorLine: recordStartLine,
      );
    }

    if (field.isNotEmpty || fields.isNotEmpty || !text.endsWith('\n')) {
      finishRecord();
    }
    return CsvParseResult(records: List<CsvRecord>.unmodifiable(records));
  }

  static LoadedTransactions loadTransactions({
    required String contents,
    required String sourceName,
    required Set<String> seenIds,
  }) {
    final parsed = parseText(contents);
    if (parsed.errorMessage != null) {
      return LoadedTransactions(
        transactions: const [],
        errors: [
          ProcessingError(
            sourceFile: sourceName,
            lineNumber: parsed.errorLine,
            transactionId: '',
            errorCode: 'CSV_PARSE_ERROR',
            message: parsed.errorMessage!,
          ),
        ],
        fileLoaded: false,
      );
    }

    if (parsed.records.isEmpty ||
        !_sameHeader(parsed.records.first.fields, transactionHeader)) {
      return LoadedTransactions(
        transactions: const [],
        errors: [
          ProcessingError(
            sourceFile: sourceName,
            lineNumber: (parsed.records.isEmpty ? 1 : parsed.records.first.lineNumber),
            transactionId: '',
            errorCode: 'FILE_SCHEMA',
            message: 'Заголовок CSV не соответствует ожидаемой схеме из 8 колонок',
          ),
        ],
        fileLoaded: false,
      );
    }

    final transactions = <Transaction>[];
    final errors = <ProcessingError>[];
    for (final record in parsed.records.skip(1)) {
      final values = record.fields.map((value) => value.trim()).toList();
      final transactionId = (values.isEmpty ? '' : values.first);
      if (values.length != transactionHeader.length) {
        errors.add(ProcessingError(
          sourceFile: sourceName,
          lineNumber: record.lineNumber,
          transactionId: transactionId,
          errorCode: 'CSV_COLUMN_COUNT',
          message: 'Число полей не соответствует ожидаемой схеме из 8 колонок',
        ));
        continue;
      }

      final validation = _validate(values, record.lineNumber);
      if (validation.transaction == null) {
        errors.add(ProcessingError(
          sourceFile: sourceName,
          lineNumber: record.lineNumber,
          transactionId: transactionId,
          errorCode: validation.errorCode,
          message: validation.message,
        ));
        continue;
      }

      final transaction = validation.transaction!;
      if (!seenIds.add(transaction.transactionId)) {
        errors.add(ProcessingError(
          sourceFile: sourceName,
          lineNumber: record.lineNumber,
          transactionId: transaction.transactionId,
          errorCode: 'DUPLICATE_TRANSACTION_ID',
          message: 'Идентификатор транзакции уже встречался',
        ));
        continue;
      }
      transactions.add(transaction);
    }

    return LoadedTransactions(
      transactions: List<Transaction>.unmodifiable(transactions),
      errors: List<ProcessingError>.unmodifiable(errors),
      fileLoaded: true,
    );
  }

  static _ValidationOutcome _validate(List<String> values, int lineNumber) {
    final id = values[0];
    final client = values[1];
    final timestampText = values[2];
    final amountText = values[3];
    final currency = values[4];
    final country = values[5];
    final category = values[6];
    final device = values[7];

    if (values.any((value) => value.isEmpty)) {
      return const _ValidationOutcome.error(
        'REQUIRED_FIELD_EMPTY',
        'Одно или несколько обязательных полей пусты',
      );
    }

    if (!RegExp(r'(?:Z|[+-]\d{2}:\d{2})$').hasMatch(timestampText)) {
      return const _ValidationOutcome.error(
        'INVALID_TIMESTAMP',
        'Дата должна соответствовать ISO 8601 и содержать часовой пояс',
      );
    }
    final timestamp = DateTime.tryParse(timestampText);
    if (timestamp == null) {
      return const _ValidationOutcome.error(
        'INVALID_TIMESTAMP',
        'Дата должна соответствовать ISO 8601 и содержать часовой пояс',
      );
    }

    Decimal amount;
    try {
      amount = Decimal.parse(amountText);
    } on FormatException {
      return const _ValidationOutcome.error(
        'INVALID_AMOUNT',
        'Сумма должна быть конечным числом строго больше нуля',
      );
    }
    if (amount <= Decimal.zero) {
      return const _ValidationOutcome.error(
        'INVALID_AMOUNT',
        'Сумма должна быть конечным числом строго больше нуля',
      );
    }
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(currency)) {
      return const _ValidationOutcome.error(
        'INVALID_CURRENCY',
        'Валюта должна быть трёхбуквенным кодом в верхнем регистре',
      );
    }

    return _ValidationOutcome.success(Transaction(
      transactionId: id,
      clientId: client,
      timestampText: timestampText,
      amountText: amountText,
      currency: currency,
      country: country,
      merchantCategory: category,
      deviceId: device,
      amount: amount,
      timestamp: timestamp.toUtc(),
      lineNumber: lineNumber,
    ));
  }

  static bool _sameHeader(List<String> actual, List<String> expected) {
    if (actual.length != expected.length) return false;
    for (var index = 0; index < actual.length; index++) {
      if (actual[index].trim() != expected[index]) return false;
    }
    return true;
  }

  static String encodeRow(Iterable<String> values) =>
      values.map(escape).join(',');

  static String escape(String value) {
    if (value.contains(',') ||
        value.contains('"') ||
        value.contains('\r') ||
        value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}

class _ValidationOutcome {
  const _ValidationOutcome.success(this.transaction)
      : errorCode = '',
        message = '';
  const _ValidationOutcome.error(this.errorCode, this.message)
      : transaction = null;

  final Transaction? transaction;
  final String errorCode;
  final String message;
}
