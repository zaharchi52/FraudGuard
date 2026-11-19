import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fraudguard_dart/models.dart';

void main() {
  Transaction transaction() => Transaction(
    transactionId: 'TX-REVIEW',
    clientId: 'C-1',
    timestampText: '2026-11-01T10:00:00Z',
    amountText: '100.00',
    currency: 'EUR',
    country: 'DE',
    merchantCategory: 'groceries',
    deviceId: 'D1',
    amount: Decimal.parse('100.00'),
    timestamp: DateTime.parse('2026-11-01T10:00:00Z'),
    lineNumber: 2,
  );

  ScoredTransaction scored(String decision) => ScoredTransaction(
    transaction: transaction(),
    riskScore: 45,
    decision: decision,
    profileStatus: ProfileStatus.ready,
    factors: const <RiskFactor>[],
  );

  test('review transaction can be approved only once', () {
    final row = LiveTransactionRow(scored('REVIEW'));
    expect(row.isPending, isTrue);
    expect(
      row.resolveReview(
        approve: true,
        reviewedAt: DateTime.parse('2026-11-01T10:05:00Z'),
      ),
      isTrue,
    );
    expect(row.workflowStatus, 'APPROVED_BY_OPERATOR');
    expect(row.reviewedAt, '2026-11-01T10:05:00.000Z');
    expect(
      row.resolveReview(
        approve: false,
        reviewedAt: DateTime.parse('2026-11-01T10:06:00Z'),
      ),
      isFalse,
    );
    expect(row.workflowStatus, 'APPROVED_BY_OPERATOR');
  });

  test('review transaction can be rejected', () {
    final row = LiveTransactionRow(scored('REVIEW'));
    expect(
      row.resolveReview(
        approve: false,
        reviewedAt: DateTime.parse('2026-11-01T10:05:00Z'),
      ),
      isTrue,
    );
    expect(row.workflowStatus, 'REJECTED_BY_OPERATOR');
  });

  test('automatic decisions are not operator review items', () {
    final approved = LiveTransactionRow(scored('APPROVE'));
    final blocked = LiveTransactionRow(scored('BLOCK'));
    expect(approved.workflowStatus, 'AUTO_APPROVED');
    expect(blocked.workflowStatus, 'AUTO_BLOCKED');
    expect(
      approved.resolveReview(approve: false, reviewedAt: DateTime.now()),
      isFalse,
    );
    expect(
      blocked.resolveReview(approve: true, reviewedAt: DateTime.now()),
      isFalse,
    );
  });
}
