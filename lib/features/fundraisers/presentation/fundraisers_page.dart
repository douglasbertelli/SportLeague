import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/router/routes.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../../../core/widgets/empty_state.dart';
import '../../invites/data/invite_repository.dart';
import '../../profile/data/profile_repository.dart';
import '../../teams/data/team_repository.dart';
import '../../teams/domain/team.dart';
import '../../teams/presentation/team_logo.dart';
import '../data/fundraiser_repository.dart';
import '../domain/fundraiser.dart';

/// Times em que o usuário vê vaquinhas: os do administrador ou do técnico
/// (os mesmos do seletor de time) ou os times em que o jogador é atleta.
final fundraiserTeamsProvider = FutureProvider<List<Team>>((ref) async {
  final profile = await ref.watch(currentProfileProvider.future);
  if (profile?.hasTeamHome ?? false) {
    return ref.watch(myTeamsProvider.future);
  }
  return ref.watch(myPlayerTeamsProvider.future);
});

/// Vaquinhas de um time. Abre no time ativo; quem está em mais de um time
/// troca pelos chips do topo. Só o administrador (dono) cria.
class FundraisersPage extends ConsumerStatefulWidget {
  const FundraisersPage({super.key});

  @override
  ConsumerState<FundraisersPage> createState() => _FundraisersPageState();
}

class _FundraisersPageState extends ConsumerState<FundraisersPage> {
  String? _teamId;

  @override
  Widget build(BuildContext context) {
    final teams = ref.watch(fundraiserTeamsProvider);
    final selectedId = ref.watch(selectedTeamProvider).value?.id;

    return Scaffold(
      appBar: AppBar(title: const Text('Vaquinha')),
      body: teams.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: TextButton.icon(
            onPressed: () => ref.invalidate(fundraiserTeamsProvider),
            icon: const Icon(Icons.refresh),
            label: const Text('Erro ao carregar os times. Tentar novamente'),
          ),
        ),
        data: (teams) {
          if (teams.isEmpty) {
            return const EmptyState(
              icon: Icons.savings_outlined,
              title: 'Nenhum time',
              message: 'As vaquinhas ficam no time. Entre num time para ver.',
            );
          }
          final team =
              teams.where((team) => team.id == _teamId).firstOrNull ??
              teams.where((team) => team.id == selectedId).firstOrNull ??
              teams.first;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (teams.length > 1)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(
                    children: [
                      for (final option in teams)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            avatar: TeamLogo(team: option, radius: 12),
                            label: Text(option.name),
                            selected: option.id == team.id,
                            onSelected: (_) =>
                                setState(() => _teamId = option.id),
                          ),
                        ),
                    ],
                  ),
                ),
              Expanded(child: _TeamFundraisers(team: team)),
            ],
          );
        },
      ),
    );
  }
}

class _TeamFundraisers extends ConsumerWidget {
  const _TeamFundraisers({required this.team});

  final Team team;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOwner = team.ownerId == ref.watch(currentUserIdProvider);
    final fundraisers = ref.watch(teamFundraisersProvider(team.id!));

    return Scaffold(
      floatingActionButton: isOwner
          ? FloatingActionButton.extended(
              heroTag: null,
              onPressed: () => context.push(
                Routes.fundraiserForm,
                extra: (team: team, fundraiser: null),
              ),
              icon: const Icon(Icons.add),
              label: const Text('Nova vaquinha'),
            )
          : null,
      body: fundraisers.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: TextButton.icon(
            onPressed: () => ref.invalidate(teamFundraisersProvider(team.id!)),
            icon: const Icon(Icons.refresh),
            label: const Text('Erro ao carregar as vaquinhas. Tentar novamente'),
          ),
        ),
        data: (fundraisers) => fundraisers.isEmpty
            ? EmptyState(
                icon: Icons.savings_outlined,
                title: 'Nenhuma vaquinha',
                message: isOwner
                    ? 'Junte o dinheiro do time para a bola, os coletes, o '
                          'uniforme ou o que precisar.'
                    : 'Quando o administrador criar uma vaquinha, ela aparece '
                          'aqui.',
              )
            : RefreshIndicator(
                onRefresh: () =>
                    ref.refresh(teamFundraisersProvider(team.id!).future),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  children: [
                    for (final fundraiser in fundraisers)
                      _FundraiserCard(team: team, fundraiser: fundraiser),
                  ],
                ),
              ),
      ),
    );
  }
}

class _FundraiserCard extends StatelessWidget {
  const _FundraiserCard({required this.team, required this.fundraiser});

  final Team team;
  final Fundraiser fundraiser;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final createdAt = fundraiser.createdAt;
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Icon(fundraiserIcon(fundraiser.item))),
        title: Row(
          children: [
            Flexible(child: Text(fundraiser.title)),
            if (fundraiser.closed) ...[
              const SizedBox(width: 8),
              Text(
                'Encerrada',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
        subtitle: Text(
          [
            switch (fundraiser.amountType) {
              AmountType.perPerson =>
                '${formatMoney(fundraiser.amountCents)} por pessoa',
              AmountType.total =>
                '${formatMoney(fundraiser.amountCents)} no total, dividido',
            },
            if (createdAt != null)
              'criada em ${DateFormat('dd/MM/yyyy').format(createdAt)}',
          ].join(' · '),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push(
          Routes.fundraiser,
          extra: (team: team, fundraiser: fundraiser),
        ),
      ),
    );
  }
}

/// Ícone de cada item da vaquinha.
IconData fundraiserIcon(FundraiserItem item) => switch (item) {
  FundraiserItem.ball => Icons.sports_soccer,
  FundraiserItem.bib => Icons.checkroom_outlined,
  FundraiserItem.kit => Icons.dry_cleaning_outlined,
  FundraiserItem.other => Icons.shopping_bag_outlined,
};
