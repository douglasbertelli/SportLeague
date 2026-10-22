import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/media/photo_picker.dart';
import '../../../core/media/picked_image.dart';
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
  late final Set<Modality> _modalities = {...?widget.team?.modalities};
  late TeamGender? _gender = widget.team?.gender;
  late AgeGroup _ageGroup = widget.team?.ageGroup ?? AgeGroup.open;
  late DateTime? _foundedOn = widget.team?.foundedOn;

  /// Logo escolhido e ainda não enviado.
  PickedImage? _newLogo;
  bool _removeLogo = false;

  /// Time já salvo: o recebido para edição ou o criado nesta tela (se o envio
  /// do logo falhar, salvar de novo atualiza em vez de criar outro time).
  late Team? _saved = widget.team;
  bool _showChoiceErrors = false;
  bool _loading = false;

  bool get _isEditing => widget.team != null;

  String? get _currentLogoUrl => _removeLogo ? null : _saved?.logoUrl;

  @override
  void dispose() {
    _nameController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickFoundedOn() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final date = await showDatePicker(
      context: context,
      initialDate: _foundedOn ?? today,
      firstDate: DateTime(1900),
      lastDate: today,
      helpText: 'Data de fundação',
    );
    if (date != null) setState(() => _foundedOn = date);
  }

  Future<void> _save() async {
    final fieldsValid = _formKey.currentState!.validate();
    setState(() => _showChoiceErrors = true);
    if (_loading || !fieldsValid || _modalities.isEmpty || _gender == null) {
      return;
    }
    final ownerId = ref.read(currentUserIdProvider);
    if (ownerId == null) return;

    final team = Team(
      id: _saved?.id,
      ownerId: ownerId,
      name: _nameController.text,
      sport: _saved?.sport ?? Sport.football,
      modalities: _modalities,
      gender: _gender,
      ageGroup: _ageGroup,
      foundedOn: _foundedOn,
      logoUrl: _currentLogoUrl,
      city: _cityController.text,
      state: _stateController.text,
      description: _descriptionController.text,
    );

    await _run(() async {
      final repository = ref.read(teamRepositoryProvider);
      final hadLogo = _saved?.logoUrl != null;
      if (_saved == null) {
        _saved = await repository.create(team);
        // O time recém-criado passa a ser o time ativo.
        await ref.read(selectedTeamIdProvider.notifier).select(_saved!.id!);
      } else {
        await repository.update(team);
        _saved = team;
      }

      if (_newLogo case final logo?) {
        final url = await repository.uploadLogo(_saved!, logo);
        _saved = _saved!.copyWith(logoUrl: url);
        await repository.update(_saved!);
        _newLogo = null;
      } else if (_removeLogo && hadLogo) {
        try {
          await repository.removeLogo(_saved!);
        } catch (_) {
          // O time já foi salvo sem logo; falhar aqui só deixa o arquivo
          // órfão no Storage.
        }
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
    await _run(() => ref.read(teamRepositoryProvider).delete(widget.team!));
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _loading = true);
    try {
      await action();
      ref.invalidate(myTeamsProvider);
      if (mounted) context.pop();
    } catch (error) {
      // Mesmo com erro, o time pode ter sido criado antes do logo.
      ref.invalidate(myTeamsProvider);
      if (mounted) showErrorSnackBar(context, friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final errorStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.error,
    );
    final foundedOn = _foundedOn;

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
        Center(
          child: PhotoPicker(
            noun: 'logo',
            image: _newLogo,
            url: _currentLogoUrl,
            placeholderIcon: Icons.shield_outlined,
            enabled: !_loading,
            onPicked: (image) => setState(() {
              _newLogo = image;
              _removeLogo = false;
            }),
            onRemoved: () => setState(() {
              _newLogo = null;
              _removeLogo = true;
            }),
          ),
        ),
        const SizedBox(height: 24),
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
              Text('Modalidade', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final modality in Modality.values)
                    FilterChip(
                      label: Text(modality.label),
                      selected: _modalities.contains(modality),
                      onSelected: (selected) => setState(
                        () => selected
                            ? _modalities.add(modality)
                            : _modalities.remove(modality),
                      ),
                    ),
                ],
              ),
              if (_showChoiceErrors && _modalities.isEmpty) ...[
                const SizedBox(height: 4),
                Text('Escolha pelo menos uma modalidade', style: errorStyle),
              ],
              const SizedBox(height: 16),
              Text('Gênero', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<TeamGender>(
                segments: [
                  for (final gender in TeamGender.values)
                    ButtonSegment(value: gender, label: Text(gender.label)),
                ],
                selected: {?_gender},
                emptySelectionAllowed: true,
                onSelectionChanged: (selection) =>
                    setState(() => _gender = selection.firstOrNull),
              ),
              if (_showChoiceErrors && _gender == null) ...[
                const SizedBox(height: 4),
                Text('Escolha o gênero', style: errorStyle),
              ],
              const SizedBox(height: 16),
              Text('Faixa de idade', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<AgeGroup>(
                segments: [
                  for (final group in AgeGroup.values)
                    ButtonSegment(value: group, label: Text(group.label)),
                ],
                selected: {_ageGroup},
                onSelectionChanged: (selection) =>
                    setState(() => _ageGroup = selection.first),
              ),
              const SizedBox(height: 4),
              Text(
                _ageGroup.description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: _pickFoundedOn,
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Data de fundação (opcional)',
                    suffixIcon: foundedOn == null
                        ? const Icon(Icons.event)
                        : IconButton(
                            tooltip: 'Limpar data de fundação',
                            icon: const Icon(Icons.close),
                            onPressed: () => setState(() => _foundedOn = null),
                          ),
                  ),
                  isEmpty: foundedOn == null,
                  child: Text(
                    foundedOn == null
                        ? ''
                        : MaterialLocalizations.of(context)
                              .formatMediumDate(foundedOn),
                  ),
                ),
              ),
              const SizedBox(height: 16),
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
