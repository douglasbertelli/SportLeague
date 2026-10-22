import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/widgets/empty_state.dart';
import '../../teams/data/team_repository.dart';
import '../../teams/presentation/no_team_placeholder.dart';
import '../data/athlete_repository.dart';

/// Aba Atletas do administrador: atletas do time ativo.
class AthletesTab extends ConsumerWidget {
  const AthletesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final team = ref.watch(selectedTeamProvider);
    return switch (team) {
      AsyncValue(value: final team?) => _AthleteList(teamId: team.id!),
      AsyncValue(hasValue: true) => const NoTeamPlaceholder(),
      AsyncValue(hasError: true) => Center(
        child: TextButton(
          onPressed: () => ref.invalidate(myTeamsProvider),
          child: const Text('Erro ao carregar os times. Tentar novamente'),
        ),
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

class _AthleteList extends ConsumerWidget {
  const _AthleteList({required this.teamId});

  final String teamId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final athletes = ref.watch(teamAthletesProvider(teamId));

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'new-athlete',
        onPressed: () => context.push(Routes.newAthlete),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Novo atleta'),
      ),
      body: athletes.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: TextButton(
            onPressed: () => ref.invalidate(teamAthletesProvider(teamId)),
            child: const Text('Erro ao carregar os atletas. Tentar novamente'),
          ),
        ),
        data: (athletes) => athletes.isEmpty
            ? const EmptyState(
                icon: Icons.groups,
                title: 'Nenhum atleta neste time',
                message: 'Cadastre os atletas do time pelo botão abaixo.',
              )
            : RefreshIndicator(
                onRefresh: () =>
                    ref.refresh(teamAthletesProvider(teamId).future),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  children: [
                    Text(
                      athletes.length == 1
                          ? '1 atleta'
                          : '${athletes.length} atletas',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    for (final athlete in athletes)
                      Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            child: Text(
                              athlete.jerseyNumber?.toString() ??
                                  athlete.name[0].toUpperCase(),
                            ),
                          ),
                          title: Text(athlete.name),
                          subtitle: athlete.position == null
                              ? null
                              : Text(athlete.position!),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () =>
                              context.push(Routes.editAthlete, extra: athlete),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}
