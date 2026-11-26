import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../plans/presentation/plan_gate.dart';
import '../../sports/domain/sport_rules.dart';
import '../../teams/domain/team.dart';
import '../data/championship_repository.dart';
import '../domain/championship.dart';
import '../domain/championship_rules.dart';

/// Cria o campeonato (ou edita, antes de começar): nome, modalidade e o
/// formato, com as opções de cada um. Fecha devolvendo o campeonato salvo.
class ChampionshipFormPage extends ConsumerStatefulWidget {
  const ChampionshipFormPage({super.key, this.championship});

  final Championship? championship;

  @override
  ConsumerState<ChampionshipFormPage> createState() =>
      _ChampionshipFormPageState();
}

class _ChampionshipFormPageState extends ConsumerState<ChampionshipFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.championship?.name);
  late var _modality = widget.championship?.modality ?? Modality.society;
  late var _format = widget.championship?.format ?? ChampionshipFormat.league;
  late var _doubleRound = widget.championship?.doubleRound ?? false;
  // Grupos + mata-mata.
  late var _teams = widget.championship?.teamCount ?? 8;
  late var _maxPerGroup = widget.championship?.groupSize ?? 4;
  late var _qualifiers = widget.championship?.qualifiersPerGroup ?? 2;
  late var _fill = widget.championship?.knockoutFill ?? KnockoutFill.bestPlaced;
  // Liga + mata-mata.
  late var _leagueQualifiers = widget.championship?.knockoutQualifiers ?? 8;

  /// Suspensão automática: amarelos para 1 jogo (0 desliga) e jogos por
  /// expulsão (0 desliga).
  late var _yellowLimit = widget.championship?.yellowLimit ?? 3;
  late var _redGames = widget.championship?.redGames ?? 1;
  var _loading = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  GroupsLayout get _layout => GroupsLayout.fromMax(
    teams: _teams,
    maxPerGroup: _maxPerGroup,
    qualifiers: _qualifiers,
    fill: _fill,
  );

  /// Muda os números e mantém os classificados dentro do possível.
  void _setGroups({int? teams, int? maxPerGroup, int? qualifiers}) {
    setState(() {
      _teams = teams ?? _teams;
      _maxPerGroup = maxPerGroup ?? _maxPerGroup;
      _qualifiers = qualifiers ?? _qualifiers;
      final most = _layout.smallestGroup - 1;
      if (most >= 1 && _qualifiers > most) _qualifiers = most;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_format == ChampionshipFormat.groups) {
      if (_layout.error case final error?) {
        showErrorSnackBar(context, error);
        return;
      }
    }
    setState(() => _loading = true);
    final championship = Championship(
      id: widget.championship?.id,
      ownerId: ref.read(currentUserIdProvider)!,
      name: _name.text,
      modality: _modality,
      format: _format,
      doubleRound: _doubleRound,
      groupCount: _layout.groups,
      qualifiersPerGroup: _qualifiers,
      teamCount: _teams,
      groupSize: _maxPerGroup,
      knockoutFill: _layout.effectiveFill,
      knockoutQualifiers: _leagueQualifiers,
      yellowLimit: _yellowLimit,
      redGames: _redGames,
    );
    try {
      final repository = ref.read(championshipRepositoryProvider);
      final saved = widget.championship == null
          ? await repository.create(championship)
          : championship;
      if (widget.championship != null) await repository.update(championship);
      if (mounted) context.pop(saved);
    } catch (error) {
      if (mounted && !handlePlanLimitError(context, error)) {
        showErrorSnackBar(context, friendlyErrorMessage(error));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.championship == null ? 'Novo campeonato' : 'Editar campeonato',
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Nome'),
              textCapitalization: TextCapitalization.words,
              maxLength: 60,
              validator: (value) => (value?.trim().length ?? 0) < 3
                  ? 'Informe o nome (pelo menos 3 letras)'
                  : null,
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<Modality>(
              initialValue: _modality,
              decoration: const InputDecoration(labelText: 'Modalidade'),
              items: [
                // As dos esportes liberados (e a do campeonato, se for outra).
                for (final modality in {...availableModalities, _modality})
                  DropdownMenuItem(
                    value: modality,
                    child: Text(modality.label),
                  ),
              ],
              onChanged: (value) => setState(() => _modality = value!),
            ),
            const SizedBox(height: 24),
            Text('Formato', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            RadioGroup<ChampionshipFormat>(
              groupValue: _format,
              onChanged: (value) => setState(() => _format = value!),
              child: Column(
                children: [
                  for (final format in ChampionshipFormat.values)
                    Card(
                      child: RadioListTile<ChampionshipFormat>(
                        value: format,
                        title: Text(format.label),
                        subtitle: Text(format.description),
                      ),
                    ),
                ],
              ),
            ),
            if (_format != ChampionshipFormat.knockout) ...[
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  _format == ChampionshipFormat.groups
                      ? 'Ida e volta nos grupos'
                      : 'Turno e returno',
                ),
                subtitle: const Text('Cada confronto acontece duas vezes'),
                value: _doubleRound,
                onChanged: (value) => setState(() => _doubleRound = value),
              ),
            ],
            if (_format == ChampionshipFormat.leagueKnockout) ...[
              _NumberField(
                label: 'Classificados para o mata-mata',
                hint: 'Os primeiros colocados da liga',
                value: _leagueQualifiers,
                min: LeagueKnockoutLayout.minQualifiers,
                max: LeagueKnockoutLayout.maxQualifiers,
                onChanged: (value) => setState(() => _leagueQualifiers = value),
              ),
              const SizedBox(height: 8),
              _LeagueKnockoutSummary(
                layout: LeagueKnockoutLayout(_leagueQualifiers),
              ),
            ],
            if (_format == ChampionshipFormat.groups) ...[
              const SizedBox(height: 8),
              _NumberField(
                label: 'Times no campeonato',
                value: _teams,
                min: GroupsLayout.minTeams,
                max: GroupsLayout.maxTeams,
                onChanged: (value) => _setGroups(teams: value),
              ),
              _NumberField(
                label: 'Times por grupo',
                hint: 'No máximo; o app divide o mais parelho possível',
                value: _maxPerGroup,
                min: 2,
                max: _teams ~/ 2,
                onChanged: (value) => _setGroups(maxPerGroup: value),
              ),
              _NumberField(
                label: 'Classificados por grupo',
                value: _qualifiers,
                min: 1,
                max: _layout.smallestGroup - 1 < 1
                    ? 1
                    : _layout.smallestGroup - 1,
                onChanged: (value) => _setGroups(qualifiers: value),
              ),
              const SizedBox(height: 8),
              _GroupsSummary(
                layout: _layout,
                onFillChanged: (fill) => setState(() => _fill = fill),
              ),
            ],
            // Suspensão automática (a escalação e a súmula avisam).
            const SizedBox(height: 24),
            Text(
              'Suspensão automática',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Vale para o próximo jogo do time. A escalação e a súmula '
              'avisam quem está suspenso. Zero desliga.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            _NumberField(
              label: 'Amarelos para 1 jogo',
              hint: _yellowLimit == 0
                  ? 'Amarelos não suspendem'
                  : 'A cada $_yellowLimit amarelos, 1 jogo fora',
              value: _yellowLimit,
              min: 0,
              max: 10,
              onChanged: (value) => setState(() => _yellowLimit = value),
            ),
            _NumberField(
              label: 'Jogos por expulsão',
              hint: _redGames == 0
                  ? 'Expulsão não suspende'
                  : 'Vermelho ou 2º amarelo',
              value: _redGames,
              min: 0,
              max: 5,
              onChanged: (value) => setState(() => _redGames = value),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _loading ? null : _save,
              icon: _loading
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: Text(
                widget.championship == null ? 'Criar campeonato' : 'Salvar',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Número com os botões de menos e mais.
class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.hint,
  });

  final String label;
  final String? hint;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.bodyLarge),
                if (hint case final hint?)
                  Text(
                    hint,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          IconButton.outlined(
            tooltip: 'Menos: $label',
            onPressed: value > min ? () => onChanged(value - 1) : null,
            icon: const Icon(Icons.remove),
          ),
          SizedBox(
            width: 40,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
          ),
          IconButton.outlined(
            tooltip: 'Mais: $label',
            onPressed: value < max ? () => onChanged(value + 1) : null,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}

/// Liga + mata-mata: como fica o chaveamento com os classificados e, quando
/// não fecha, quem folga.
class _LeagueKnockoutSummary extends StatelessWidget {
  const _LeagueKnockoutSummary({required this.layout});

  final LeagueKnockoutLayout layout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = layout.qualifiers;
    final byes = layout.byes;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Os $q primeiros fazem o mata-mata',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(switch (layout.bracket) {
              2 => 'A final é entre o 1º e o 2º colocados.',
              final size when byes == 0 =>
                'Começa ${inKnockoutRound(size ~/ 2)}: 1º x $sizeº, '
                    '2º x ${size - 1}º e assim por diante.',
              final size =>
                'Começa ${inKnockoutRound(size ~/ 2)}: ${byes + 1}º x '
                    '$qº e assim por diante; o melhor colocado pega o pior.',
            }),
            if (byes > 0)
              Text(
                byes == 1
                    ? 'O 1º colocado folga e passa direto '
                          '${inKnockoutRound(layout.bracket ~/ 4, to: true)}.'
                    : 'Os $byes primeiros colocados folgam e passam direto '
                          '${inKnockoutRound(layout.bracket ~/ 4, to: true)}.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            Text(
              'Precisa de pelo menos ${max(3, q + 1)} times confirmados.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Como fica o formato: os grupos, quantos vão ao mata-mata e, quando não
/// fecha, como completar.
class _GroupsSummary extends StatelessWidget {
  const _GroupsSummary({required this.layout, required this.onFillChanged});

  final GroupsLayout layout;
  final ValueChanged<KnockoutFill> onFillChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    if (layout.error case final error?) {
      return Card(
        color: colors.errorContainer,
        child: ListTile(
          leading: Icon(Icons.error_outline, color: colors.onErrorContainer),
          title: Text(error),
          textColor: colors.onErrorContainer,
        ),
      );
    }
    final q = layout.qualifiers;
    final missing = layout.missing;
    final next = q + 1;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(layout.groupsText, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '${q == 1 ? 'Passa o 1º' : 'Passam os $q primeiros'} de cada '
              'grupo: ${layout.direct} classificados.',
            ),
            Text(
              'Mata-mata com ${layout.bracket} times, começando '
              '${inKnockoutRound(layout.bracket ~/ 2)}.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            if (missing > 0) ...[
              const SizedBox(height: 12),
              Text(
                'Faltam $missing ${missing == 1 ? 'vaga' : 'vagas'} para '
                'fechar o mata-mata. Como completar?',
                style: theme.textTheme.titleSmall,
              ),
              RadioGroup<KnockoutFill>(
                groupValue: layout.effectiveFill,
                onChanged: (value) => onFillChanged(value!),
                child: Column(
                  children: [
                    RadioListTile<KnockoutFill>(
                      contentPadding: EdgeInsets.zero,
                      value: KnockoutFill.bestPlaced,
                      enabled: layout.canUseBestPlaced,
                      title: Text(
                        missing == 1
                            ? 'O melhor $nextº colocado'
                            : 'Os $missing melhores $nextº colocados',
                      ),
                      subtitle: Text(
                        layout.canUseBestPlaced
                            ? 'Comparados entre os grupos por pontos por '
                                  'jogo, saldo e gols'
                            : 'Não há $nextº colocados que bastem',
                      ),
                    ),
                    RadioListTile<KnockoutFill>(
                      contentPadding: EdgeInsets.zero,
                      value: KnockoutFill.byes,
                      title: Text(
                        missing == 1
                            ? 'Folga para o melhor classificado'
                            : 'Folga para os $missing melhores classificados',
                      ),
                      subtitle: Text(
                        '${missing == 1 ? 'Passa' : 'Passam'} direto '
                        '${inKnockoutRound(layout.bracket ~/ 4, to: true)}',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
