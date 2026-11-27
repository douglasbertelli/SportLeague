import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/empty_state.dart';
import '../../teams/presentation/team_logo.dart';
import '../../sports/domain/sport_rules.dart';
import '../data/championship_repository.dart';
import '../domain/championship_stats.dart';

/// As outras visões, além dos rankings de atletas do esporte.
enum _View {
  cards('Cartões'),
  teams('Ataque e defesa'),
  fairPlay('Fair play'),
  rounds('Seleção da rodada');

  const _View(this.label);
  final String label;
}

/// Estatísticas do campeonato: os rankings de atletas do esporte (no
/// futebol, artilharia e assistências; no vôlei, pontos, aces e bloqueios),
/// cartões (com os suspensos) e fair play nos esportes com cartão, ataque e
/// defesa e seleção da rodada.
class ChampionshipStatsTab extends ConsumerStatefulWidget {
  const ChampionshipStatsTab({
    super.key,
    required this.championshipId,
    this.rules = footballRules,
  });

  final String championshipId;
  final SportRules rules;

  @override
  ConsumerState<ChampionshipStatsTab> createState() =>
      _ChampionshipStatsTabState();
}

class _ChampionshipStatsTabState extends ConsumerState<ChampionshipStatsTab> {
  /// Ranking escolhido (a chave da estatística) ou, nulo, a [_view].
  late String? _ranking = widget.rules.rankings.firstOrNull?.statKey;
  _View _view = _View.teams;

  /// Cartões e fair play só nos esportes com cartão na súmula.
  bool get _hasCards => widget.rules.stat('yellow_cards') != null;

  @override
  Widget build(BuildContext context) {
    final provider = championshipStatsProvider(widget.championshipId);
    final stats = ref.watch(provider);
    return stats.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => Center(
        child: TextButton.icon(
          onPressed: () => ref.invalidate(provider),
          icon: const Icon(Icons.refresh),
          label: const Text('Erro ao carregar. Tentar novamente'),
        ),
      ),
      data: (stats) => RefreshIndicator(
        onRefresh: () => ref.refresh(provider.future),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            // Qual estatística: chips com rolagem para o lado.
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final ranking in widget.rules.rankings)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(ranking.championshipTitle ?? ranking.title),
                        selected: _ranking == ranking.statKey,
                        onSelected: (_) =>
                            setState(() => _ranking = ranking.statKey),
                      ),
                    ),
                  for (final view in _View.values)
                    if (_hasCards ||
                        (view != _View.cards && view != _View.fairPlay))
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(view.label),
                          selected: _ranking == null && view == _view,
                          onSelected: (_) => setState(() {
                            _ranking = null;
                            _view = view;
                          }),
                        ),
                      ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            ...switch ((_ranking, widget.rules.stat(_ranking ?? ''))) {
              (final key?, final stat?) => _players(
                stats.ranking(key),
                (p) => p.value(key),
                (stat.unit.singular, stat.unit.plural),
                empty: 'O ranking vem da súmula dos jogos.',
              ),
              _ => switch (_view) {
                _View.cards => _cards(stats),
                _View.teams => _teams(stats),
                _View.fairPlay => _fairPlay(stats),
                _View.rounds => _rounds(stats),
              },
            },
          ],
        ),
      ),
    );
  }

  List<Widget> _empty(String message) => [
    EmptyState(
      icon: Icons.insights_outlined,
      title: 'Sem dados ainda',
      message: message,
    ),
  ];

  List<Widget> _players(
    List<StatsPlayer> players,
    int Function(StatsPlayer) value,
    (String, String) unit, {
    required String empty,
  }) {
    if (players.isEmpty) return _empty(empty);
    return [
      _RankCard(
        rows: [
          for (final player in players)
            _Row(
              title: player.name,
              subtitle: player.teamName,
              logoUrl: player.logoUrl,
              value:
                  '${value(player)} '
                  '${value(player) == 1 ? unit.$1 : unit.$2}',
            ),
        ],
      ),
    ];
  }

  List<Widget> _cards(ChampionshipStats stats) {
    final theme = Theme.of(context);
    return [
      // Regra e quem está suspenso no próximo jogo do time.
      Text(
        [
          if (stats.yellowLimit > 0) '${stats.yellowLimit} amarelos = 1 jogo',
          if (stats.redGames > 0)
            'vermelho = ${stats.redGames} '
                '${stats.redGames == 1 ? 'jogo' : 'jogos'}',
        ].join(' · ').ifEmpty('Sem suspensão automática'),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 8),
      if (stats.suspended.isNotEmpty) ...[
        _RankCard(
          title: 'Suspensos no próximo jogo',
          rows: [
            for (final player in stats.suspended)
              _Row(
                title: player.name,
                subtitle: player.teamName,
                value: player.reason ?? 'Suspenso',
                icon: Icons.block,
              ),
          ],
        ),
        const SizedBox(height: 12),
      ],
      if (stats.carded.isEmpty)
        ..._empty('Os cartões vêm da súmula dos jogos.')
      else
        _RankCard(
          title: 'Cartões por atleta',
          rows: [
            for (final player in stats.carded)
              _Row(
                title: player.name,
                subtitle: player.teamName,
                logoUrl: player.logoUrl,
                value: [
                  if (player.yellowCards > 0) '🟨 ${player.yellowCards}',
                  if (player.redCards > 0) '🟥 ${player.redCards}',
                ].join('  '),
              ),
          ],
        ),
    ];
  }

  List<Widget> _teams(ChampionshipStats stats) {
    if (stats.byAttack.isEmpty) {
      return _empty('Ataque e defesa aparecem depois dos primeiros jogos.');
    }
    return [
      _RankCard(
        title: 'Melhor ataque',
        rows: [
          for (final team in stats.byAttack)
            _Row(
              title: team.name,
              subtitle:
                  '${team.played} jogos · saldo ${_signed(team.goalDifference)}',
              logoUrl: team.logoUrl,
              // Gols no futebol, sets no vôlei.
              value: widget.rules.scoreUnit.count(team.goalsFor),
            ),
        ],
      ),
      const SizedBox(height: 12),
      _RankCard(
        title: 'Melhor defesa',
        rows: [
          for (final team in stats.byDefense)
            _Row(
              title: team.name,
              subtitle: '${team.played} jogos',
              logoUrl: team.logoUrl,
              value:
                  '${team.goalsAgainst} '
                  '${team.goalsAgainst == 1 ? 'sofrido' : 'sofridos'}',
            ),
        ],
      ),
    ];
  }

  List<Widget> _fairPlay(ChampionshipStats stats) {
    if (stats.byFairPlay.isEmpty) {
      return _empty('O fair play aparece depois dos primeiros jogos.');
    }
    final theme = Theme.of(context);
    return [
      Text(
        'Amarelo vale 1 ponto e vermelho, 3. Menos pontos, mais disciplina.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 8),
      _RankCard(
        rows: [
          for (final team in stats.byFairPlay)
            _Row(
              title: team.name,
              subtitle: '🟨 ${team.yellowCards}  🟥 ${team.redCards}',
              logoUrl: team.logoUrl,
              value:
                  '${team.fairPlay} ${team.fairPlay == 1 ? 'ponto' : 'pontos'}',
            ),
        ],
      ),
    ];
  }

  List<Widget> _rounds(ChampionshipStats stats) {
    if (stats.rounds.isEmpty) {
      return _empty(
        'A seleção da rodada vem do craque que cada time escolhe na súmula.',
      );
    }
    return [
      for (final round in stats.rounds) ...[
        _RankCard(
          title: round.stage == 'knockout'
              ? 'Mata-mata · fase ${round.round}'
              : 'Rodada ${round.round}',
          rows: [
            for (final player in round.players)
              _Row(
                title: player.name,
                subtitle: player.teamName,
                logoUrl: player.logoUrl,
                value: [
                  if (player.goals > 0) '⚽ ${player.goals}',
                  if (player.assists > 0) '🅰️ ${player.assists}',
                ].join('  '),
                highlight: player.top,
                icon: player.top ? Icons.star : null,
              ),
          ],
        ),
        const SizedBox(height: 12),
      ],
    ];
  }

  static String _signed(int value) => value > 0 ? '+$value' : '$value';
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}

class _Row {
  const _Row({
    required this.title,
    required this.subtitle,
    required this.value,
    this.logoUrl,
    this.icon,
    this.highlight = false,
  });

  final String title;
  final String subtitle;
  final String value;
  final String? logoUrl;
  final IconData? icon;

  /// Craque da rodada: em destaque.
  final bool highlight;
}

/// Card de ranking: posição, escudo, nome, time e o número.
class _RankCard extends StatelessWidget {
  const _RankCard({required this.rows, this.title});

  final String? title;
  final List<_Row> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final title = this.title;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              Text(title, style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
            ],
            for (final (index, row) in rows.indexed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 24,
                      child: row.icon != null
                          ? Icon(
                              row.icon,
                              size: 18,
                              color: row.highlight
                                  ? const Color(0xFFF5C518)
                                  : colors.error,
                            )
                          : Text(
                              '${index + 1}',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: index == 0 ? colors.primary : null,
                                fontWeight: index == 0 ? FontWeight.w700 : null,
                              ),
                            ),
                    ),
                    TeamLogo.url(logoUrl: row.logoUrl, radius: 14),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            row.title,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: row.highlight
                                  ? FontWeight.w700
                                  : null,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            row.subtitle,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      row.value,
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
