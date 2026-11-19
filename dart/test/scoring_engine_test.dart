import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fraudguard_dart/csv_codec.dart';
import 'package:fraudguard_dart/fraudguard_service.dart';
import 'package:fraudguard_dart/models.dart';
import 'package:fraudguard_dart/scoring_engine.dart';

void main() {
  group('FraudGuard Dart scoring', () {
    test('matches all rows in expected-results.csv', () {
      final transactions = File(
        'assets/data/transactions.csv',
      ).readAsStringSync();
      final history = File('assets/data/history.csv').readAsStringSync();
      final expectedText = File(
        'assets/data/expected-results.csv',
      ).readAsStringSync();
      final batch = FraudGuardService.analyze(
        transactionsCsv: transactions,
        transactionsFileName: 'transactions.csv',
        historyCsv: history,
        historyFileName: 'history.csv',
      );
      final expected = CsvCodec.parseText(expectedText).records.skip(1);
      final expectedById = <String, List<String>>{
        for (final row in expected) row.fields.first: row.fields,
      };

      expect(batch.currentFileLoaded, isTrue);
      expect(batch.historyCount, 15);
      expect(batch.scoredTransactions, hasLength(9));
      for (final scored in batch.scoredTransactions) {
        final actual = [
          scored.transaction.transactionId,
          scored.riskScore.toString(),
          scored.decision,
          scored.riskFactorsText,
          scored.profileStatus.csvValue,
        ];
        expect(actual, expectedById[scored.transaction.transactionId]);
      }
    });

    test('continues after invalid rows and reports three errors', () {
      final invalid = File(
        'assets/data/transactions_invalid.csv',
      ).readAsStringSync();
      final history = File('assets/data/history.csv').readAsStringSync();
      final batch = FraudGuardService.analyze(
        transactionsCsv: invalid,
        transactionsFileName: 'transactions_invalid.csv',
        historyCsv: history,
      );
      expect(batch.currentFileLoaded, isTrue);
      expect(batch.scoredTransactions, hasLength(1));
      expect(
        batch.scoredTransactions.single.transaction.transactionId,
        'T9004',
      );
      expect(batch.errors, hasLength(3));
    });

    test('decision thresholds are inclusive at 30 and 60', () {
      expect(ScoringEngine.decisionForScore(29), 'APPROVE');
      expect(ScoringEngine.decisionForScore(30), 'REVIEW');
      expect(ScoringEngine.decisionForScore(59), 'REVIEW');
      expect(ScoringEngine.decisionForScore(60), 'BLOCK');
      expect(ScoringEngine.decisionForScore(100), 'BLOCK');
    });

    test('CSV parser supports quoted commas and escaped quotes', () {
      final parsed = CsvCodec.parseText(
        'name,note\nAlice,"hello, world"\nBob,"said ""hi"""\n',
      );
      expect(parsed.errorMessage, isNull);
      expect(parsed.records[1].fields[1], 'hello, world');
      expect(parsed.records[2].fields[1], 'said "hi"');
    });

    test('rejects characters after a closing CSV quote', () {
      final parsed = CsvCodec.parseText('a,b\n1,"valid"suffix\n');
      expect(parsed.errorMessage, isNotNull);
    });

    test('accepts UTF-8 BOM, CRLF and whitespace after closing quote', () {
      final parsed = CsvCodec.parseText('\uFEFFa,b\r\n1,"value"  \r\n');
      expect(parsed.errorMessage, isNull);
      expect(parsed.records[1].fields, ['1', 'value']);
    });

    test('conformance edge fixture matches C++ and Kotlin golden results', () {
      final transactions = File(
        'assets/data/conformance/transactions.csv',
      ).readAsStringSync();
      final history = File(
        'assets/data/conformance/history.csv',
      ).readAsStringSync();
      final expectedText = File(
        'assets/data/conformance/expected-results.csv',
      ).readAsStringSync();
      final batch = FraudGuardService.analyze(
        transactionsCsv: transactions,
        transactionsFileName: 'transactions.csv',
        historyCsv: history,
        historyFileName: 'history.csv',
      );
      final expectedRows = CsvCodec.parseText(expectedText).records.skip(1);
      final expectedById = {
        for (final row in expectedRows)
          row.fields[0]: row.fields.skip(1).toList(),
      };
      expect(batch.currentFileLoaded, isTrue);
      expect(batch.errors, isEmpty);
      expect(batch.scoredTransactions, hasLength(expectedById.length));
      for (final scored in batch.scoredTransactions) {
        expect([
          scored.riskScore.toString(),
          scored.decision,
          scored.riskFactorsText,
          scored.profileStatus.csvValue,
        ], expectedById[scored.transaction.transactionId]);
      }
    });

    test(
      'velocity includes exact ten-minute boundary but excludes event older by one second',
      () {
        const source =
            'transaction_id,client_id,timestamp,amount,currency,country,merchant_category,device_id\n'
            'V5,V,2026-11-01T12:10:00Z,10,EUR,DE,other,DV\n'
            'V2,V,2026-11-01T12:02:00Z,10,EUR,DE,other,DV\n'
            'V1,V,2026-11-01T12:00:00Z,10,EUR,DE,other,DV\n'
            'V4,V,2026-11-01T12:06:00Z,10,EUR,DE,other,DV\n'
            'V3,V,2026-11-01T12:04:00Z,10,EUR,DE,other,DV\n'
            'V6,V,2026-11-01T12:20:01Z,10,EUR,DE,other,DV\n';
        final batch = FraudGuardService.analyze(
          transactionsCsv: source,
          transactionsFileName: 'velocity.csv',
        );
        final byId = {
          for (final result in batch.scoredTransactions)
            result.transaction.transactionId: result,
        };
        expect(byId['V5']!.riskFactorsText, 'HIGH_VELOCITY');
        expect(byId['V6']!.riskFactorsText, isEmpty);
      },
    );

    test(
      'duplicate transaction ids are rejected while following rows continue',
      () {
        const source =
            'transaction_id,client_id,timestamp,amount,currency,country,merchant_category,device_id\n'
            'DUP,C,2026-11-01T12:00:00Z,10,EUR,DE,other,D1\n'
            'DUP,C,2026-11-01T12:01:00Z,10,EUR,DE,other,D1\n'
            'OK,C,2026-11-01T12:02:00Z,10,EUR,DE,other,D1\n';
        final loaded = CsvCodec.loadTransactions(
          contents: source,
          sourceName: 'duplicates.csv',
          seenIds: <String>{},
        );
        expect(loaded.transactions.map((tx) => tx.transactionId), [
          'DUP',
          'OK',
        ]);
        expect(loaded.errors.map((error) => error.errorCode), [
          'DUPLICATE_TRANSACTION_ID',
        ]);
      },
    );

    test('empty history uses cold-start profiles without profile penalties', () {
      const source =
          'transaction_id,client_id,timestamp,amount,currency,country,merchant_category,device_id\n'
          'COLD1,C9,2026-10-28T10:00:00Z,999.00,EUR,US,electronics,new-device\n';
      final batch = FraudGuardService.analyze(
        transactionsCsv: source,
        transactionsFileName: 'cold-start.csv',
      );
      expect(
        batch.scoredTransactions.single.profileStatus,
        ProfileStatus.coldStart,
      );
      expect(batch.scoredTransactions.single.riskScore, 0);
      expect(batch.scoredTransactions.single.decision, 'APPROVE');
    });
  });
}
