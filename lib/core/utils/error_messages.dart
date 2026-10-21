import 'package:supabase_flutter/supabase_flutter.dart';

/// Converte erros do Supabase em mensagens amigáveis em português.
String friendlyErrorMessage(Object error) {
  if (error is AuthException) {
    final message = error.message.toLowerCase();
    if (message.contains('invalid login credentials')) {
      return 'E-mail ou senha incorretos.';
    }
    if (message.contains('email not confirmed')) {
      return 'Confirme seu e-mail antes de entrar.';
    }
    if (message.contains('already registered') ||
        message.contains('already been registered')) {
      return 'Este e-mail já está cadastrado.';
    }
    if (message.contains('password')) {
      return 'Senha inválida. Use pelo menos 8 caracteres.';
    }
    if (error.statusCode == '429') {
      return 'Muitas tentativas. Aguarde um pouco e tente novamente.';
    }
    return error.message;
  }
  if (error is PostgrestException) {
    return 'Não foi possível salvar os dados. Tente novamente.';
  }
  return 'Algo deu errado. Verifique sua conexão e tente novamente.';
}
