import 'package:flutter/material.dart';

import '../../../core/widgets/theme_mode_button.dart';
import '../../athletes/presentation/athletes_tab.dart';
import '../../games/presentation/games_tab.dart';
import '../../profile/domain/profile.dart';
import '../../profile/presentation/profile_tab.dart';
import 'home_overview.dart';

/// Home do administrador: Início, Jogos, Atletas e Perfil na barra inferior.
/// Cada aba mantém o próprio estado (rolagem etc.) ao trocar de aba.
class AdminHomePage extends StatefulWidget {
  const AdminHomePage({super.key, required this.profile});

  final Profile profile;

  @override
  State<AdminHomePage> createState() => _AdminHomePageState();
}

class _AdminHomePageState extends State<AdminHomePage> {
  static const _tabs = [
    (
      title: 'SportLeague',
      label: 'Início',
      icon: Icons.home_outlined,
      selectedIcon: Icons.home,
    ),
    (
      title: 'Jogos',
      label: 'Jogos',
      icon: Icons.sports_soccer_outlined,
      selectedIcon: Icons.sports_soccer,
    ),
    (
      title: 'Atletas',
      label: 'Atletas',
      icon: Icons.groups_outlined,
      selectedIcon: Icons.groups,
    ),
    (
      title: 'Perfil',
      label: 'Perfil',
      icon: Icons.person_outline,
      selectedIcon: Icons.person,
    ),
  ];

  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_tabs[_index].title),
        actions: const [ThemeModeButton()],
      ),
      body: IndexedStack(
        index: _index,
        children: [
          HomeOverview(profile: widget.profile),
          const GamesTab(),
          const AthletesTab(),
          ProfileTab(profile: widget.profile),
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
