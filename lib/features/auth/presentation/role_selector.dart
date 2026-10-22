import 'package:flutter/material.dart';

import '../../profile/domain/profile.dart';

/// Seleção obrigatória do tipo de perfil, logo depois de criar a conta.
class RoleSelector extends FormField<UserRole> {
  RoleSelector({super.key, super.onSaved})
    : super(
        validator: (value) => value == null ? 'Escolha o tipo de perfil' : null,
        builder: (state) {
          final theme = Theme.of(state.context);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Tipo de perfil', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final role in UserRole.values) ...[
                _RoleCard(
                  role: role,
                  selected: state.value == role,
                  onTap: () => state.didChange(role),
                ),
                const SizedBox(height: 8),
              ],
              if (state.hasError)
                Text(
                  state.errorText!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
            ],
          );
        },
      );
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.role,
    required this.selected,
    required this.onTap,
  });

  final UserRole role;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      color: selected ? colorScheme.primaryContainer : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? colorScheme.primary : colorScheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Icon(
          role == UserRole.admin ? Icons.shield_outlined : Icons.directions_run,
        ),
        title: Text(role.label),
        subtitle: Text(role.description),
        trailing: Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
          color: selected ? colorScheme.primary : null,
        ),
      ),
    );
  }
}
