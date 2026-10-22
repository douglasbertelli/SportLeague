import 'package:flutter/material.dart';

import '../../profile/domain/profile.dart';

/// Boas-vindas com o resumo do perfil e as ações de cada tipo de perfil.
class HomeOverview extends StatelessWidget {
  const HomeOverview({super.key, required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final actions = profile.isAdmin
        ? const [
            _ActionTile(icon: Icons.groups, title: 'Meus times'),
            _ActionTile(
              icon: Icons.person_add_alt,
              title: 'Cadastrar jogadores',
            ),
            _ActionTile(icon: Icons.mail_outline, title: 'Convites enviados'),
          ]
        : const [
            _ActionTile(icon: Icons.search, title: 'Buscar times'),
            _ActionTile(icon: Icons.mail_outline, title: 'Meus convites'),
          ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Olá, ${profile.fullName.split(' ').first}!',
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            if (profile.role case final role?) Chip(label: Text(role.label)),
            Chip(label: Text('Plano ${profile.plan.label}')),
            const Chip(
              avatar: Icon(Icons.sports_soccer, size: 18),
              label: Text('Futebol'),
            ),
          ],
        ),
        const SizedBox(height: 24),
        ...actions,
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: const Text('Em breve'),
        enabled: false,
      ),
    );
  }
}
