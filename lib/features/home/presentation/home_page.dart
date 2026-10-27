import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/widgets/theme_mode_button.dart';
import '../../auth/data/auth_repository.dart';
import '../../profile/data/profile_repository.dart';
import '../../teams/presentation/team_search_page.dart';
import 'admin_home_page.dart';
import 'app_drawer.dart';
import 'home_overview.dart';

/// Tela inicial. O administrador tem navegação por abas; o jogador, por
/// enquanto, só a tela de boas-vindas.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentProfileProvider);
    if (profile.value case final admin? when admin.hasTeamHome) {
      return AdminHomePage(profile: admin);
    }

    return Scaffold(
      endDrawer: switch (profile.value) {
        final profile? => AppDrawer(profile: profile),
        null => null,
      },
      appBar: AppBar(
        title: const Text('SportLeague'),
        actions: [
          const TeamSearchButton(),
          const ThemeModeButton(),
          if (profile.value != null) const AppDrawerButton(),
          IconButton(
            tooltip: 'Editar endereço',
            icon: const Icon(Icons.location_on_outlined),
            onPressed: () => context.push(Routes.editAddress),
          ),
          IconButton(
            tooltip: 'Sair',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authRepositoryProvider).signOut(),
          ),
        ],
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
        data: (profile) => profile == null
            ? const Center(child: Text('Perfil não encontrado.'))
            : HomeOverview(profile: profile),
      ),
    );
  }
}
