import 'package:flutter_test/flutter_test.dart';
import 'package:sport_league/core/utils/pix.dart';

void main() {
  test('BR Code do exemplo do Banco Central', () {
    expect(
      pixPayload(
        key: '123e4567-e12b-12d1-a456-426655440000',
        name: 'Fulano de Tal',
        city: 'BRASILIA',
      ),
      '00020126580014br.gov.bcb.pix0136123e4567-e12b-12d1-a456-426655440000'
      '5204000053039865802BR5913Fulano de Tal6008BRASILIA62070503***63041D3D',
    );
  });

  test('com valor, sem acentos e no tamanho máximo', () {
    final code = pixPayload(
      key: 'time@exemplo.com',
      name: 'Grêmio Esportivo União da Vila Nova',
      city: 'São Paulo',
      amountCents: 3050,
    );
    expect(code, contains('540530.50'));
    expect(code, contains('5925Gremio Esportivo Uniao d'));
    expect(code, contains('6009Sao Paulo'));
    expect(code.substring(code.length - 8, code.length - 4), '6304');
  });
}
