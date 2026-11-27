import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/widgets/confirm_dialog.dart';
import '../data/app_update.dart';

/// Build abaixo do mínimo (`app_versions`): só dá para ir à loja atualizar.
class UpdateRequiredPage extends ConsumerWidget {
  const UpdateRequiredPage({super.key});

  Future<void> _openStore(BuildContext context, String url) async {
    final opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && context.mounted) {
      showErrorSnackBar(context, 'Não foi possível abrir a loja.');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final storeUrl = ref.watch(minVersionProvider).value?.storeUrl;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.system_update_outlined,
                  size: 64,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'Atualize o SportLeague',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'Esta versão do app não é mais compatível. Atualize pela '
                  'loja para continuar usando.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 32),
                if (storeUrl != null)
                  FilledButton.icon(
                    onPressed: () => _openStore(context, storeUrl),
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Atualizar na loja'),
                  )
                else
                  Text(
                    'Procure o SportLeague na loja do seu celular.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
