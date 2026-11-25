import 'package:flutter_test/flutter_test.dart';
import 'package:sport_league/features/cash/domain/team_cash.dart';
import 'package:sport_league/features/cash/presentation/receipts_section.dart';

void main() {
  test('lê o caixa do banco', () {
    final cash = TeamCash.fromMap({
      'locked': false,
      'can_manage': true,
      'balance': 4500,
      'total_in': 9000,
      'total_out': 4500,
      'entries': [
        {
          'id': 'e1',
          'day': '2026-11-20',
          'kind': 'out',
          'category': 'Campo',
          'description': 'Aluguel sábado',
          'amount': 4500,
          'auto': false,
        },
        {
          'id': 'due-a1-2026-11-01',
          'day': '2026-11-10',
          'kind': 'in',
          'category': 'Mensalidade',
          'description': 'novembro · Zé',
          'amount': 3000,
          'auto': true,
        },
      ],
    });
    expect(cash.balanceCents, 4500);
    expect(cash.entries.first.isIn, isFalse);
    expect(cash.entries.last.auto, isTrue);
    expect(cash.entries.last.day, DateTime(2026, 11, 10));
  });

  test('caixa fechado sem o Premium', () {
    final cash = TeamCash.fromMap({'locked': true, 'can_manage': false});
    expect(cash.locked, isTrue);
    expect(cash.entries, isEmpty);
  });

  test('comprovante da mensalidade e da vaquinha', () {
    final dues = PaymentReceipt.fromMap({
      'id': 'r1',
      'kind': 'dues',
      'month': '2026-03-01',
      'payer': 'Zé',
      'image_path': 't/u/1.jpg',
      'status': 'pending',
      'created_at': '2026-03-05T12:00:00Z',
    });
    expect(receiptLabel(dues), 'mensalidade de março');
    final fund = PaymentReceipt.fromMap({
      'id': 'r2',
      'kind': 'fundraiser',
      'fundraiser_id': 'f1',
      'fundraiser': 'Bola',
      'payer': 'Tico',
      'image_path': 't/u/2.jpg',
      'status': 'rejected',
      'note': 'Valor errado',
      'created_at': '2026-03-05T12:00:00Z',
    });
    expect(receiptLabel(fund), 'vaquinha · Bola');
    expect(fund.status, ReceiptStatus.rejected);
  });
}
