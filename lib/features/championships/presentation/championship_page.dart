import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/media/photo_picker.dart';
import '../../../core/router/routes.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/empty_state.dart';
import '../../games/presentation/game_card.dart'
    show formatGameDay, formatGameTime;
import '../../teams/presentation/team_logo.dart';
import '../../venues/domain/venue.dart';
import '../data/championship_repository.dart';
import '../domain/championship.dart';
import '../domain/championship_rules.dart';
import 'championship_team_picker_page.dart';

/// Um campeonato: classificação (ou chaveamento), jogos e times. O
/// organizador inscreve os times, gera a tabela, marca data e local e lança
/// os placares; os times inscritos acompanham, e o dono de um time
/// convidado aceita ou recusa aqui.
class ChampionshipPage extends ConsumerStatefulWidget {
  const ChampionshipPage({
    super.key,
    required this.championshipId,
    this.random,
  });

  final String championshipId;

  /// Sorteio (fixo nos testes).
  final Random? random;

  @override
  ConsumerState<ChampionshipPage> createState() => _ChampionshipPageState();
}

class _ChampionshipPageState extends ConsumerState<ChampionshipPage> {
  var _busy = false;

  String get _id => widget.championshipId;

  ChampionshipRepository get _repository =>
      ref.read(championshipRepositoryProvider);

  void _refresh() => ref
    ..invalidate(championshipProvider(_id))
    ..invalidate(championshipTeamsProvider(_id))
    ..invalidate(championshipMatchesProvider(_id))
    ..invalidate(myChampionshipsProvider);

  /// Roda [action] com o indicador de carregando e mostra o erro amigável.
  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      _refresh();
    } catch (error) {
      if (mounted) showErrorSnackBar(context, friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Ações do organizador (⋮ do topo) num bottom sheet: editar, antes de
  /// começar, e excluir.
  Future<void> _showActions(Championship championship) async {
    final action = await showAppSheet<String>(
      context,
      builder: (context) {
        final colors = Theme.of(context).colorScheme;
        return AppSheet(
          title: championship.name,
          message: championship.summary,
          body: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (championship.status == ChampionshipStatus.draft)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Editar campeonato'),
                  subtitle: const Text('Nome, modalidade e formato'),
                  onTap: () => Navigator.of(context).pop('edit'),
                ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.delete_outline),
                iconColor: colors.error,
                textColor: colors.error,
                title: const Text('Excluir campeonato'),
                subtitle: const Text('Apaga os times inscritos e os jogos'),
                onTap: () => Navigator.of(context).pop('delete'),
              ),
            ],
          ),
          actions: const [SheetBackButton(label: 'Fechar')],
        );
      },
    );
    if (!mounted) return;
    switch (action) {
      case 'edit':
        await context.push(Routes.championshipForm, extra: championship);
        _refresh();
      case 'delete':
        await _delete(championship);
    }
  }

  /// Envia, troca ou remove o símbolo de um time fictício.
  Future<void> _changeGuestLogo(ChampionshipTeam entry) async {
    final choice = await chooseImage(
      context,
      ref,
      noun: 'símbolo',
      canRemove: entry.logoUrl != null,
      cropSquare: true,
    );
    if (choice == null) return;
    await _run(
      () => _repository.setGuestLogo(entry.guestTeamId!, switch (choice) {
        ImagePicked(:final image) => image,
        ImageRemoved() => null,
      }),
    );
  }

  Future<void> _addTeam(
    Championship championship,
    List<ChampionshipTeam> teams,
  ) async {
    final picked = await context.push<PickedChampionshipTeam>(
      Routes.championshipTeamPicker,
      extra: (
        modality: championship.modality,
        teamIds: {for (final t in teams) ?t.teamId},
        guestIds: {for (final t in teams) ?t.guestTeamId},
      ),
    );
    if (picked == null) return;
    await _run(
      () => _repository.addTeam(
        _id,
        teamId: picked.teamId,
        guestTeamId: picked.guestTeamId,
      ),
    );
  }

  Future<void> _start(
    Championship championship,
    List<ChampionshipTeam> teams,
  ) async {
    final confirmed = teams
        .where((t) => t.status == EntryStatus.accepted)
        .toList();
    if (cannotGenerate(championship, confirmed.length) case final reason?) {
      showErrorSnackBar(context, reason);
      return;
    }
    final pending = teams.where((t) => t.status == EntryStatus.invited);
    final ok = await confirmAction(
      context,
      title: 'Gerar a tabela?',
      message:
          'O app sorteia ${championship.format == ChampionshipFormat.groups ? 'os grupos e ' : ''}'
          'os jogos dos ${confirmed.length} times confirmados. Depois não '
          'dá para incluir nem tirar times.'
          '${pending.isEmpty ? '' : ' Os convites sem resposta são cancelados.'}',
      confirmLabel: 'Gerar tabela',
    );
    if (!ok) return;
    final ids = [for (final t in confirmed) t.id];
    final groups = championship.format == ChampionshipFormat.groups
        ? drawGroups(ids, championship.groupCount!, widget.random)
        : const <String, String>{};
    final planned = planChampionship(
      championship,
      ids,
      groups: groups,
      random: widget.random,
    );
    await _run(() async {
      for (final entry in pending) {
        await _repository.removeTeam(entry.id);
      }
      await _repository.start(championship, planned, groups: groups);
    });
  }

  /// Grupos encerrados: monta o mata-mata com os classificados.
  Future<void> _startKnockout(
    Championship championship,
    List<ChampionshipTeam> teams,
    List<ChampionshipMatch> matches,
  ) async {
    final names = {for (final t in teams) t.id: t.name};
    final byGroup = [
      for (final label in groupLabels.take(championship.groupCount!))
        standings(
          [
            for (final t in teams)
              if (t.groupLabel == label) t.id,
          ],
          matches.where((m) => m.groupLabel == label),
          names: names,
        ),
    ];
    final bracket = knockoutFromGroups(
      byGroup,
      championship.qualifiersPerGroup!,
    );
    final rounds = matches
        .where((m) => m.stage == MatchStage.group)
        .map((m) => m.round)
        .fold(0, max);
    await _run(
      () => _repository.addMatches(
        _id,
        knockoutBracket(bracket, firstRound: rounds + 1),
      ),
    );
  }

  Future<void> _finishLeague() async {
    final ok = await confirmAction(
      context,
      title: 'Encerrar o campeonato?',
      message: 'O líder da classificação é o campeão.',
      confirmLabel: 'Encerrar',
    );
    if (!ok) return;
    await _run(() => _repository.setStatus(_id, ChampionshipStatus.finished));
  }

  Future<void> _delete(Championship championship) async {
    final ok = await confirmDelete(
      context,
      title: 'Excluir campeonato?',
      message:
          'O campeonato ${championship.name}, os times inscritos e os jogos '
          'serão apagados.',
    );
    if (!ok) return;
    try {
      await _repository.delete(_id);
      ref.invalidate(myChampionshipsProvider);
      if (mounted) context.pop();
    } catch (error) {
      if (mounted) showErrorSnackBar(context, friendlyErrorMessage(error));
    }
  }

  Future<void> _openMatch(
    Championship championship,
    ChampionshipMatch match,
    List<ChampionshipMatch> matches,
    Map<String, ChampionshipTeam> teams,
  ) async {
    final action = await showAppSheet<String>(
      context,
      builder: (context) => AppSheet(
        title:
            '${teams[match.homeId]?.name ?? 'A definir'} x '
            '${teams[match.awayId]?.name ?? 'A definir'}',
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: const Text('Marcar data e local'),
              onTap: () => Navigator.of(context).pop('schedule'),
            ),
            if (match.hasTeams)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.scoreboard_outlined),
                title: Text(
                  match.hasScore ? 'Corrigir placar' : 'Lançar placar',
                ),
                onTap: () => Navigator.of(context).pop('score'),
              ),
          ],
        ),
        actions: const [SheetBackButton(label: 'Fechar')],
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'schedule':
        await _schedule(match);
      case 'score':
        await _score(championship, match, matches, teams);
    }
  }

  Future<void> _schedule(ChampionshipMatch match) async {
    final now = DateTime.now();
    final start =
        match.scheduledAt ?? DateTime(now.year, now.month, now.day, 15);
    final day = await pickDateSheet(
      context,
      initialDate: start,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
      title: 'Dia do jogo',
    );
    if (day == null || !mounted) return;
    final time = await pickTimeSheet(
      context,
      initialTime: TimeOfDay.fromDateTime(start),
      title: 'Horário do jogo',
    );
    if (time == null || !mounted) return;
    final venue = await context.push<Venue>(Routes.pickVenue);
    if (!mounted) return;
    await _run(
      () => _repository.schedule(
        match.id,
        at: DateTime(day.year, day.month, day.day, time.hour, time.minute),
        venueId: venue?.id ?? match.venueId,
      ),
    );
  }

  Future<void> _score(
    Championship championship,
    ChampionshipMatch match,
    List<ChampionshipMatch> matches,
    Map<String, ChampionshipTeam> teams,
  ) async {
    final result = await showAppSheet<_ScoreResult>(
      context,
      builder: (_) => _ScoreSheet(
        match: match,
        home: teams[match.homeId]!.name,
        away: teams[match.awayId]!.name,
      ),
    );
    if (result == null) return;
    await _run(() async {
      await _repository.setScore(
        match.id,
        home: result.home,
        away: result.away,
        homePenalties: result.homePenalties,
        awayPenalties: result.awayPenalties,
      );
      if (match.stage != MatchStage.knockout) return;
      // O vencedor entra no jogo seguinte; sem a final, acaba o campeonato.
      final updated = ChampionshipMatch(
        id: match.id,
        championshipId: match.championshipId,
        stage: match.stage,
        round: match.round,
        slot: match.slot,
        homeId: match.homeId,
        awayId: match.awayId,
        homeScore: result.home,
        awayScore: result.away,
        homePenalties: result.homePenalties,
        awayPenalties: result.awayPenalties,
      );
      final next = nextKnockoutSlot(updated, matches);
      if (next != null) {
        await _repository.setSide(
          next.match.id,
          home: next.home,
          teamId: updated.winnerId,
        );
      } else {
        await _repository.setStatus(
          _id,
          updated.winnerId == null
              ? ChampionshipStatus.running
              : ChampionshipStatus.finished,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final championship = ref.watch(championshipProvider(_id));
    final teams = ref.watch(championshipTeamsProvider(_id));
    final matches = ref.watch(championshipMatchesProvider(_id));
    final userId = ref.watch(currentUserIdProvider);

    return switch ((championship, teams, matches)) {
      (
        AsyncData(value: final championship),
        AsyncData(value: final teams),
        AsyncData(value: final matches),
      ) =>
        _page(
          championship,
          teams,
          matches,
          isOwner: championship.ownerId == userId,
          userId: userId,
        ),
      (AsyncError(), _, _) ||
      (_, AsyncError(), _) ||
      (_, _, AsyncError()) => Scaffold(
        appBar: AppBar(),
        body: Center(
          child: TextButton.icon(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
            label: const Text('Erro ao carregar. Tentar novamente'),
          ),
        ),
      ),
      _ => Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      ),
    };
  }

  Widget _page(
    Championship championship,
    List<ChampionshipTeam> teams,
    List<ChampionshipMatch> matches, {
    required bool isOwner,
    required String? userId,
  }) {
    final byId = {for (final t in teams) t.id: t};
    final draft = championship.status == ChampionshipStatus.draft;
    final tableLabel = championship.format == ChampionshipFormat.knockout
        ? 'Chaveamento'
        : 'Classificação';

    return DefaultTabController(
      length: 4,
      initialIndex: draft ? 3 : 0,
      child: Scaffold(
        appBar: AppBar(
          title: Text(championship.name),
          actions: [
            if (isOwner)
              IconButton(
                tooltip: 'Ações do campeonato',
                icon: const Icon(Icons.more_vert),
                onPressed: () => _showActions(championship),
              ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: tableLabel),
              const Tab(text: 'Jogos'),
              const Tab(text: 'Artilharia'),
              Tab(text: 'Times (${teams.length})'),
            ],
          ),
        ),
        body: Stack(
          children: [
            TabBarView(
              children: [
                _TableTab(
                  championship: championship,
                  teams: teams,
                  matches: matches,
                ),
                _MatchesTab(
                  championship: championship,
                  teams: byId,
                  matches: matches,
                  isOwner: isOwner,
                  onTap: isOwner && !draft
                      ? (match) =>
                            _openMatch(championship, match, matches, byId)
                      : null,
                  onStartKnockout: () =>
                      _startKnockout(championship, teams, matches),
                  onFinish: _finishLeague,
                ),
                _ScorersTab(championshipId: _id),
                _TeamsTab(
                  championship: championship,
                  teams: teams,
                  isOwner: isOwner,
                  userId: userId,
                  onAdd: () => _addTeam(championship, teams),
                  onStart: () => _start(championship, teams),
                  onRemove: (entry) =>
                      _run(() => _repository.removeTeam(entry.id)),
                  onRespond: (entry, accept) =>
                      _run(() => _repository.respond(entry.id, accept: accept)),
                  onGuestLogo: _changeGuestLogo,
                ),
              ],
            ),
            if (_busy)
              const Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: LinearProgressIndicator(),
              ),
          ],
        ),
      ),
    );
  }
}

/// O campeão: o vencedor da final ou o líder dos pontos corridos.
String? championOf(
  Championship championship,
  List<ChampionshipTeam> teams,
  List<ChampionshipMatch> matches,
) {
  if (championship.status != ChampionshipStatus.finished) return null;
  final names = {for (final t in teams) t.id: t.name};
  if (championship.format == ChampionshipFormat.league) {
    final ids = [
      for (final t in teams)
        if (t.status == EntryStatus.accepted) t.id,
    ];
    final table = standings(ids, matches, names: names);
    return table.isEmpty ? null : names[table.first.teamId];
  }
  final knockout = matches.where((m) => m.stage == MatchStage.knockout);
  if (knockout.isEmpty) return null;
  final lastRound = knockout.map((m) => m.round).reduce(max);
  final finalMatch = knockout.firstWhere((m) => m.round == lastRound);
  return names[finalMatch.winnerId];
}

class _ChampionBanner extends StatelessWidget {
  const _ChampionBanner(this.name);

  final String name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Card(
      color: colors.primaryContainer,
      child: ListTile(
        leading: Icon(Icons.emoji_events, color: colors.onPrimaryContainer),
        title: Text(
          'Campeão: $name',
          style: theme.textTheme.titleMedium?.copyWith(
            color: colors.onPrimaryContainer,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Classificação / chaveamento
// ---------------------------------------------------------------------------

class _TableTab extends StatelessWidget {
  const _TableTab({
    required this.championship,
    required this.teams,
    required this.matches,
  });

  final Championship championship;
  final List<ChampionshipTeam> teams;
  final List<ChampionshipMatch> matches;

  @override
  Widget build(BuildContext context) {
    if (championship.status == ChampionshipStatus.draft) {
      return const EmptyState(
        icon: Icons.table_chart_outlined,
        title: 'A tabela ainda não saiu',
        message:
            'Quando o organizador gerar a tabela, a classificação aparece '
            'aqui.',
      );
    }
    final names = {for (final t in teams) t.id: t.name};
    final logos = {for (final t in teams) t.id: t.logoUrl};
    final champion = championOf(championship, teams, matches);
    final knockout = matches
        .where((m) => m.stage == MatchStage.knockout)
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        if (champion != null) ...[
          _ChampionBanner(champion),
          const SizedBox(height: 16),
        ],
        switch (championship.format) {
          ChampionshipFormat.league => _StandingsTable(
            rows: standings(
              [
                for (final t in teams)
                  if (t.status == EntryStatus.accepted) t.id,
              ],
              matches,
              names: names,
            ),
            names: names,
            logos: logos,
          ),
          ChampionshipFormat.groups => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final label in groupLabels.take(championship.groupCount!))
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _StandingsTable(
                    title: 'Grupo $label',
                    qualifiers: championship.qualifiersPerGroup,
                    rows: standings(
                      [
                        for (final t in teams)
                          if (t.groupLabel == label) t.id,
                      ],
                      matches.where((m) => m.groupLabel == label),
                      names: names,
                    ),
                    names: names,
                    logos: logos,
                  ),
                ),
            ],
          ),
          ChampionshipFormat.knockout => const SizedBox.shrink(),
        },
        if (knockout.isNotEmpty) ...[
          if (championship.format == ChampionshipFormat.groups)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Mata-mata',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          _Bracket(matches: knockout, names: names),
        ],
      ],
    );
  }
}

class _StandingsTable extends StatelessWidget {
  const _StandingsTable({
    required this.rows,
    required this.names,
    required this.logos,
    this.title,
    this.qualifiers,
  });

  final List<StandingRow> rows;
  final Map<String, String> names;
  final Map<String, String?> logos;
  final String? title;

  /// Quantos passam (destacados).
  final int? qualifiers;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final header = theme.textTheme.labelMedium?.copyWith(
      color: colors.onSurfaceVariant,
    );
    final cell = theme.textTheme.bodyMedium;

    Widget number(String text, TextStyle? style, {double width = 30}) =>
        SizedBox(
          width: width,
          child: Text(text, style: style, textAlign: TextAlign.center),
        );

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title case final title?)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(title, style: theme.textTheme.titleMedium),
              ),
            Row(
              children: [
                number('#', header, width: 24),
                const SizedBox(width: 8),
                Expanded(child: Text('Time', style: header)),
                for (final label in ['P', 'J', 'V', 'E', 'D', 'SG'])
                  number(label, header),
              ],
            ),
            const Divider(),
            for (final (index, row) in rows.indexed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 24,
                      child: Text(
                        '${index + 1}',
                        textAlign: TextAlign.center,
                        style: cell?.copyWith(
                          color: index < (qualifiers ?? 0)
                              ? colors.primary
                              : null,
                          fontWeight: index < (qualifiers ?? 0)
                              ? FontWeight.w700
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TeamLogo.url(logoUrl: logos[row.teamId], radius: 12),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        names[row.teamId] ?? '',
                        style: cell,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    number(
                      '${row.points}',
                      cell?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    number('${row.played}', cell),
                    number('${row.wins}', cell),
                    number('${row.draws}', cell),
                    number('${row.losses}', cell),
                    number(
                      row.goalDifference > 0
                          ? '+${row.goalDifference}'
                          : '${row.goalDifference}',
                      cell,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Chaveamento: as fases do mata-mata, uma embaixo da outra.
class _Bracket extends StatelessWidget {
  const _Bracket({required this.matches, required this.names});

  final List<ChampionshipMatch> matches;
  final Map<String, String> names;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rounds = matches.map((m) => m.round).toSet().toList()..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final round in rounds) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
            child: Text(
              knockoutRoundName(matches.where((m) => m.round == round).length),
              style: theme.textTheme.titleSmall,
            ),
          ),
          for (final match in matches.where((m) => m.round == round))
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    for (final home in [true, false])
                      _BracketLine(
                        name: names[home ? match.homeId : match.awayId],
                        score: home ? match.homeScore : match.awayScore,
                        penalties: home
                            ? match.homePenalties
                            : match.awayPenalties,
                        winner:
                            match.winnerId != null &&
                            match.winnerId ==
                                (home ? match.homeId : match.awayId),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _BracketLine extends StatelessWidget {
  const _BracketLine({
    required this.name,
    required this.score,
    required this.penalties,
    required this.winner,
  });

  final String? name;
  final int? score;
  final int? penalties;
  final bool winner;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyLarge?.copyWith(
      fontWeight: winner ? FontWeight.w700 : null,
      color: name == null ? theme.colorScheme.onSurfaceVariant : null,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(name ?? 'A definir', style: style)),
          if (penalties != null)
            Text('($penalties) ', style: theme.textTheme.bodySmall),
          Text(score?.toString() ?? '-', style: style),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Jogos
// ---------------------------------------------------------------------------

class _MatchesTab extends StatelessWidget {
  const _MatchesTab({
    required this.championship,
    required this.teams,
    required this.matches,
    required this.isOwner,
    required this.onTap,
    required this.onStartKnockout,
    required this.onFinish,
  });

  final Championship championship;
  final Map<String, ChampionshipTeam> teams;
  final List<ChampionshipMatch> matches;
  final bool isOwner;
  final ValueChanged<ChampionshipMatch>? onTap;
  final VoidCallback onStartKnockout;
  final VoidCallback onFinish;

  /// Título de cada bloco de jogos.
  String _section(ChampionshipMatch match) => switch (match.stage) {
    MatchStage.league => 'Rodada ${match.round}',
    MatchStage.group => 'Grupo ${match.groupLabel} · Rodada ${match.round}',
    MatchStage.knockout => knockoutRoundName(
      matches
          .where(
            (m) => m.stage == MatchStage.knockout && m.round == match.round,
          )
          .length,
    ),
  };

  @override
  Widget build(BuildContext context) {
    if (matches.isEmpty) {
      return const EmptyState(
        icon: Icons.sports_soccer,
        title: 'Sem jogos ainda',
        message: 'Os jogos aparecem quando o organizador gerar a tabela.',
      );
    }
    final theme = Theme.of(context);
    final running = championship.status == ChampionshipStatus.running;
    final groupsDone =
        championship.format == ChampionshipFormat.groups &&
        matches.every((m) => m.stage != MatchStage.group || m.hasScore) &&
        !matches.any((m) => m.stage == MatchStage.knockout);
    final leagueDone =
        championship.format == ChampionshipFormat.league &&
        matches.every((m) => m.hasScore);

    // Ordem: fase, rodada (e grupo) e posição.
    final sorted = [...matches]
      ..sort((a, b) {
        final stage = (a.stage == MatchStage.knockout ? 1 : 0).compareTo(
          b.stage == MatchStage.knockout ? 1 : 0,
        );
        if (stage != 0) return stage;
        final round = a.round.compareTo(b.round);
        if (round != 0) return round;
        final group = (a.groupLabel ?? '').compareTo(b.groupLabel ?? '');
        return group != 0 ? group : a.slot.compareTo(b.slot);
      });

    String? last;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        if (isOwner && running && groupsDone)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: FilledButton.icon(
              onPressed: onStartKnockout,
              icon: const Icon(Icons.account_tree_outlined),
              label: const Text('Gerar o mata-mata'),
            ),
          ),
        if (isOwner && running && leagueDone)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: FilledButton.icon(
              onPressed: onFinish,
              icon: const Icon(Icons.emoji_events_outlined),
              label: const Text('Encerrar campeonato'),
            ),
          ),
        if (isOwner && running)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'Toque num jogo para marcar data e local ou lançar o placar.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        for (final match in sorted) ...[
          if (_section(match) != last)
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 16, 0, 4),
              child: Text(
                last = _section(match),
                style: theme.textTheme.titleSmall,
              ),
            ),
          _MatchTile(
            match: match,
            home: teams[match.homeId],
            away: teams[match.awayId],
            onTap: onTap == null ? null : () => onTap!(match),
          ),
        ],
      ],
    );
  }
}

class _MatchTile extends StatelessWidget {
  const _MatchTile({
    required this.match,
    required this.home,
    required this.away,
    required this.onTap,
  });

  final ChampionshipMatch match;
  final ChampionshipTeam? home;
  final ChampionshipTeam? away;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final when = match.scheduledAt;
    final details = [
      if (when != null)
        '${formatGameDay(when)} às ${formatGameTime(when)}'
      else
        'Data a definir',
      ?match.venueName,
    ].join(' · ');

    Widget side(ChampionshipTeam? team, {required bool end}) => Expanded(
      child: Row(
        mainAxisAlignment: end
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (!end) ...[
            TeamLogo.url(logoUrl: team?.logoUrl, radius: 12),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Text(
              team?.name ?? 'A definir',
              overflow: TextOverflow.ellipsis,
              textAlign: end ? TextAlign.end : TextAlign.start,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: team == null ? colors.onSurfaceVariant : null,
              ),
            ),
          ),
          if (end) ...[
            const SizedBox(width: 8),
            TeamLogo.url(logoUrl: team?.logoUrl, radius: 12),
          ],
        ],
      ),
    );

    final penalties = match.homePenalties != null
        ? ' (${match.homePenalties} x ${match.awayPenalties} pên.)'
        : '';

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                children: [
                  side(home, end: false),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      match.hasScore
                          ? '${match.homeScore} x ${match.awayScore}'
                          : 'x',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  side(away, end: true),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '$details$penalties',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

typedef _ScoreResult = ({
  int home,
  int away,
  int? homePenalties,
  int? awayPenalties,
});

/// Placar do jogo e, no mata-mata empatado, os pênaltis.
class _ScoreSheet extends StatefulWidget {
  const _ScoreSheet({
    required this.match,
    required this.home,
    required this.away,
  });

  final ChampionshipMatch match;
  final String home;
  final String away;

  @override
  State<_ScoreSheet> createState() => _ScoreSheetState();
}

class _ScoreSheetState extends State<_ScoreSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _home = TextEditingController(
    text: widget.match.homeScore?.toString(),
  );
  late final _away = TextEditingController(
    text: widget.match.awayScore?.toString(),
  );
  late final _homePen = TextEditingController(
    text: widget.match.homePenalties?.toString(),
  );
  late final _awayPen = TextEditingController(
    text: widget.match.awayPenalties?.toString(),
  );

  bool get _knockout => widget.match.stage == MatchStage.knockout;

  bool get _tied =>
      _home.text.isNotEmpty && _home.text.trim() == _away.text.trim();

  @override
  void dispose() {
    for (final controller in [_home, _away, _homePen, _awayPen]) {
      controller.dispose();
    }
    super.dispose();
  }

  Widget _field(TextEditingController controller, String label) =>
      TextFormField(
        controller: controller,
        decoration: InputDecoration(labelText: label),
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        textAlign: TextAlign.center,
        onChanged: (_) => setState(() {}),
        validator: (value) => (value ?? '').isEmpty ? 'Informe' : null,
      );

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final penalties = _knockout && _tied;
    final homePen = penalties ? int.parse(_homePen.text) : null;
    final awayPen = penalties ? int.parse(_awayPen.text) : null;
    if (penalties && homePen == awayPen) {
      showErrorSnackBar(context, 'Os pênaltis precisam ter um vencedor.');
      return;
    }
    Navigator.of(context).pop<_ScoreResult>((
      home: int.parse(_home.text),
      away: int.parse(_away.text),
      homePenalties: homePen,
      awayPenalties: awayPen,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: AppSheet(
        title: 'Placar',
        message: '${widget.home} x ${widget.away}',
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(child: _field(_home, widget.home)),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text('x'),
                ),
                Expanded(child: _field(_away, widget.away)),
              ],
            ),
            if (_knockout && _tied) ...[
              const SizedBox(height: 16),
              const Text('Empate no mata-mata: e nos pênaltis?'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _field(_homePen, 'Pênaltis')),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('x'),
                  ),
                  Expanded(child: _field(_awayPen, 'Pênaltis')),
                ],
              ),
            ],
          ],
        ),
        actions: [
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check),
            label: const Text('Salvar placar'),
          ),
          const SheetBackButton(),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Artilharia
// ---------------------------------------------------------------------------

/// Artilheiros e garçons do campeonato, da súmula dos jogos.
class _ScorersTab extends ConsumerWidget {
  const _ScorersTab({required this.championshipId});

  final String championshipId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totals = ref.watch(championshipPlayerTotalsProvider(championshipId));
    return totals.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => Center(
        child: TextButton.icon(
          onPressed: () =>
              ref.invalidate(championshipPlayerTotalsProvider(championshipId)),
          icon: const Icon(Icons.refresh),
          label: const Text('Erro ao carregar. Tentar novamente'),
        ),
      ),
      data: (totals) {
        // Mais gols (ou assistências) primeiro; empate, quem jogou menos.
        List<ChampionshipPlayerTotal> ranked(
          int Function(ChampionshipPlayerTotal) value,
        ) => totals.where((t) => value(t) > 0).toList()
          ..sort((a, b) {
            final byValue = value(b).compareTo(value(a));
            if (byValue != 0) return byValue;
            final byGames = a.games.compareTo(b.games);
            return byGames != 0 ? byGames : a.name.compareTo(b.name);
          });
        final scorers = ranked((t) => t.goals);
        final assisters = ranked((t) => t.assists);
        if (scorers.isEmpty && assisters.isEmpty) {
          return const EmptyState(
            icon: Icons.sports_soccer,
            title: 'Sem gols ainda',
            message:
                'A artilharia vem da súmula dos jogos do campeonato, lançada '
                'pelos times.',
          );
        }
        return RefreshIndicator(
          onRefresh: () => ref.refresh(
            championshipPlayerTotalsProvider(championshipId).future,
          ),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              if (scorers.isNotEmpty)
                _RankingCard(
                  title: 'Artilheiros',
                  unit: ('gol', 'gols'),
                  totals: scorers,
                  value: (t) => t.goals,
                ),
              if (assisters.isNotEmpty) ...[
                const SizedBox(height: 16),
                _RankingCard(
                  title: 'Garçons',
                  unit: ('assistência', 'assistências'),
                  totals: assisters,
                  value: (t) => t.assists,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _RankingCard extends StatelessWidget {
  const _RankingCard({
    required this.title,
    required this.unit,
    required this.totals,
    required this.value,
  });

  final String title;

  /// Singular e plural ("gol", "gols").
  final (String, String) unit;
  final List<ChampionshipPlayerTotal> totals;
  final int Function(ChampionshipPlayerTotal) value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final (index, total) in totals.indexed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 24,
                      child: Text(
                        '${index + 1}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: index == 0 ? colors.primary : null,
                          fontWeight: index == 0 ? FontWeight.w700 : null,
                        ),
                      ),
                    ),
                    TeamLogo.url(logoUrl: total.logoUrl, radius: 14),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            total.name,
                            style: theme.textTheme.bodyLarge,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            total.teamName,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${value(total)} '
                      '${value(total) == 1 ? unit.$1 : unit.$2}',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Times
// ---------------------------------------------------------------------------

class _TeamsTab extends StatelessWidget {
  const _TeamsTab({
    required this.championship,
    required this.teams,
    required this.isOwner,
    required this.userId,
    required this.onAdd,
    required this.onStart,
    required this.onRemove,
    required this.onRespond,
    required this.onGuestLogo,
  });

  final Championship championship;
  final List<ChampionshipTeam> teams;
  final bool isOwner;
  final String? userId;
  final VoidCallback onAdd;
  final VoidCallback onStart;
  final ValueChanged<ChampionshipTeam> onRemove;
  final void Function(ChampionshipTeam entry, bool accept) onRespond;

  /// O organizador troca o símbolo de um time fictício.
  final ValueChanged<ChampionshipTeam> onGuestLogo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final draft = championship.status == ChampionshipStatus.draft;
    final confirmed = teams
        .where((t) => t.status == EntryStatus.accepted)
        .length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(championship.summary),
            subtitle: Text(
              '${championship.modality.label} · ${championship.status.label}'
              '${draft ? ' · $confirmed confirmados' : ''}',
            ),
          ),
        ),
        if (isOwner && draft) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.group_add_outlined),
                  label: const Text('Adicionar time'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: onStart,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Gerar tabela'),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        if (teams.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Text(
              isOwner
                  ? 'Adicione os times: os da plataforma recebem o convite, '
                        'os fictícios já entram confirmados.'
                  : 'Nenhum time inscrito ainda.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
        for (final entry in teams)
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  ListTile(
                    // O organizador toca no fictício para enviar o símbolo
                    // (o selo da câmera mostra que dá).
                    onTap: isOwner && entry.isGuest
                        ? () => onGuestLogo(entry)
                        : null,
                    leading: isOwner && entry.isGuest
                        ? Semantics(
                            button: true,
                            label: entry.logoUrl == null
                                ? 'Enviar símbolo do ${entry.name}'
                                : 'Trocar símbolo do ${entry.name}',
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                TeamLogo.url(logoUrl: entry.logoUrl),
                                Positioned(
                                  right: -4,
                                  bottom: -4,
                                  child: CircleAvatar(
                                    radius: 9,
                                    backgroundColor: colors.primary,
                                    child: Icon(
                                      Icons.photo_camera,
                                      size: 11,
                                      color: colors.onPrimary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : TeamLogo.url(logoUrl: entry.logoUrl),
                    title: Text(entry.name),
                    subtitle: Text(
                      [
                        if (entry.isGuest) 'Fictício',
                        if (entry.groupLabel case final group?) 'Grupo $group',
                        if (draft || entry.status != EntryStatus.accepted)
                          entry.status.label,
                      ].join(' · '),
                      style: TextStyle(
                        color: switch (entry.status) {
                          EntryStatus.accepted => null,
                          EntryStatus.invited => colors.tertiary,
                          EntryStatus.declined => colors.error,
                        },
                      ),
                    ),
                    trailing: isOwner && draft
                        ? IconButton(
                            tooltip: 'Tirar ${entry.name}',
                            icon: const Icon(Icons.close),
                            onPressed: () => onRemove(entry),
                          )
                        : null,
                  ),
                  // O dono do time convidado responde aqui.
                  if (draft &&
                      entry.status == EntryStatus.invited &&
                      entry.ownerId == userId &&
                      !isOwner)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => onRespond(entry, false),
                              child: const Text('Recusar'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton(
                              onPressed: () => onRespond(entry, true),
                              child: const Text('Aceitar'),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
