import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/router/routes.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../games/presentation/game_card.dart';
import '../../invites/data/invite_repository.dart';
import '../../profile/data/profile_repository.dart';
import '../data/team_repository.dart';
import '../domain/team.dart';
import '../domain/team_stats.dart';
import '../../games/data/player_stats_repository.dart';
import '../../games/domain/player_stats.dart';
import 'season_button.dart';
import 'team_logo.dart';
import 'team_stats_widgets.dart';

/// Perfil público de um time, em duas abas. Visão geral: capa, seguidores
/// (com o botão Seguir), estatísticas, últimos resultados e próximos jogos.
/// Sobre o time: mando, cidade, local, fundação, descrição, uniformes (para
/// saber as cores da camisa) e contatos.
class TeamProfilePage extends ConsumerWidget {
  const TeamProfilePage({super.key, required this.teamId});

  final String teamId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final team = ref.watch(teamByIdProvider(teamId));
    final loaded = team.value;
    final isOwner =
        loaded != null && loaded.ownerId == ref.watch(currentUserIdProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(loaded?.name ?? 'Time'),
        actions: [
          // Só o administrador do time vê; leva ao cadastro do time.
          if (isOwner)
            IconButton(
              tooltip: 'Editar time',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () async {
                await context.push(Routes.editTeam, extra: loaded);
                // Volta com os dados que acabaram de ser salvos.
                ref.invalidate(teamByIdProvider(teamId));
              },
            ),
        ],
      ),
      body: team.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: TextButton.icon(
            onPressed: () => ref.invalidate(teamByIdProvider(teamId)),
            icon: const Icon(Icons.refresh),
            label: const Text('Erro ao carregar o time. Tentar novamente'),
          ),
        ),
        data: (team) => team == null
            ? const Center(child: Text('Este time não existe mais.'))
            : _Profile(team: team),
      ),
    );
  }
}

class _Profile extends StatelessWidget {
  const _Profile({required this.team});

  final Team team;

  void _showImage(BuildContext context, String url, String label) {
    showAppSheet<void>(
      context,
      builder: (context) => AppSheet(
        title: label,
        body: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Semantics(
            label: label,
            image: true,
            // Pinça para ampliar.
            child: InteractiveViewer(
              child: Image.network(
                url,
                errorBuilder: (_, _, _) =>
                    const Icon(Icons.broken_image_outlined, size: 64),
              ),
            ),
          ),
        ),
        actions: const [SheetBackButton(label: 'Fechar')],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final mutedStyle = theme.textTheme.bodyMedium?.copyWith(
      color: colors.onSurfaceVariant,
    );
    final foundedOn = team.foundedOn;
    final contacts = [
      if (team.phone case final phone?)
        (Icons.phone_outlined, 'Telefone', formatPhone(phone)),
      if (team.instagram case final instagram?)
        (Icons.camera_alt_outlined, 'Instagram', '@$instagram'),
      if (team.facebook case final facebook?)
        (Icons.facebook, 'Facebook', facebook),
      if (team.youtube case final youtube?)
        (Icons.smart_display_outlined, 'YouTube', youtube),
      if (team.website case final website?) (Icons.language, 'Site', website),
    ];

    // Aba "Visão geral": capa, seguidores, estatísticas e jogos.
    final overview = ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: switch (team.coverUrl) {
            final url? => Semantics(
              label: 'Capa do ${team.name}',
              image: true,
              child: Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    ColoredBox(color: colors.surfaceContainerHigh),
              ),
            ),
            null => ColoredBox(
              color: colors.surfaceContainerHigh,
              child: Icon(
                Icons.shield_outlined,
                size: 64,
                color: colors.onSurfaceVariant,
              ),
            ),
          },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(
            children: [
              TeamLogo(team: team, radius: 28),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(team.name, style: theme.textTheme.titleLarge),
                    Text(team.summary, style: mutedStyle),
                  ],
                ),
              ),
            ],
          ),
        ),
        _FollowBar(team: team),
        _StatsSection(team: team),
        _RankingsSection(teamId: team.id!),
      ],
    );

    // Aba "Sobre o time": as informações cadastradas do time.
    final about = ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 32),
      children: [
        ListTile(
          leading: const Icon(Icons.stadium_outlined),
          title: Text('Joga como: ${team.playsAs.label}'),
          subtitle: Text(team.playsAs.description),
        ),
        if (team.location case final location?)
          ListTile(
            leading: const Icon(Icons.location_city_outlined),
            title: Text(location),
          ),
        if (team.homeVenue case final venue?)
          ListTile(
            leading: const Icon(Icons.place_outlined),
            title: Text(venue.name),
            subtitle: Text(venue.address),
          ),
        if (foundedOn != null)
          ListTile(
            leading: const Icon(Icons.cake_outlined),
            title: Text(
              'Fundado em '
              '${MaterialLocalizations.of(context).formatMediumDate(foundedOn)}',
            ),
          ),
        if (team.description case final description?)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(description),
          ),
        if (team.kitUrls.isNotEmpty) ...[
          const _SectionTitle('Uniformes'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GridView.count(
              crossAxisCount: maxKits,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 3 / 4,
              children: [
                for (final (index, url) in team.kitUrls.indexed)
                  Semantics(
                    button: true,
                    label: 'Uniforme ${index + 1}',
                    excludeSemantics: true,
                    child: Material(
                      borderRadius: BorderRadius.circular(12),
                      clipBehavior: Clip.antiAlias,
                      color: colors.surfaceContainerHighest,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.network(
                            url,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Icon(
                              Icons.broken_image_outlined,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          Material(
                            type: MaterialType.transparency,
                            child: InkWell(
                              onTap: () => _showImage(
                                context,
                                url,
                                'Uniforme ${index + 1}',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (contacts.isNotEmpty) ...[
          const _SectionTitle('Contato'),
          for (final (icon, label, value) in contacts)
            ListTile(
              leading: Icon(icon),
              title: SelectableText(value),
              subtitle: Text(label),
            ),
        ],
      ],
    );

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.insights_outlined), text: 'Visão geral'),
              Tab(icon: Icon(Icons.info_outline), text: 'Sobre o time'),
            ],
          ),
          Expanded(child: TabBarView(children: [overview, about])),
        ],
      ),
    );
  }
}

/// Seguidores, seguindo e o botão Seguir (pelo time ativo). Sem time ativo,
/// ou no perfil do próprio time ativo, o botão não aparece.
class _FollowBar extends ConsumerStatefulWidget {
  const _FollowBar({required this.team});

  final Team team;

  @override
  ConsumerState<_FollowBar> createState() => _FollowBarState();
}

class _FollowBarState extends ConsumerState<_FollowBar> {
  bool _saving = false;

  Future<void> _toggle(Team mine, bool following) async {
    final pair = (follower: mine.id!, followed: widget.team.id!);
    final repository = ref.read(teamRepositoryProvider);
    setState(() => _saving = true);
    try {
      await (following
          ? repository.unfollow(pair.follower, pair.followed)
          : repository.follow(pair.follower, pair.followed));
      ref
        ..invalidate(isFollowingProvider(pair))
        ..invalidate(teamStatsProvider(widget.team.id!))
        ..invalidate(teamStatsProvider(mine.id!));
    } catch (error) {
      if (mounted) showErrorSnackBar(context, friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stats = ref.watch(teamStatsProvider(widget.team.id!)).value;
    final mine = ref.watch(selectedTeamProvider).value;
    final canFollow = mine != null && mine.id != widget.team.id;
    final following = canFollow
        ? ref
              .watch(
                isFollowingProvider((
                  follower: mine.id!,
                  followed: widget.team.id!,
                )),
              )
              .value
        : null;

    Widget count(int? value, String label) => Semantics(
      container: true,
      child: Column(
        children: [
          Text(
            value?.toString() ?? '–',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        children: [
          // Em tela estreita, os números quebram a linha em vez de empurrar
          // o botão para fora.
          Expanded(
            child: Wrap(
              spacing: 24,
              runSpacing: 8,
              children: [
                count(
                  stats?.followers,
                  stats?.followers == 1 ? 'Seguidor' : 'Seguidores',
                ),
                count(stats?.following, 'Seguindo'),
              ],
            ),
          ),
          // Jogador ou técnico pede para entrar no time.
          if (ref.watch(currentProfileProvider).value case final profile?
              when !profile.isAdmin)
            _JoinButton(team: widget.team, profileId: profile.id)
          else if (canFollow)
            switch (following) {
              true => OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(120, 44),
                ),
                onPressed: _saving ? null : () => _toggle(mine, true),
                icon: const Icon(Icons.check),
                label: const Text('Seguindo'),
              ),
              false => FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size(120, 44)),
                onPressed: _saving ? null : () => _toggle(mine, false),
                icon: const Icon(Icons.person_add_alt_1_outlined),
                label: const Text('Seguir'),
              ),
              null => const SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            },
        ],
      ),
    );
  }
}

/// Botão do jogador: Pedir para entrar, Pedido enviado (toque cancela) ou
/// Você é do time.
class _JoinButton extends ConsumerStatefulWidget {
  const _JoinButton({required this.team, required this.profileId});

  final Team team;
  final String profileId;

  @override
  ConsumerState<_JoinButton> createState() => _JoinButtonState();
}

class _JoinButtonState extends ConsumerState<_JoinButton> {
  bool _saving = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _saving = true);
    try {
      await action();
      ref
        ..invalidate(myInvitesProvider)
        ..invalidate(myPlayerTeamsProvider);
    } catch (error) {
      if (mounted) showErrorSnackBar(context, friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repository = ref.read(inviteRepositoryProvider);
    final isMember = (ref.watch(myPlayerTeamsProvider).value ?? const []).any(
      (team) => team.id == widget.team.id,
    );
    final pending = (ref.watch(myInvitesProvider).value ?? const [])
        .where((i) => i.teamId == widget.team.id && i.isRequest && i.isPending)
        .firstOrNull;
    const size = Size(120, 44);

    if (isMember) {
      return OutlinedButton.icon(
        style: OutlinedButton.styleFrom(minimumSize: size),
        onPressed: null,
        icon: const Icon(Icons.verified_outlined),
        label: const Text('Você é do time'),
      );
    }
    if (pending != null) {
      return OutlinedButton.icon(
        style: OutlinedButton.styleFrom(minimumSize: size),
        onPressed: _saving
            ? null
            : () async {
                final confirmed = await confirmAction(
                  context,
                  title: 'Cancelar pedido?',
                  message: 'O pedido para entrar no ${widget.team.name} sai.',
                  confirmLabel: 'Cancelar pedido',
                  confirmIcon: Icons.close,
                  cancelLabel: 'Voltar',
                );
                if (confirmed) await _run(() => repository.cancel(pending.id));
              },
        icon: const Icon(Icons.hourglass_top),
        label: const Text('Pedido enviado'),
      );
    }
    return FilledButton.icon(
      style: FilledButton.styleFrom(minimumSize: size),
      onPressed: _saving
          ? null
          : () => _run(
              () => repository.requestToJoin(widget.team.id!, widget.profileId),
            ),
      icon: const Icon(Icons.group_add_outlined),
      label: const Text('Pedir para entrar'),
    );
  }
}

/// Estatísticas, últimos resultados e próximos jogos do time.
class _StatsSection extends ConsumerWidget {
  const _StatsSection({required this.team});

  final Team team;

  String get teamId => team.id!;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return ref
        .watch(teamStatsProvider(teamId))
        .when(
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, _) => TextButton.icon(
            onPressed: () => ref.invalidate(teamStatsProvider(teamId)),
            icon: const Icon(Icons.refresh),
            label: const Text('Erro ao carregar os números. Tentar novamente'),
          ),
          data: (stats) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Temporada: vale para as estatísticas e a artilharia.
                const _SectionTitle('Estatísticas', trailing: SeasonButton()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: StatsGrid(stats: stats),
                ),
                const _SectionTitle('Últimos resultados'),
                if (stats.recent.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text('Nenhum amistoso realizado ainda.'),
                  ),
                for (final game in stats.recent)
                  ListTile(
                    // Símbolo do adversário; o resultado (V, E, D) vai junto
                    // do placar.
                    leading: TeamLogo.url(logoUrl: game.opponentLogoUrl),
                    title: OpponentWithSide(
                      opponent: game.opponent,
                      isHome: game.isHome,
                    ),
                    subtitle: Text(formatGameDay(game.scheduledAt)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          game.hasScore
                              ? '${game.goalsFor} × ${game.goalsAgainst}'
                              : 'Sem placar',
                          style: game.hasScore
                              ? theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                )
                              : theme.textTheme.bodySmall?.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                        ),
                        const SizedBox(width: 12),
                        OutcomeBadge(game: game, radius: 14),
                      ],
                    ),
                  ),
                if (stats.upcoming.isNotEmpty) ...[
                  const _SectionTitle('Próximos jogos'),
                  for (final game in stats.upcoming)
                    ListTile(
                      leading: TeamLogo.url(logoUrl: game.opponentLogoUrl),
                      title: OpponentWithSide(
                        opponent: game.opponent,
                        isHome: game.isHome,
                      ),
                      subtitle: Text(
                        '${formatGameDay(game.scheduledAt)} às '
                        '${formatGameTime(game.scheduledAt)}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      // Resumo da partida.
                      onTap: () => showAppSheet<void>(
                        context,
                        builder: (_) =>
                            _UpcomingGameSheet(team: team, game: game),
                      ),
                    ),
                ],
              ],
            );
          },
        );
  }
}

/// Resumo de um próximo jogo do perfil: os dois times, quando (e quanto
/// falta), mando, modalidade e local; abre o perfil do adversário da
/// plataforma.
class _UpcomingGameSheet extends StatelessWidget {
  const _UpcomingGameSheet({required this.team, required this.game});

  final Team team;
  final ProfileGame game;

  /// "Hoje", "Amanhã" ou "Em 5 dias".
  static String _whenLabel(DateTime day) {
    final today = DateUtils.dateOnly(DateTime.now());
    final days = DateUtils.dateOnly(day).difference(today).inDays;
    return switch (days) {
      <= 0 => 'Hoje',
      1 => 'Amanhã',
      _ => 'Em $days dias',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final weekday = DateFormat('EEEE', 'pt_BR').format(game.scheduledAt);
    final opponentId = game.opponentTeamId;

    Widget side(Widget logo, String name) => Expanded(
      child: Column(
        children: [
          logo,
          const SizedBox(height: 8),
          Text(
            name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall,
          ),
        ],
      ),
    );

    Widget detail(IconData icon, String text, [String? extra]) => Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text, style: theme.textTheme.bodyLarge),
                if (extra != null) Text(extra, style: muted),
              ],
            ),
          ),
        ],
      ),
    );

    return AppSheet(
      title: 'Resumo da partida',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              side(TeamLogo(team: team, radius: 28), team.name),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('×', style: theme.textTheme.headlineSmall),
              ),
              side(
                TeamLogo.url(logoUrl: game.opponentLogoUrl, radius: 28),
                game.opponent,
              ),
            ],
          ),
          const SizedBox(height: 8),
          detail(
            Icons.calendar_month_outlined,
            '${weekday[0].toUpperCase()}${weekday.substring(1)}, '
            '${formatGameDay(game.scheduledAt)} às '
            '${formatGameTime(game.scheduledAt)}',
            _whenLabel(game.scheduledAt),
          ),
          detail(
            Icons.stadium_outlined,
            game.isHome
                ? '${team.name} joga em casa (mandante)'
                : '${team.name} joga fora (visitante)',
          ),
          if (game.modality case final modality?)
            detail(Icons.sports_soccer, modality.label),
          if (game.venue case final venue?)
            detail(Icons.location_on_outlined, venue.name, venue.address)
          else if (game.location case final location?)
            detail(Icons.location_on_outlined, location),
        ],
      ),
      actions: [
        if (opponentId != null)
          FilledButton.tonalIcon(
            onPressed: () {
              Navigator.of(context).pop();
              context.push(Routes.teamProfile, extra: opponentId);
            },
            icon: const Icon(Icons.shield_outlined),
            label: Text('Ver perfil do ${game.opponent}'),
          ),
        const SheetBackButton(label: 'Fechar'),
      ],
    );
  }
}

/// "(19) 99999-8888" ou "(19) 3333-4444".
String formatPhone(String digits) {
  if (digits.length < 10) return digits;
  final area = digits.substring(0, 2);
  final number = digits.substring(2);
  final split = number.length - 4;
  return '($area) ${number.substring(0, split)}-${number.substring(split)}';
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {this.trailing});

  final String text;

  /// À direita do título (ex.: a temporada).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Artilharia e garçons do time, pelas súmulas dos jogos.
class _RankingsSection extends ConsumerWidget {
  const _RankingsSection({required this.teamId});

  final String teamId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final totals = ref.watch(teamPlayerTotalsProvider(teamId)).value;
    if (totals == null) return const SizedBox.shrink();

    List<AthleteTotals> top(int Function(AthleteTotals) value) => ([
      for (final row in totals)
        if (value(row) > 0) row,
    ]..sort((a, b) => value(b).compareTo(value(a)))).take(5).toList();

    final scorers = top((row) => row.goals);
    final assists = top((row) => row.assists);

    Widget list(
      List<AthleteTotals> rows,
      int Function(AthleteTotals) value,
      String unit,
    ) => Column(
      children: [
        for (final (index, row) in rows.indexed)
          ListTile(
            dense: true,
            leading: CircleAvatar(radius: 14, child: Text('${index + 1}')),
            title: Text(
              [
                if (row.jerseyNumber case final number?) '$number',
                row.name,
              ].join(' · '),
            ),
            trailing: Text(
              '${value(row)} $unit',
              style: theme.textTheme.titleSmall,
            ),
          ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionTitle('Artilharia'),
        if (scorers.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Nenhum gol lançado nas súmulas ainda.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          list(scorers, (row) => row.goals, 'gols'),
        if (assists.isNotEmpty) ...[
          const _SectionTitle('Garçons'),
          list(assists, (row) => row.assists, 'assist.'),
        ],
      ],
    );
  }
}
