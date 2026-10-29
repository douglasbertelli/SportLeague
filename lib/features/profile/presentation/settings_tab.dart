import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../../../core/theme/app_color_picker.dart';
import '../../address/data/address_repository.dart';
import '../../auth/data/auth_repository.dart';
import '../data/profile_repository.dart';
import 'edit_text_sheet.dart';

/// Aba Config (barra inferior de todos): a conta (e-mail, tipo de perfil e,
/// do administrador, o plano), Meu código (jogador e técnico), a cor do time, o endereço e, à
/// parte, o Sair.
class SettingsTab extends ConsumerWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final profile = ref.watch(currentProfileProvider).value;
    final email = ref.watch(supabaseClientProvider).auth.currentUser?.email;
    final address = ref.watch(myAddressProvider).value;

    final items = [
      // O jogador troca o nome completo aqui; no Perfil aparece o apelido.
      if (profile != null && profile.isPlayer)
        ListTile(
          leading: const Icon(Icons.badge_outlined),
          title: const Text('Nome'),
          subtitle: Text(profile.fullName),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => editFullName(context, ref, profile),
        ),
      if (profile?.code case final code?)
        ListTile(
          leading: const Icon(Icons.qr_code_2),
          title: const Text('Meu código'),
          subtitle: Text('$code · para o administrador te convidar'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(Routes.myCode),
        ),
      const AppColorTile(),
      ListTile(
        leading: const Icon(Icons.location_on_outlined),
        title: const Text('Endereço'),
        subtitle: address == null
            ? null
            : Text(
                '${address.street}, ${address.number} - '
                '${address.city}/${address.state}',
              ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push(Routes.editAddress),
      ),
    ];

    // Itens mais altos, com folga em volta do ícone e do texto.
    return ListTileTheme(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      minVerticalPadding: 12,
      horizontalTitleGap: 20,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // A conta: com que e-mail entrou, o tipo de perfil e o plano.
          Card(
            child: ListTile(
              leading: const Icon(Icons.account_circle_outlined),
              title: Text(email ?? 'Conta'),
              subtitle: Text(
                [
                  ?profile?.role?.label,
                  // Só o administrador tem plano.
                  if (profile != null && profile.isAdmin)
                    'Plano ${profile.plan.label}',
                ].join(' · '),
              ),
            ),
          ),
          // Um card por item, com espaço entre eles, como nas configurações do
          // sistema.
          for (final item in items) ...[
            const SizedBox(height: 8),
            Card(child: item),
          ],
          const SizedBox(height: 32),
          Card(
            child: ListTile(
              leading: Icon(Icons.logout, color: theme.colorScheme.error),
              title: Text(
                'Sair',
                style: TextStyle(color: theme.colorScheme.error),
              ),
              onTap: () => ref.read(authRepositoryProvider).signOut(),
            ),
          ),
        ],
      ),
    );
  }
}
