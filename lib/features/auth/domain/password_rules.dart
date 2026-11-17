/// Regras da senha no cadastro, as mesmas do site (sportleague-web,
/// `src/lib/password.ts`): mínimo 8, letras maiúsculas e minúsculas, números
/// e símbolos, e sem o e-mail.
class PasswordRule {
  const PasswordRule(this.id, this.label, this.shortLabel, this.test);

  final String id;

  /// Texto completo, usado na mensagem de erro do campo.
  final String label;

  /// Texto curto, para a lista compacta abaixo do campo.
  final String shortLabel;
  final bool Function(String password) test;
}

final passwordRules = <PasswordRule>[
  PasswordRule(
    'length',
    'Pelo menos 8 caracteres',
    '8+ caracteres',
    (p) => p.length >= 8,
  ),
  PasswordRule(
    'upper',
    'Uma letra maiúscula',
    'Maiúscula',
    (p) => p.contains(_upper),
  ),
  PasswordRule(
    'lower',
    'Uma letra minúscula',
    'Minúscula',
    (p) => p.contains(_lower),
  ),
  PasswordRule('digit', 'Um número', 'Número', (p) => p.contains(_digit)),
  PasswordRule(
    'symbol',
    'Um símbolo (ex.: ! @ # \$ %)',
    'Símbolo (!@#\$%)',
    (p) => p.contains(_symbol),
  ),
];

final _upper = RegExp('[A-Z]');
final _lower = RegExp('[a-z]');
final _digit = RegExp(r'\d');
final _symbol = RegExp(r'[^A-Za-z0-9\s]');

/// A parte do e-mail antes do @ (com 4 letras ou mais) não pode estar na
/// senha: é a primeira coisa que alguém tenta.
bool passwordContainsEmail(String password, String email) {
  final user = email.trim().split('@').first.toLowerCase();
  return user.length >= 4 && password.toLowerCase().contains(user);
}

/// Primeiro problema da senha, ou `null` se ela é forte.
String? passwordProblem(String password, [String email = '']) {
  if (password.isEmpty) return 'Informe sua senha';
  for (final rule in passwordRules) {
    if (!rule.test(password)) {
      return 'A senha precisa ter: ${rule.label.toLowerCase()}.';
    }
  }
  if (passwordContainsEmail(password, email)) {
    return 'A senha não pode conter o seu e-mail.';
  }
  return null;
}

/// 0 a 4, para a barra de força: as regras cumpridas, com bônus pelo
/// tamanho.
int passwordScore(String password) {
  if (password.isEmpty) return 0;
  final passed = passwordRules.where((rule) => rule.test(password)).length;
  if (passed < 3) return 1;
  if (passed < passwordRules.length) return 2;
  return password.length >= 12 ? 4 : 3;
}
