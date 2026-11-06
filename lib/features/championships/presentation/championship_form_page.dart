import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../plans/presentation/plan_gate.dart';
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
                for (final modality in Modality.values)
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
