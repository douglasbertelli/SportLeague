import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../../core/widgets/app_logo.dart';
import '../../address/data/address_repository.dart';
import '../../auth/data/auth_repository.dart';

/// Exibida enquanto a sessão e o endereço carregam, ou se o carregamento falhar.
class SplashPage extends ConsumerWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasError =
        ref.watch(authSessionProvider).hasError ||
        ref.watch(myAddressProvider).hasError;

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppLogo(),
              const SizedBox(height: 32),
              if (!hasError)
                const CircularProgressIndicator()
              else ...[
                const Text(
                  'Não foi possível carregar seus dados.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(myAddressProvider),
                  child: const Text('Tentar novamente'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => ref.read(authRepositoryProvider).signOut(),
                  child: const Text('Sair'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
