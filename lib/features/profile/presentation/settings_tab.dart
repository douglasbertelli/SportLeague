import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/security/biometric_tile.dart';
import '../../../core/security/biometrics.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../../../core/theme/app_color_picker.dart';
import '../../../core/widgets/theme_mode_button.dart';
import '../../address/data/address_repository.dart';
import '../../auth/data/biometric_sign_in.dart';
import '../data/profile_repository.dart';
import 'edit_text_sheet.dart';
import 'profile_tab.dart';

/// Aba Config do jogador: o cabeçalho compacto (foto, nome, e-mail e tipo de
/// perfil); num grupo, o nome, Meu código, a cor do time, o tema, a
/// biometria e o endereço; e, à parte, o Sair.
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
      const ThemeModeTile(),
      // Some em aparelhos sem biometria cadastrada.
      if (ref.watch(biometricsAvailableProvider).value ?? false)
        const BiometricTile(),
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

    // O mesmo visual do Perfil do administrador e do técnico: o cabeçalho
    // compacto, os itens num grupo e o Sair à parte.
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (profile != null) ...[
          ProfileHeader(profile: profile, email: email),
          const SizedBox(height: 16),
        ],
        SettingsGroup(items: items),
        const SizedBox(height: 32),
        Card(
          child: ListTile(
            leading: Icon(Icons.logout, color: theme.colorScheme.error),
            title: Text(
              'Sair',
              style: TextStyle(color: theme.colorScheme.error),
            ),
            // Com a biometria ligada, guarda a conta para voltar com ela.
            onTap: () => signOutOrPark(ref),
          ),
        ),
      ],
    );
  }
}
