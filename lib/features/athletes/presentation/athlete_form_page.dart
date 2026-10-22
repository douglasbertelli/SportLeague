import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/error_messages.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/form_page.dart';
import '../../../core/widgets/loading_button.dart';
import '../../teams/data/team_repository.dart';
import '../data/athlete_repository.dart';
import '../domain/athlete.dart';

/// Cadastra um atleta no time ativo ou edita/exclui um existente.
class AthleteFormPage extends ConsumerStatefulWidget {
  const AthleteFormPage({super.key, this.athlete});

  final Athlete? athlete;

  @override
  ConsumerState<AthleteFormPage> createState() => _AthleteFormPageState();
}

class _AthleteFormPageState extends ConsumerState<AthleteFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(
    text: widget.athlete?.name,
  );
  late final _numberController = TextEditingController(
    text: widget.athlete?.jerseyNumber?.toString(),
  );
  late String? _position = widget.athlete?.position;
  bool _loading = false;

  bool get _isEditing => widget.athlete != null;

  @override
  void dispose() {
    _nameController.dispose();
    _numberController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_loading || !_formKey.currentState!.validate()) return;
    final teamId =
        widget.athlete?.teamId ?? ref.read(selectedTeamProvider).value?.id;
    if (teamId == null) return;

    final athlete = Athlete(
      id: widget.athlete?.id,
      teamId: teamId,
      name: _nameController.text,
      position: _position,
      jerseyNumber: int.tryParse(_numberController.text),
    );
    final repository = ref.read(athleteRepositoryProvider);
    await _run(
      teamId,
      () =>
          _isEditing ? repository.update(athlete) : repository.create(athlete),
    );
  }

  Future<void> _delete() async {
    final athlete = widget.athlete!;
    final confirmed = await confirmDelete(
      context,
      title: 'Excluir atleta?',
      message: '${athlete.name} será removido do time.',
    );
    if (!confirmed) return;
    await _run(
      athlete.teamId,
      () => ref.read(athleteRepositoryProvider).delete(athlete.id!),
    );
  }

  Future<void> _run(String teamId, Future<void> Function() action) async {
    setState(() => _loading = true);
    try {
      await action();
      ref.invalidate(teamAthletesProvider(teamId));
      if (mounted) context.pop();
    } catch (error) {
      if (mounted) showErrorSnackBar(context, friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final teamName = ref.watch(selectedTeamProvider).value?.name;
    final positions = [
      ...footballPositions,
      // Mantém uma posição antiga que não está mais na lista.
      if (_position != null && !footballPositions.contains(_position))
        _position!,
    ];

    return FormPage(
      appBar: AppBar(
        title: Text(_isEditing ? 'Editar atleta' : 'Novo atleta'),
        actions: [
          if (_isEditing)
            IconButton(
              tooltip: 'Excluir atleta',
              icon: const Icon(Icons.delete_outline),
              onPressed: _loading ? null : _delete,
            ),
        ],
      ),
      children: [
        if (!_isEditing && teamName != null) ...[
          Text(
            'Time: $teamName',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 16),
        ],
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Nome do atleta'),
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                maxLength: 120,
                validator: (value) =>
                    Validators.name(value, message: 'Informe o nome do atleta'),
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String>(
                      initialValue: _position,
                      decoration: const InputDecoration(
                        labelText: 'Posição (opcional)',
                      ),
                      items: [
                        for (final position in positions)
                          DropdownMenuItem(
                            value: position,
                            child: Text(position),
                          ),
                      ],
                      onChanged: (value) => setState(() => _position = value),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _numberController,
                      decoration: const InputDecoration(labelText: 'Número'),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(3),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        LoadingButton(
          label: _isEditing ? 'Salvar' : 'Cadastrar atleta',
          loading: _loading,
          onPressed: _save,
        ),
      ],
    );
  }
}
