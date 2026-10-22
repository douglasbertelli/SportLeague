import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/form_page.dart';
import '../../../core/widgets/loading_button.dart';
import '../data/team_repository.dart';
import '../domain/team.dart';

/// Cria um time ou edita/exclui um existente ([team] preenchido).
class TeamFormPage extends ConsumerStatefulWidget {
  const TeamFormPage({super.key, this.team});

  final Team? team;

  @override
  ConsumerState<TeamFormPage> createState() => _TeamFormPageState();
}

class _TeamFormPageState extends ConsumerState<TeamFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.team?.name);
  late final _cityController = TextEditingController(text: widget.team?.city);
  late final _stateController = TextEditingController(text: widget.team?.state);
  late final _descriptionController = TextEditingController(
    text: widget.team?.description,
  );
  bool _loading = false;

  bool get _isEditing => widget.team != null;

  @override
  void dispose() {
    _nameController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_loading || !_formKey.currentState!.validate()) return;
    final ownerId = ref.read(currentUserIdProvider);
    if (ownerId == null) return;

    final team = Team(
      id: widget.team?.id,
      ownerId: ownerId,
      name: _nameController.text,
      sport: widget.team?.sport ?? Sport.football,
      city: _cityController.text,
      state: _stateController.text,
      description: _descriptionController.text,
    );

    await _run(() async {
      final repository = ref.read(teamRepositoryProvider);
      if (_isEditing) {
        await repository.update(team);
      } else {
        final created = await repository.create(team);
        // O time recém-criado passa a ser o time ativo.
        await ref.read(selectedTeamIdProvider.notifier).select(created.id!);
      }
    });
  }

  Future<void> _delete() async {
    final confirmed = await confirmDelete(
      context,
      title: 'Excluir time?',
      message:
          'O time "${widget.team!.name}" será excluído junto com todos os '
          'atletas e jogos dele. Essa ação não pode ser desfeita.',
    );
    if (!confirmed) return;
    await _run(() => ref.read(teamRepositoryProvider).delete(widget.team!.id!));
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _loading = true);
    try {
      await action();
      ref.invalidate(myTeamsProvider);
      if (mounted) context.pop();
    } catch (error) {
      if (mounted) showErrorSnackBar(context, friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FormPage(
      appBar: AppBar(
        title: Text(_isEditing ? 'Editar time' : 'Novo time'),
        actions: [
          if (_isEditing)
            IconButton(
              tooltip: 'Excluir time',
              icon: const Icon(Icons.delete_outline),
              onPressed: _loading ? null : _delete,
            ),
        ],
      ),
      children: [
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Nome do time'),
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                maxLength: 80,
                validator: (value) =>
                    Validators.name(value, message: 'Informe o nome do time'),
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _cityController,
                      decoration: const InputDecoration(
                        labelText: 'Cidade (opcional)',
                      ),
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _stateController,
                      decoration: const InputDecoration(labelText: 'UF'),
                      textCapitalization: TextCapitalization.characters,
                      textInputAction: TextInputAction.next,
                      maxLength: 2,
                      validator: Validators.optionalState,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Descrição (opcional)',
                ),
                textCapitalization: TextCapitalization.sentences,
                minLines: 2,
                maxLines: 4,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        LoadingButton(
          label: _isEditing ? 'Salvar' : 'Criar time',
          loading: _loading,
          onPressed: _save,
        ),
      ],
    );
  }
}
