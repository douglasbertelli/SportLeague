abstract final class Validators {
  static final _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  static String? required(
    String? value, {
    String message = 'Campo obrigatório',
  }) {
    if (value == null || value.trim().isEmpty) return message;
    return null;
  }

  static String? fullName(String? value) {
    final error = required(value, message: 'Informe seu nome');
    if (error != null) return error;
    if (value!.trim().length < 2) return 'Nome muito curto';
    return null;
  }

  static String? email(String? value) {
    final error = required(value, message: 'Informe seu e-mail');
    if (error != null) return error;
    if (!_emailRegex.hasMatch(value!.trim())) return 'E-mail inválido';
    return null;
  }

  static String? password(String? value) {
    if (value == null || value.isEmpty) return 'Informe sua senha';
    if (value.length < 8) return 'A senha deve ter pelo menos 8 caracteres';
    return null;
  }

  static String? zipCode(String? value) {
    final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return 'Informe o CEP';
    if (digits.length != 8) return 'CEP deve ter 8 dígitos';
    return null;
  }

  static String? state(String? value) {
    final error = required(value, message: 'Informe a UF');
    if (error != null) return error;
    if (!RegExp(r'^[A-Za-z]{2}$').hasMatch(value!.trim())) return 'UF inválida';
    return null;
  }

  static String? optionalState(String? value) =>
      value == null || value.trim().isEmpty ? null : state(value);

  /// Texto obrigatório com pelo menos 2 caracteres (nome de time, atleta,
  /// adversário).
  static String? name(String? value, {required String message}) {
    final error = required(value, message: message);
    if (error != null) return error;
    if (value!.trim().length < 2) return 'Muito curto';
    return null;
  }
}
