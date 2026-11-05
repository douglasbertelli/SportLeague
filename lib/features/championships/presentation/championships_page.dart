import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../../../core/widgets/empty_state.dart';
import '../../plans/domain/plan_status.dart';
import '../../plans/presentation/plan_gate.dart';
import '../../profile/data/profile_repository.dart';
import '../data/championship_repository.dart';
import '../domain/championship.dart';

/// Campeonatos que o usuário organiza ou em que um time dele joga. Só o
/// administrador cria.
class ChampionshipsPage extends ConsumerWidget {
  const ChampionshipsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(currentProfileProvider).value?.isAdmin ?? false;
    final userId = ref.watch(currentUserIdProvider);
    final championships = ref.watch(myChampionshipsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Campeonatos')),
      floatingActionButton: isAdmin
          ? FloatingActionButton.extended(
              heroTag: null,
              onPressed: () async {
                final allowed = await ensurePlanAllows(
                  context,
                  ref,
                  PlanFeature.championships,
                  adding: true,
                );
                if (!allowed || !context.mounted) return;
                final created = await context.push<Championship>(
                  Routes.championshipForm,
                );
                ref.invalidate(myChampionshipsProvider);
                if (created != null && context.mounted) {
                  await context.push(Routes.championship, extra: created.id);
                }
              },
              icon: const Icon(Icons.add),
              label: const Text('Novo campeonato'),
            )
          : null,
      body: championships.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: TextButton.icon(
            onPressed: () => ref.invalidate(myChampionshipsProvider),
            icon: const Icon(Icons.refresh),
            label: const Text('Erro ao carregar. Tentar novamente'),
          ),
        ),
        data: (championships) => championships.isEmpty
            ? EmptyState(
                icon: Icons.emoji_events_outlined,
                title: 'Nenhum campeonato',
                message: isAdmin
                    ? 'Organize um campeonato: pontos corridos, mata-mata ou '
                          'grupos + mata-mata, com times do app e fictícios.'
                    : 'Quando um time seu entrar num campeonato, ele aparece '
                          'aqui.',
              )
            : RefreshIndicator(
                onRefresh: () => ref.refresh(myChampionshipsProvider.future),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  children: [
                    for (final championship in championships)
                      _ChampionshipCard(
                        championship: championship,
                        organizer: championship.ownerId == userId,
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _ChampionshipCard extends StatelessWidget {
  const _ChampionshipCard({
    required this.championship,
    required this.organizer,
  });

  final Championship championship;
  final bool organizer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
        leading: CircleAvatar(
          backgroundColor: colors.secondaryContainer,
          child: Icon(
            Icons.emoji_events_outlined,
            color: colors.onSecondaryContainer,
          ),
        ),
        title: Text(championship.name),
        subtitle: Text(
          [
            championship.modality.label,
            championship.format.label,
            if (organizer) 'Você organiza',
          ].join(' · '),
        ),
        trailing: Chip(
          label: Text(championship.status.label),
          visualDensity: VisualDensity.compact,
        ),
        onTap: () => context.push(Routes.championship, extra: championship.id),
      ),
    );
  }
}
