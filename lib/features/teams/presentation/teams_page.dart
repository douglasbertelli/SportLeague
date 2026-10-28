import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../data/team_repository.dart';
import 'no_team_placeholder.dart';
import 'team_logo.dart';

/// Meus times: escolhe o time ativo, edita e cria times.
class TeamsPage extends ConsumerWidget {
  const TeamsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teams = ref.watch(myTeamsProvider);
    final selectedId = ref.watch(selectedTeamProvider).value?.id;
    // O técnico e o jogador não criam nem editam times: só escolhem entre os
    // que acompanham.
    final coach = ref.watch(isCoachProvider) || ref.watch(isPlayerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Meus times')),
      floatingActionButton: coach
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.push(Routes.newTeam),
              icon: const Icon(Icons.add),
              label: const Text('Novo time'),
            ),
      body: teams.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: TextButton.icon(
            onPressed: () => ref.invalidate(myTeamsProvider),
            icon: const Icon(Icons.refresh),
            label: const Text('Erro ao carregar os times. Tentar novamente'),
          ),
        ),
        data: (teams) => teams.isEmpty
            ? const NoTeamPlaceholder()
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                children: [
                  for (final team in teams)
                    Card(
                      child: ListTile(
                        leading: TeamLogo(team: team),
                        title: Row(
                          children: [
                            Flexible(child: Text(team.name)),
                            if (team.id == selectedId) ...[
                              const SizedBox(width: 8),
                              Icon(
                                Icons.check_circle,
                                size: 18,
                                semanticLabel: 'Time ativo',
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ],
                          ],
                        ),
                        subtitle: Text(
                          [team.summary, ?team.location].join('\n'),
                        ),
                        isThreeLine: team.location != null,
                        trailing: coach
                            ? null
                            : IconButton(
                                tooltip: 'Editar ${team.name}',
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () =>
                                    context.push(Routes.editTeam, extra: team),
                              ),
                        onTap: () => ref
                            .read(selectedTeamIdProvider.notifier)
                            .select(team.id!),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
