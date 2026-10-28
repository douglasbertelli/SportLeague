import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/theme_mode_button.dart';
import '../../athletes/presentation/athletes_tab.dart';
import '../../games/data/games_tab_request.dart';
import '../../games/presentation/games_tab.dart';
import '../../profile/domain/profile.dart';
import '../../profile/presentation/profile_tab.dart';
import '../../profile/presentation/settings_tab.dart';
import '../../teams/presentation/team_search_page.dart';
import '../../teams/presentation/team_switcher.dart';
import 'app_drawer.dart';
import 'home_overview.dart';

/// Home do administrador e do técnico: Início, Jogos, Atletas, Perfil e
/// Config na barra inferior.
/// Jogos e Atletas mostram só os dados do time ativo, escolhido no título.
/// Cada aba mantém o próprio estado (rolagem etc.) ao trocar de aba.
class AdminHomePage extends ConsumerStatefulWidget {
  const AdminHomePage({super.key, required this.profile});

  final Profile profile;

  @override
  ConsumerState<AdminHomePage> createState() => _AdminHomePageState();
}

class _AdminHomePageState extends ConsumerState<AdminHomePage> {
  static const _tabs = [
    (label: 'Início', icon: Icons.home_outlined, selectedIcon: Icons.home),
    (
      label: 'Jogos',
      icon: Icons.sports_soccer_outlined,
      selectedIcon: Icons.sports_soccer,
    ),
    (label: 'Atletas', icon: Icons.groups_outlined, selectedIcon: Icons.groups),
    (label: 'Perfil', icon: Icons.person_outline, selectedIcon: Icons.person),
    (
      label: 'Config',
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
    ),
  ];
  static const _profileIndex = 3;
  static const _settingsIndex = 4;

  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      endDrawer: AppDrawer(profile: widget.profile),
      appBar: AppBar(
        // Início, Jogos e Atletas mostram o time ativo e permitem trocá-lo.
        title: switch (_index) {
          _profileIndex => const Text('Perfil'),
          _settingsIndex => const Text('Configurações'),
          _ => const TeamSwitcher(),
        },
        actions: const [
          TeamSearchButton(),
          ThemeModeButton(),
          AppDrawerButton(),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: [
          HomeOverview(
            profile: widget.profile,
            onOpenGames: (stage) {
              ref.read(gamesTabRequestProvider.notifier).open(stage);
              setState(() => _index = 1);
            },
          ),
          const GamesTab(),
          const AthletesTab(),
          ProfileTab(profile: widget.profile),
          const SettingsTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: [
          for (final tab in _tabs)
            NavigationDestination(
              icon: Icon(tab.icon),
              selectedIcon: Icon(tab.selectedIcon),
              label: tab.label,
            ),
        ],
      ),
    );
  }
}
