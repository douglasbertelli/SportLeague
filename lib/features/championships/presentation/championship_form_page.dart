import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../plans/data/plan_repository.dart';
import '../../plans/domain/plan_status.dart';
import '../../plans/presentation/plan_gate.dart';
import '../../teams/domain/team.dart';
import '../data/championship_repository.dart';
import '../domain/championship.dart';

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
  late var _groupCount = widget.championship?.groupCount ?? 2;
  late var _qualifiers = widget.championship?.qualifiersPerGroup ?? 2;
  var _loading = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    final championship = Championship(
      id: widget.championship?.id,
      ownerId: ref.read(currentUserIdProvider)!,
      name: _name.text,
      modality: _modality,
      format: _format,
      doubleRound: _doubleRound,
      groupCount: _groupCount,
      qualifiersPerGroup: _qualifiers,
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

  /// Formato que o plano não libera (o que o campeonato já tem continua).
  bool _locked(ChampionshipFormat format, PlanStatus plan) =>
      format != ChampionshipFormat.league &&
      format != widget.championship?.format &&
      !plan.has(PlanFeature.advancedFormats);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plan = ref.watch(planStatusProvider).value ?? PlanStatus.unrestricted;
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
              onChanged: (value) {
                if (_locked(value!, plan)) {
                  showPremiumSheet(context, PlanFeature.advancedFormats);
                  return;
                }
                setState(() => _format = value);
              },
              child: Column(
                children: [
                  for (final format in ChampionshipFormat.values)
                    Card(
                      child: RadioListTile<ChampionshipFormat>(
                        value: format,
                        title: Row(
                          children: [
                            Flexible(child: Text(format.label)),
                            if (_locked(format, plan)) ...[
                              const SizedBox(width: 8),
                              const PremiumBadge(),
                            ],
                          ],
                        ),
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
              Text('Grupos', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 2, label: Text('2 grupos')),
                  ButtonSegment(value: 4, label: Text('4 grupos')),
                  ButtonSegment(value: 8, label: Text('8 grupos')),
                ],
                selected: {_groupCount},
                onSelectionChanged: (value) =>
                    setState(() => _groupCount = value.single),
              ),
              const SizedBox(height: 16),
              Text(
                'Classificados por grupo',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 1, label: Text('1 (o líder)')),
                  ButtonSegment(value: 2, label: Text('2 (1º e 2º)')),
                ],
                selected: {_qualifiers},
                onSelectionChanged: (value) =>
                    setState(() => _qualifiers = value.single),
              ),
              const SizedBox(height: 8),
              Text(
                '${_groupCount * _qualifiers} times no mata-mata.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
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
