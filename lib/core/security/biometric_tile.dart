import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/preferences_provider.dart';
import '../widgets/app_sheet.dart';
import 'biometrics.dart';

/// Item "Entrar com biometria" do Perfil (administrador e técnico) e do
/// Config (jogador); só entra na lista com biometria cadastrada no aparelho
/// ([biometricsAvailableProvider]).
class BiometricTile extends ConsumerWidget {
  const BiometricTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(biometricLockProvider);
    return SwitchListTile(
      secondary: const Icon(Icons.fingerprint),
      title: const Text('Entrar com biometria'),
      subtitle: const Text('Digital ou rosto em vez da senha'),
      value: enabled,
      onChanged: (value) => setBiometricLock(ref, value),
    );
  }
}

/// Liga (depois de confirmar a digital ou o rosto) ou desliga.
Future<void> setBiometricLock(WidgetRef ref, bool enabled) async {
  if (enabled &&
      !await ref
          .read(biometricsProvider)
          .authenticate('Confirme para entrar com biometria')) {
    return;
  }
  await ref.read(biometricLockProvider.notifier).set(enabled);
}

/// Depois do login, oferece uma vez ligar a biometria (se o aparelho tem e
/// ela ainda está desligada).
Future<void> offerBiometrics(BuildContext context, WidgetRef ref) async {
  final preferences = ref.read(sharedPreferencesProvider);
  if (ref.read(biometricLockProvider) ||
      (preferences.getBool(BiometricLock.offeredKey) ?? false) ||
      !await ref.read(biometricsAvailableProvider.future)) {
    return;
  }
  await preferences.setBool(BiometricLock.offeredKey, true);
  if (!context.mounted) return;
  final accepted = await showAppSheet<bool>(
    context,
    builder: (context) => AppSheet(
      title: 'Entrar com biometria?',
      message:
          'Ao abrir o app, e mesmo depois de sair da conta, entre com a '
          'digital ou o rosto em vez da senha. Dá para mudar depois em Perfil '
          'ou Config.',
      body: const Icon(Icons.fingerprint, size: 56),
      actions: [
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Usar biometria'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Agora não'),
        ),
      ],
    ),
  );
  if (accepted == true) await setBiometricLock(ref, true);
}
