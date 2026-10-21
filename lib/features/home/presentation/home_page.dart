import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/widgets/theme_mode_button.dart';
import '../../auth/data/auth_repository.dart';
import '../../profile/data/profile_repository.dart';
import '../../profile/domain/profile.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentProfileProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('SportLeague'),
        actions: [
          const ThemeModeButton(),
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
          child: TextButton(
            onPressed: () => ref.invalidate(currentProfileProvider),
            child: const Text('Erro ao carregar o perfil. Tentar novamente'),
          ),
        ),
        data: (profile) => profile == null
            ? const Center(child: Text('Perfil não encontrado.'))
            : _HomeContent(profile: profile),
      ),
    );
  }
}

class _HomeContent extends StatelessWidget {
  const _HomeContent({required this.profile});

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
            Chip(label: Text(profile.role.label)),
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
