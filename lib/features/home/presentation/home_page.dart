import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/theme_mode_button.dart';
import '../../profile/data/profile_repository.dart';
import 'admin_home_page.dart';
import 'player_home_page.dart';

/// Tela inicial. Todos têm navegação por abas: o administrador e o técnico,
/// Início, Jogos, Atletas e Perfil; o jogador, Início e Perfil.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentProfileProvider);
    if (profile.value case final loaded?) {
      return loaded.hasTeamHome
          ? AdminHomePage(profile: loaded)
          : PlayerHomePage(profile: loaded);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('SportLeague'),
        actions: const [ThemeModeButton()],
      ),
      body: profile.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: TextButton.icon(
            onPressed: () => ref.invalidate(currentProfileProvider),
            icon: const Icon(Icons.refresh),
            label: const Text('Erro ao carregar o perfil. Tentar novamente'),
          ),
        ),
        data: (_) => const Center(child: Text('Perfil não encontrado.')),
      ),
    );
  }
}
