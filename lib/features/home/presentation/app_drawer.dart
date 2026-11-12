import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../plans/domain/plan_status.dart';
import '../../plans/presentation/plan_gate.dart';
import '../../profile/domain/profile.dart';
import '../../teams/data/team_repository.dart';

/// Botão ☰ da barra da home, depois do modo claro/escuro: abre o
/// [AppDrawer] (que fica no `endDrawer` do Scaffold).
class AppDrawerButton extends StatelessWidget {
  const AppDrawerButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Menu',
    icon: const Icon(Icons.menu),
    onPressed: () => Scaffold.of(context).openEndDrawer(),
  );
}

/// Menu lateral (☰ no topo da home): as funcionalidades extras do app.
/// Os campeonatos, a vaquinha, a mensalidade e os banners.
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key, required this.profile});

  final Profile profile;

  void _open(BuildContext context, String route) {
    Navigator.of(context).pop();
    context.push(route);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final avatarUrl = profile.avatarUrl;
    return NavigationDrawer(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 16, 16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                foregroundImage: avatarUrl == null
                    ? null
                    : NetworkImage(avatarUrl),
                onForegroundImageError: avatarUrl == null ? null : (_, _) {},
                child: Text(
                  profile.fullName.isEmpty
                      ? '?'
                      : profile.fullName[0].toUpperCase(),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.fullName,
                      style: theme.textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (profile.role case final role?)
                      Text(
                        role.label,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(indent: 28, endIndent: 28),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 28),
          leading: const Icon(Icons.emoji_events_outlined),
          title: const Text('Campeonatos'),
          subtitle: const Text('Pontos corridos, mata-mata ou grupos'),
          onTap: () => _open(context, Routes.championships),
        ),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 28),
          leading: const Icon(Icons.savings_outlined),
          title: const Text('Vaquinha'),
          subtitle: const Text('Dinheiro do time para bola, coletes e mais'),
          onTap: () => _open(context, Routes.fundraisers),
        ),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 28),
          leading: const Icon(Icons.payments_outlined),
          title: const Text('Mensalidade'),
          subtitle: const Text('Quem pagou o mês e quem está devendo'),
          onTap: () => _open(context, Routes.dues),
        ),
        // Banners do time ativo, para quem administra (Premium). O aviso do
        // plano aparece por cima do menu; liberado, fecha o menu e abre.
        Consumer(
          builder: (context, ref, _) => !ref.watch(canManageTeamProvider)
              ? const SizedBox.shrink()
              : ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 28),
                  leading: const Icon(Icons.auto_awesome_outlined),
                  title: const Text('Banners'),
                  subtitle: const Text(
                    'Jogo, resultado, convocação e mais para as redes',
                  ),
                  onTap: () async {
                    if (!await ensurePlanAllows(
                          context,
                          ref,
                          PlanFeature.banners,
                        ) ||
                        !context.mounted) {
                      return;
                    }
                    _open(context, Routes.banners);
                  },
                ),
        ),
      ],
    );
  }
}
