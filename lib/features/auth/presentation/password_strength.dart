import 'package:flutter/material.dart';

import '../domain/password_rules.dart';

/// Card compacto abaixo do campo de senha, com a barra de força e as regras,
/// que vão ficando marcadas enquanto a senha é digitada (as mesmas do site).
class PasswordStrength extends StatelessWidget {
  const PasswordStrength({
    super.key,
    required this.password,
    required this.email,
  });

  final String password;
  final String email;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final score = passwordScore(password);
    final (label, color) = switch (score) {
      1 => ('Fraca', scheme.error),
      2 => ('Média', Colors.orange.shade600),
      3 => ('Forte', scheme.primary),
      4 => ('Muito forte', scheme.primary),
      _ => ('Força da senha', scheme.onSurfaceVariant),
    };
    final hasEmail =
        password.isNotEmpty && passwordContainsEmail(password, email);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (var n = 1; n <= 4; n++) ...[
                if (n > 1) const SizedBox(width: 4),
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 4,
                    decoration: BoxDecoration(
                      color: n <= score
                          ? color
                          : scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 12),
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              for (final rule in passwordRules)
                _Rule(ok: rule.test(password), label: rule.shortLabel),
              if (hasEmail)
                const _Rule(ok: false, label: 'Sem o seu e-mail', error: true),
            ],
          ),
        ],
      ),
    );
  }
}

class _Rule extends StatelessWidget {
  const _Rule({required this.ok, required this.label, this.error = false});

  final bool ok;
  final String label;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = error
        ? scheme.error
        : ok
        ? scheme.primary
        : scheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          error
              ? Icons.error_outline
              : ok
              ? Icons.check_circle
              : Icons.radio_button_unchecked,
          size: 14,
          color: color,
        ),
        const SizedBox(width: 4),
        Text(label, style: theme.textTheme.bodySmall?.copyWith(color: color)),
      ],
    );
  }
}
