import 'package:flutter/material.dart';

import '../../../core/widgets/theme_mode_button.dart';
import '../../profile/domain/profile.dart';
import '../../profile/presentation/profile_tab.dart';
import '../../profile/presentation/settings_tab.dart';
import '../../teams/presentation/team_search_page.dart';
import 'app_drawer.dart';
import 'home_overview.dart';

/// Home do jogador: Início, Perfil e Config na barra inferior, como a do
/// administrador e do técnico. Cada aba mantém o próprio estado ao trocar.
class PlayerHomePage extends StatefulWidget {
  const PlayerHomePage({super.key, required this.profile});

  final Profile profile;

  @override
  State<PlayerHomePage> createState() => _PlayerHomePageState();
}

class _PlayerHomePageState extends State<PlayerHomePage> {
  static const _tabs = [
    (label: 'Início', icon: Icons.home_outlined, selectedIcon: Icons.home),
    (label: 'Perfil', icon: Icons.person_outline, selectedIcon: Icons.person),
    (
      label: 'Config',
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
    ),
  ];
  static const _profileIndex = 1;
  static const _settingsIndex = 2;

  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      endDrawer: AppDrawer(profile: widget.profile),
      appBar: AppBar(
        // No Início, a foto e o nome do jogador (o time do painel troca pelos
        // chips de Meus números).
        title: switch (_index) {
          _profileIndex => const Text('Perfil'),
          _settingsIndex => const Text('Configurações'),
          _ => _PlayerTitle(profile: widget.profile),
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
          HomeOverview(profile: widget.profile),
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

/// Foto (ou as iniciais) e apelido do jogador, no título do Início.
class _PlayerTitle extends StatelessWidget {
  const _PlayerTitle({required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context) {
    final avatarUrl = profile.avatarUrl;
    final initials = profile.fullName
        .split(' ')
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();
    return Row(
      children: [
        CircleAvatar(
          radius: 16,
          foregroundImage: avatarUrl == null ? null : NetworkImage(avatarUrl),
          onForegroundImageError: avatarUrl == null ? null : (_, _) {},
          child: Text(initials, style: const TextStyle(fontSize: 12)),
        ),
        const SizedBox(width: 12),
        Flexible(
          // O apelido (ou o nome, sem apelido), como no Perfil.
          child: Text(profile.displayName, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}
