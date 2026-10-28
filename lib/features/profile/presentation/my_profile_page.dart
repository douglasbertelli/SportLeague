import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/profile_repository.dart';
import 'profile_tab.dart';

/// Meu perfil do jogador, que não tem a barra inferior do administrador e do
/// técnico: a mesma [ProfileTab], numa tela própria.
class MyProfilePage extends ConsumerWidget {
  const MyProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentProfileProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Meu perfil')),
      body: switch (profile) {
        AsyncValue(value: final profile?) => ProfileTab(profile: profile),
        AsyncError() => Center(
          child: TextButton.icon(
            onPressed: () => ref.invalidate(currentProfileProvider),
            icon: const Icon(Icons.refresh),
            label: const Text('Erro ao carregar o perfil. Tentar novamente'),
          ),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}
