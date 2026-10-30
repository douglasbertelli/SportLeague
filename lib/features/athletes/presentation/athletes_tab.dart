import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/empty_state.dart';
import '../../teams/data/team_repository.dart';
import '../../teams/presentation/no_team_placeholder.dart';
import '../data/athlete_repository.dart';
import '../domain/athlete.dart';

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
        child: TextButton.icon(
          onPressed: () => ref.invalidate(myTeamsProvider),
          icon: const Icon(Icons.refresh),
          label: const Text('Erro ao carregar os times. Tentar novamente'),
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
      // Só o dono cadastra e convida atletas (o técnico vê o elenco).
      floatingActionButton: ref.watch(canManageTeamProvider)
          ? FloatingActionButton(
              heroTag: 'add-athlete',
              tooltip: 'Adicionar atleta',
              onPressed: () => _showAddOptions(context),
              child: const Icon(Icons.person_add_alt),
            )
          : null,
      body: athletes.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: TextButton.icon(
            onPressed: () => ref.invalidate(teamAthletesProvider(teamId)),
            icon: const Icon(Icons.refresh),
            label: const Text('Erro ao carregar os atletas. Tentar novamente'),
          ),
        ),
        data: (athletes) => athletes.isEmpty
            ? const EmptyState(
                icon: Icons.groups,
                title: 'Nenhum atleta neste time',
                message:
                    'Cadastre os atletas ou convide jogadores do app pelo '
                    'botão abaixo.',
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
                          leading: _AthletePhoto(athlete: athlete),
                          title: Text(athlete.displayName),
                          subtitle: switch ([
                            ?athlete.position,
                            if (athlete.jerseyNumber case final number?)
                              'Nº $number',
                          ]) {
                            [] => null,
                            final parts => Text(parts.join(' · ')),
                          },
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.push(
                            Routes.athleteProfile,
                            extra: athlete,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}

/// Como adicionar: cadastrar o atleta à mão ou convidar um jogador que já usa
/// o app (pela busca de nome ou código).
Future<void> _showAddOptions(BuildContext context) async {
  final route = await showAppSheet<String>(
    context,
    builder: (context) => AppSheet(
      title: 'Adicionar atleta',
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.person_add_alt),
            title: const Text('Novo atleta'),
            subtitle: const Text('Cadastre com nome, posição e camisa'),
            onTap: () => Navigator.of(context).pop(Routes.newAthlete),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.person_search_outlined),
            title: const Text('Convidar jogador'),
            subtitle: const Text(
              'Busque quem já usa o app pelo nome ou código',
            ),
            onTap: () => Navigator.of(context).pop(Routes.invitePlayer),
          ),
        ],
      ),
    ),
  );
  if (route != null && context.mounted) context.push(route);
}

/// Foto do atleta; sem foto (ou se a URL expirar), mostra a inicial do nome.
class _AthletePhoto extends StatelessWidget {
  const _AthletePhoto({required this.athlete});

  final Athlete athlete;

  @override
  Widget build(BuildContext context) {
    final photoUrl = athlete.photoUrl;
    return CircleAvatar(
      radius: 24,
      foregroundImage: photoUrl == null ? null : NetworkImage(photoUrl),
      onForegroundImageError: photoUrl == null ? null : (_, _) {},
      child: Text(athlete.displayName[0].toUpperCase()),
    );
  }
}
