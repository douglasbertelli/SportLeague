import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../data/team_repository.dart';
import 'no_team_placeholder.dart';

/// Meus times: escolhe o time ativo, edita e cria times.
class TeamsPage extends ConsumerWidget {
  const TeamsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teams = ref.watch(myTeamsProvider);
    final selectedId = ref.watch(selectedTeamProvider).value?.id;

    return Scaffold(
      appBar: AppBar(title: const Text('Meus times')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(Routes.newTeam),
        icon: const Icon(Icons.add),
        label: const Text('Novo time'),
      ),
      body: teams.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: TextButton(
            onPressed: () => ref.invalidate(myTeamsProvider),
            child: const Text('Erro ao carregar os times. Tentar novamente'),
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
                        leading: Icon(
                          team.id == selectedId
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          color: team.id == selectedId
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                        title: Text(team.name),
                        subtitle: Text(
                          [team.sport.label, ?team.location].join(' · '),
                        ),
                        trailing: IconButton(
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
