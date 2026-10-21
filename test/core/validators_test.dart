import 'package:flutter_test/flutter_test.dart';
import 'package:sport_league/core/utils/validators.dart';

void main() {
  group('Validators', () {
    test('email', () {
      expect(Validators.email(''), isNotNull);
      expect(Validators.email('joao@'), isNotNull);
      expect(Validators.email('joao@time.com'), isNull);
    });

    test('password exige 8 caracteres', () {
      expect(Validators.password('1234567'), isNotNull);
      expect(Validators.password('12345678'), isNull);
    });

    test('zipCode aceita 8 dígitos com ou sem máscara', () {
      expect(Validators.zipCode('0131000'), isNotNull);
      expect(Validators.zipCode('01310-000'), isNull);
      expect(Validators.zipCode('01310000'), isNull);
    });

    test('state exige UF de 2 letras', () {
      expect(Validators.state('S'), isNotNull);
      expect(Validators.state('S1'), isNotNull);
      expect(Validators.state('sp'), isNull);
    });
  });
}
