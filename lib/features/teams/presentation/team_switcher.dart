import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../data/team_repository.dart';
import 'team_logo.dart';

/// Título da barra superior com o time ativo; ao tocar, troca de time.
class TeamSwitcher extends ConsumerWidget {
  const TeamSwitcher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final team = ref.watch(selectedTeamProvider).value;
    if (team == null) return const Text('SportLeague');

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (_) => const _TeamSheet(),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TeamLogo(team: team, radius: 17),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                team.name,
                overflow: TextOverflow.ellipsis,
                // Um pouco menor que o título padrão da barra (22).
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontSize: 18),
              ),
            ),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }
}

class _TeamSheet extends ConsumerWidget {
  const _TeamSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teams = ref.watch(myTeamsProvider).value ?? const [];
    final selectedId = ref.watch(selectedTeamProvider).value?.id;

    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          for (final team in teams)
            ListTile(
              leading: TeamLogo(team: team),
              title: Text(team.name),
              subtitle: Text(team.summary),
              trailing: team.id == selectedId ? const Icon(Icons.check) : null,
              selected: team.id == selectedId,
              onTap: () {
                ref.read(selectedTeamIdProvider.notifier).select(team.id!);
                Navigator.of(context).pop();
              },
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Gerenciar times'),
            onTap: () {
              Navigator.of(context).pop();
              context.push(Routes.teams);
            },
          ),
        ],
      ),
    );
  }
}
