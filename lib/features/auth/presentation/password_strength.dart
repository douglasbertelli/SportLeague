import 'package:flutter/material.dart';

import '../domain/password_rules.dart';

/// Barra de força e a lista das regras, que vão ficando marcadas enquanto a
/// senha é digitada (igual ao cadastro do site).
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
    final small = theme.textTheme.bodySmall;

    return Container(
      padding: const EdgeInsets.all(16),
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
                if (n > 1) const SizedBox(width: 6),
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 6,
                    decoration: BoxDecoration(
                      color: n <= score
                          ? color
                          : scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ],
              SizedBox(
                width: 88,
                child: Text(
                  label,
                  textAlign: TextAlign.right,
                  style: small?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final rule in passwordRules)
            _RuleRow(ok: rule.test(password), label: rule.label),
          if (hasEmail)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Icon(Icons.error_outline, size: 16, color: scheme.error),
                  const SizedBox(width: 8),
                  Text(
                    'Não use o seu e-mail na senha',
                    style: small?.copyWith(color: scheme.error),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _RuleRow extends StatelessWidget {
  const _RuleRow({required this.ok, required this.label});

  final bool ok;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: ok ? scheme.primary : null,
              border: ok ? null : Border.all(color: scheme.outline),
            ),
            child: ok
                ? Icon(Icons.check, size: 11, color: scheme.onPrimary)
                : null,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: ok ? scheme.onSurface : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
