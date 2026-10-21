import 'package:flutter_test/flutter_test.dart';
import 'package:sport_league/core/utils/error_messages.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('falha de rede no login não é tratada como senha inválida', () {
    final error = AuthRetryableFetchException(
      message: 'ClientException: Failed to fetch, uri=https://x.supabase.co/auth/v1/token?grant_type=password',
    );
    expect(friendlyErrorMessage(error), contains('Verifique sua conexão'));
  });

  test('credenciais inválidas', () {
    const error = AuthApiException(
      'Invalid login credentials',
      statusCode: '400',
      code: 'invalid_credentials',
    );
    expect(friendlyErrorMessage(error), 'E-mail ou senha incorretos.');
  });

  test('senha fraca', () {
    final error = AuthWeakPasswordException(
      message: 'Password should be at least 8 characters.',
      statusCode: '422',
      reasons: const ['length'],
    );
    expect(friendlyErrorMessage(error), contains('Senha fraca'));
  });

  test('e-mail recusado pelo Supabase', () {
    const error = AuthApiException(
      'Email address "ana@teste.dev" is invalid',
      statusCode: '400',
      code: 'email_address_invalid',
    );
    expect(
      friendlyErrorMessage(error),
      contains('Este e-mail não pode ser usado'),
    );
  });
}
