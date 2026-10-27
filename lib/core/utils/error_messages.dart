import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _connectionError =
    'Algo deu errado. Verifique sua conexão e tente novamente.';

/// Converte erros do Supabase e do login social em mensagens amigáveis em
/// português.
String friendlyErrorMessage(Object error) {
  if (error is AuthRetryableFetchException || error is AuthUnknownException) {
    // Falha de rede: a mensagem traz a URL da requisição, não o motivo.
    return _connectionError;
  }
  if (error is AuthException) {
    final code = error.code;
    final message = error.message.toLowerCase();
    if (code == 'invalid_credentials' ||
        message.contains('invalid login credentials')) {
      return 'E-mail ou senha incorretos.';
    }
    if (code == 'email_not_confirmed' ||
        message.contains('email not confirmed')) {
      return 'Confirme seu e-mail antes de entrar.';
    }
    if (code == 'user_already_exists' ||
        message.contains('already registered')) {
      return 'Este e-mail já está cadastrado.';
    }
    if (code == 'email_address_invalid' ||
        code == 'email_address_not_authorized') {
      return 'Este e-mail não pode ser usado. Verifique o endereço.';
    }
    if (error is AuthWeakPasswordException || code == 'weak_password') {
      return 'Senha fraca. Use pelo menos 8 caracteres.';
    }
    if (error.statusCode == '429') {
      return 'Muitas tentativas. Aguarde um pouco e tente novamente.';
    }
    return error.message;
  }
  if (error is PostgrestException) {
    // Número de camisa repetido no time (índice team_players_unique_number).
    if (error.code == '23505' &&
        error.message.contains('team_players_unique_number')) {
      return 'Já existe um atleta com esse número no time.';
    }
    return 'Não foi possível salvar os dados. Tente novamente.';
  }
  if (error is GoogleSignInException) {
    return 'Não foi possível entrar com o Google. Tente novamente.';
  }
  if (error is SignInWithAppleException) {
    return 'Não foi possível entrar com a Apple. Tente novamente.';
  }
  return _connectionError;
}
