import 'package:flutter_test/flutter_test.dart';
import 'package:sport_league/features/auth/domain/password_rules.dart';

void main() {
  test('exige 8 caracteres, maiúscula, minúscula, número e símbolo', () {
    expect(passwordProblem(''), 'Informe sua senha');
    expect(passwordProblem('Ab1!'), contains('pelo menos 8 caracteres'));
    expect(passwordProblem('abcdef1!'), contains('maiúscula'));
    expect(passwordProblem('ABCDEF1!'), contains('minúscula'));
    expect(passwordProblem('Abcdefg!'), contains('número'));
    expect(passwordProblem('Abcdefg1'), contains('símbolo'));
    expect(passwordProblem('Abcdef1!'), isNull);
  });

  test('não aceita o e-mail (antes do @, com 4 letras ou mais) na senha', () {
    expect(passwordProblem('Maria#2024', 'maria@x.com'), contains('e-mail'));
    expect(passwordProblem('Ana#20245', 'ana@x.com'), isNull);
  });

  test('força: fraca, média, forte e muito forte', () {
    expect(passwordScore(''), 0);
    expect(passwordScore('abc'), 1);
    expect(passwordScore('senha1234'), 2);
    expect(passwordScore('Senha@12'), 3);
    expect(passwordScore('Senha@123456'), 4);
  });
}
