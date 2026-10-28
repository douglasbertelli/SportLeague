import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/media/photo_picker.dart';
import '../../../core/media/picked_image.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_sheet.dart';
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

  /// Foto escolhida e ainda não enviada.
  PickedImage? _newPhoto;
  bool _removePhoto = false;

  /// Atleta já salvo: o recebido para edição ou o criado nesta tela (se o
  /// envio da foto falhar, salvar de novo atualiza em vez de duplicar).
  late Athlete? _saved = widget.athlete;
  bool _photoMissing = false;

  /// Tentou salvar sem a posição (obrigatória).
  bool _positionMissing = false;
  bool _loading = false;

  bool get _isEditing => widget.athlete != null;

  /// A foto do perfil do jogador vinculado também vale (quem entrou pelo
  /// convite não tem foto de atleta).
  bool get _hasPhoto =>
      _newPhoto != null ||
      (!_removePhoto &&
          (_saved?.photoPath != null || _saved?.profilePhotoUrl != null));

  @override
  void dispose() {
    _nameController.dispose();
    _numberController.dispose();
    super.dispose();
  }

  /// Escolha da posição num bottom sheet; "Sem posição" limpa.
  Future<void> _pickPosition(List<String> positions) async {
    final choice = await showAppSheet<({String? position})>(
      context,
      builder: (context) => AppSheet(
        title: 'Posição',
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final position in [...positions, null])
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  position == null
                      ? Icons.remove_circle_outline
                      : Icons.sports_soccer,
                ),
                title: Text(position ?? 'Sem posição'),
                trailing: position == _position
                    ? const Icon(Icons.check)
                    : null,
                selected: position == _position,
                onTap: () => Navigator.of(context).pop((position: position)),
              ),
          ],
        ),
        actions: const [SheetBackButton()],
      ),
    );
    if (choice != null) setState(() => _position = choice.position);
  }

  /// Números dos outros atletas do time (atualizado a cada build).
  Map<int, String> _takenNumbers = const {};

  Future<void> _save() async {
    final fieldsValid = _formKey.currentState!.validate();
    // Número repetido: o campo só diz "Já usado"; o nome vem no aviso.
    if (_takenNumbers[int.tryParse(_numberController.text)] case final name?) {
      showErrorSnackBar(context, 'Número já usado por $name');
    }
    setState(() {
      _photoMissing = !_hasPhoto;
      _positionMissing = _position == null;
    });
    if (_loading || !fieldsValid || !_hasPhoto || _position == null) return;
    final teamId =
        widget.athlete?.teamId ?? ref.read(selectedTeamProvider).value?.id;
    final ownerId = ref.read(currentUserIdProvider);
    if (teamId == null || ownerId == null) return;

    final athlete = Athlete(
      id: _saved?.id,
      teamId: teamId,
      name: _nameController.text,
      position: _position,
      jerseyNumber: int.tryParse(_numberController.text),
      profileId: _saved?.profileId,
      photoPath: _removePhoto ? null : _saved?.photoPath,
      profilePhotoUrl: _saved?.profilePhotoUrl,
    );
    final repository = ref.read(athleteRepositoryProvider);
    await _run(teamId, () async {
      final previousPhoto = _saved?.photoPath;
      if (_saved == null) {
        _saved = await repository.create(athlete);
      } else {
        await repository.update(athlete);
        _saved = athlete;
      }

      if (_newPhoto case final photo?) {
        final path = await repository.uploadPhoto(
          ownerId: ownerId,
          athlete: _saved!,
          image: photo,
        );
        _saved = _saved!.copyWith(photoPath: path);
        await repository.update(_saved!);
        _newPhoto = null;
      } else if (_removePhoto && previousPhoto != null) {
        try {
          await repository.removePhoto(previousPhoto);
        } catch (_) {
          // O atleta já foi salvo sem foto; falhar aqui só deixa o arquivo
          // órfão no Storage.
        }
      }
    });
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
      () => ref.read(athleteRepositoryProvider).delete(athlete),
    );
  }

  Future<void> _run(String teamId, Future<void> Function() action) async {
    setState(() => _loading = true);
    try {
      await action();
      ref.invalidate(teamAthletesProvider(teamId));
      if (mounted) context.pop();
    } catch (error) {
      // Mesmo com erro, o atleta pode ter sido criado antes da foto.
      ref.invalidate(teamAthletesProvider(teamId));
      if (mounted) showErrorSnackBar(context, friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final teamName = ref.watch(selectedTeamProvider).value?.name;
    final teamId =
        widget.athlete?.teamId ?? ref.watch(selectedTeamProvider).value?.id;
    // Números já usados por outros atletas do time: não pode repetir.
    final takenNumbers = _takenNumbers = {
      for (final other
          in (teamId == null
                  ? null
                  : ref.watch(teamAthletesProvider(teamId)).value) ??
              const <Athlete>[])
        if (other.id != _saved?.id && other.jerseyNumber != null)
          other.jerseyNumber!: other.name,
    };
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
        Center(
          child: PhotoPicker(
            noun: 'foto',
            image: _newPhoto,
            url: _removePhoto ? null : _saved?.photoUrl,
            placeholderIcon: Icons.person_outline,
            enabled: !_loading,
            errorText: _photoMissing && !_hasPhoto
                ? 'Adicione a foto do atleta'
                : null,
            onPicked: (image) => setState(() {
              _newPhoto = image;
              _removePhoto = false;
            }),
            onRemoved: () => setState(() {
              _newPhoto = null;
              _removePhoto = true;
            }),
          ),
        ),
        const SizedBox(height: 24),
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
                    child: InkWell(
                      onTap: _loading ? null : () => _pickPosition(positions),
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Posição',
                          suffixIcon: const Icon(Icons.expand_more),
                          errorText: _positionMissing && _position == null
                              ? 'Escolha a posição'
                              : null,
                        ),
                        isEmpty: _position == null,
                        child: Text(_position ?? ''),
                      ),
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
                      validator: (value) =>
                          switch (takenNumbers[int.tryParse(value ?? '')]) {
                            // A mensagem inteira vai no aviso ao salvar.
                            _? => 'Já usado',
                            null => null,
                          },
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
