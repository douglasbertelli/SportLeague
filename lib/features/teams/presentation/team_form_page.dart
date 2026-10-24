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
import '../../../core/router/routes.dart';
import '../data/team_repository.dart';
import '../domain/team.dart';
import '../../venues/domain/venue.dart';

/// Etapas do cadastro do time, na ordem.
enum _Step {
  team('Time'),
  details('Detalhes'),
  contacts('Contato'),
  media('Mídia');

  const _Step(this.label);

  final String label;
}

/// Foto de uniforme: já salva ([url]) ou escolhida agora ([image]).
typedef _Kit = ({String? url, PickedImage? image});

/// Cria um time ou edita/exclui um existente ([team] preenchido), em abas:
/// time, detalhes, contato e mídia (capa e uniformes).
class TeamFormPage extends ConsumerStatefulWidget {
  const TeamFormPage({super.key, this.team});

  final Team? team;

  @override
  ConsumerState<TeamFormPage> createState() => _TeamFormPageState();
}

class _TeamFormPageState extends ConsumerState<TeamFormPage>
    with SingleTickerProviderStateMixin {
  final _formKeys = {
    for (final step in _Step.values) step: GlobalKey<FormState>(),
  };
  _Step _step = _Step.team;
  late final _tabs = TabController(length: _Step.values.length, vsync: this);

  late final _nameController = TextEditingController(text: widget.team?.name);
  late final _cityController = TextEditingController(text: widget.team?.city);
  late final _stateController = TextEditingController(text: widget.team?.state);
  late final _descriptionController = TextEditingController(
    text: widget.team?.description,
  );
  late final _phoneController = TextEditingController(text: widget.team?.phone);
  late final _instagramController = TextEditingController(
    text: widget.team?.instagram,
  );
  late final _facebookController = TextEditingController(
    text: widget.team?.facebook,
  );
  late final _youtubeController = TextEditingController(
    text: widget.team?.youtube,
  );
  late final _websiteController = TextEditingController(
    text: widget.team?.website,
  );

  /// Um time joga uma modalidade só. Times antigos com várias ficam com a
  /// primeira ao salvar.
  late Modality? _modality = widget.team?.modalities.firstOrNull;
  late TeamGender? _gender = widget.team?.gender;
  late AgeGroup _ageGroup = widget.team?.ageGroup ?? AgeGroup.open;
  late final _minAgeController = TextEditingController(
    text: (widget.team?.minAge ?? _ageGroup.defaultMin)?.toString(),
  );
  late final _maxAgeController = TextEditingController(
    text: (widget.team?.maxAge ?? _ageGroup.defaultMax)?.toString(),
  );
  late PlaysAs _playsAs = widget.team?.playsAs ?? PlaysAs.both;
  late DateTime? _foundedOn = widget.team?.foundedOn;
  late Venue? _homeVenue = widget.team?.homeVenue;

  /// Logo escolhido e ainda não enviado.
  PickedImage? _newLogo;
  bool _removeLogo = false;

  /// Capa escolhida e ainda não enviada.
  PickedImage? _newCover;
  bool _removeCover = false;

  /// Uniformes na ordem em que aparecem.
  late final List<_Kit> _kits = [
    for (final url in widget.team?.kitUrls ?? const <String>[])
      (url: url, image: null),
  ];

  /// Time já salvo: o recebido para edição ou o criado nesta tela (se o envio
  /// de uma imagem falhar, salvar de novo atualiza em vez de criar outro time).
  late Team? _saved = widget.team;
  bool _showChoiceErrors = false;
  bool _loading = false;

  bool get _isEditing => widget.team != null;

  String? get _currentLogoUrl => _removeLogo ? null : _saved?.logoUrl;
  String? get _currentCoverUrl => _removeCover ? null : _saved?.coverUrl;

  @override
  void dispose() {
    for (final controller in [
      _nameController,
      _cityController,
      _stateController,
      _descriptionController,
      _phoneController,
      _instagramController,
      _facebookController,
      _youtubeController,
      _websiteController,
      _minAgeController,
      _maxAgeController,
    ]) {
      controller.dispose();
    }
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _pickFoundedOn() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final date = await pickDateSheet(
      context,
      initialDate: _foundedOn ?? today,
      firstDate: DateTime(1900),
      lastDate: today,
      title: 'Data de fundação',
    );
    if (date != null) setState(() => _foundedOn = date);
  }

  /// Se a etapa está preenchida; mostra os erros dela.
  bool _validate(_Step step) {
    final fieldsValid = _formKeys[step]!.currentState!.validate();
    final choicesValid = switch (step) {
      _Step.team => _modality != null && _gender != null,
      _Step.details => _foundedOn != null,
      _ => true,
    };
    if (!choicesValid) setState(() => _showChoiceErrors = true);
    return fieldsValid && choicesValid;
  }

  /// Avança (conferindo as etapas anteriores) ou volta para [step].
  void _goTo(_Step step) {
    var target = step;
    if (step.index > _step.index) {
      for (final previous in _Step.values.take(step.index)) {
        if (!_validate(previous)) {
          target = previous;
          break;
        }
      }
    }
    setState(() => _step = target);
    // A aba tocada muda sozinha; volta para a etapa que vale.
    _tabs.animateTo(target.index);
  }

  Future<void> _pickHomeVenue() async {
    final venue = await context.push<Venue>(Routes.pickTeamVenue);
    if (venue != null) setState(() => _homeVenue = venue);
  }

  Future<void> _chooseCover() async {
    switch (await chooseImage(
      context,
      ref,
      noun: 'capa',
      canRemove: _newCover != null || _currentCoverUrl != null,
      maxSize: largeImageSize,
    )) {
      case ImagePicked(:final image):
        setState(() {
          _newCover = image;
          _removeCover = false;
        });
      case ImageRemoved():
        setState(() {
          _newCover = null;
          _removeCover = true;
        });
      case null:
        break;
    }
  }

  /// Escolhe uma foto nova ([index] nulo) ou troca/remove a do [index].
  Future<void> _chooseKit([int? index]) async {
    switch (await chooseImage(
      context,
      ref,
      noun: 'uniforme',
      canRemove: index != null,
      maxSize: largeImageSize,
    )) {
      case ImagePicked(:final image):
        setState(() {
          if (index == null) {
            _kits.add((url: null, image: image));
          } else {
            _kits[index] = (url: null, image: image);
          }
        });
      case ImageRemoved():
        setState(() => _kits.removeAt(index!));
      case null:
        break;
    }
  }

  Future<void> _save() async {
    if (_loading) return;
    for (final step in _Step.values) {
      if (!_validate(step)) {
        setState(() => _step = step);
        return;
      }
    }
    final ownerId = ref.read(currentUserIdProvider);
    if (ownerId == null) return;

    final team = Team(
      id: _saved?.id,
      ownerId: ownerId,
      name: _nameController.text,
      sport: _saved?.sport ?? Sport.football,
      modalities: {?_modality},
      gender: _gender,
      ageGroup: _ageGroup,
      minAge: int.tryParse(_minAgeController.text),
      maxAge: int.tryParse(_maxAgeController.text),
      foundedOn: _foundedOn,
      logoUrl: _currentLogoUrl,
      city: _cityController.text,
      state: _stateController.text,
      description: _descriptionController.text,
      playsAs: _playsAs,
      homeVenue: _homeVenue,
      phone: _phoneController.text,
      instagram: _instagramController.text,
      facebook: _facebookController.text,
      youtube: _youtubeController.text,
      website: _websiteController.text,
      coverUrl: _currentCoverUrl,
      // As fotos novas entram depois de enviadas.
      kitUrls: [for (final kit in _kits) ?kit.url],
    );

    await _run(() async {
      final repository = ref.read(teamRepositoryProvider);
      final previous = _saved;
      if (_saved == null) {
        _saved = await repository.create(team);
        // O time recém-criado passa a ser o time ativo.
        await ref.read(selectedTeamIdProvider.notifier).select(_saved!.id!);
      } else {
        await repository.update(team);
        _saved = team;
      }

      // Imagens: envia as novas e grava as URLs no time.
      var changed = false;
      if (_newLogo case final logo?) {
        _saved = _saved!.copyWith(
          logoUrl: await repository.uploadLogo(_saved!, logo),
        );
        _newLogo = null;
        changed = true;
      }
      if (_newCover case final cover?) {
        _saved = _saved!.copyWith(
          coverUrl: await repository.uploadCover(_saved!, cover),
        );
        _newCover = null;
        changed = true;
      }
      for (var i = 0; i < _kits.length; i++) {
        if (_kits[i].image case final image?) {
          _kits[i] = (
            url: await repository.uploadKit(_saved!, image),
            image: null,
          );
          changed = true;
        }
      }
      if (changed) {
        _saved = _saved!.copyWith(kitUrls: [for (final kit in _kits) kit.url!]);
        await repository.update(_saved!);
      }

      // Limpa do Storage o que saiu; falhar aqui só deixa arquivos órfãos.
      try {
        if (_removeLogo && previous?.logoUrl != null) {
          await repository.removeLogo(_saved!);
        }
        await repository.removeImages([
          if (_removeCover) ?previous?.coverUrl,
          for (final url in previous?.kitUrls ?? const <String>[])
            if (!_saved!.kitUrls.contains(url)) url,
        ]);
      } catch (_) {}
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
      // Mesmo com erro, o time pode ter sido criado antes das imagens.
      ref.invalidate(myTeamsProvider);
      if (mounted) showErrorSnackBar(context, friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _step == _Step.values.last;
    return FormPage(
      alignTop: true,
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
        bottom: TabBar(
          controller: _tabs,
          // Tocar numa aba à frente confere as etapas anteriores.
          onTap: (index) =>
              _loading ? _tabs.index = _step.index : _goTo(_Step.values[index]),
          tabs: [for (final step in _Step.values) Tab(text: step.label)],
        ),
      ),
      children: [
        // As etapas ficam montadas para guardar o que foi digitado e poder
        // conferir todas ao salvar.
        for (final step in _Step.values)
          Visibility(
            visible: step == _step,
            maintainState: true,
            child: Form(
              key: _formKeys[step],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: switch (step) {
                  _Step.team => _team(context),
                  _Step.details => _details(context),
                  _Step.contacts => _contacts(context),
                  _Step.media => _media(context),
                },
              ),
            ),
          ),
        const SizedBox(height: 24),
        Row(
          children: [
            if (_step.index > 0) ...[
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(88, 48),
                  ),
                  onPressed: _loading
                      ? null
                      : () => _goTo(_Step.values[_step.index - 1]),
                  child: const Text('Voltar'),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: isLast
                  ? LoadingButton(
                      label: _isEditing ? 'Salvar' : 'Criar time',
                      loading: _loading,
                      onPressed: _save,
                    )
                  : FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(88, 48),
                      ),
                      onPressed: _loading
                          ? null
                          : () => _goTo(_Step.values[_step.index + 1]),
                      child: const Text('Próximo'),
                    ),
            ),
          ],
        ),
        // Na edição dá para salvar de qualquer etapa.
        if (_isEditing && !isLast) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _loading ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Salvar'),
          ),
        ],
      ],
    );
  }

  List<Widget> _team(BuildContext context) {
    final theme = Theme.of(context);
    final errorStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.error,
    );
    final mutedStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return [
      Center(
        child: PhotoPicker(
          noun: 'logo',
          image: _newLogo,
          url: _currentLogoUrl,
          placeholderIcon: Icons.shield_outlined,
          cropSquare: true,
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
            ChoiceChip(
              label: Text(modality.label),
              selected: _modality == modality,
              onSelected: (_) => setState(() => _modality = modality),
            ),
        ],
      ),
      if (_showChoiceErrors && _modality == null) ...[
        const SizedBox(height: 4),
        Text('Escolha a modalidade', style: errorStyle),
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
        onSelectionChanged: (selection) => _selectAgeGroup(selection.first),
      ),
      if (_ageGroup.hasMinAge) ...[
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _AgeField(
                controller: _minAgeController,
                label: 'Idade mínima',
                validator: _validateMinAge,
                // Atualiza o texto da faixa ("13 a 15 anos").
                onChanged: (_) => setState(() {}),
              ),
            ),
            if (_ageGroup.hasMaxAge) ...[
              const SizedBox(width: 12),
              Expanded(
                child: _AgeField(
                  controller: _maxAgeController,
                  label: 'Idade máxima',
                  validator: _validateMaxAge,
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ],
        ),
      ],
      const SizedBox(height: 4),
      Text(
        _ageGroup.describe(
          minAge: int.tryParse(_minAgeController.text),
          maxAge: int.tryParse(_maxAgeController.text),
        ),
        style: mutedStyle,
      ),
    ];
  }

  /// Ao trocar de faixa, os campos de idade vêm com os valores sugeridos.
  void _selectAgeGroup(AgeGroup group) {
    if (group == _ageGroup) return;
    setState(() {
      _ageGroup = group;
      _minAgeController.text = group.defaultMin?.toString() ?? '';
      _maxAgeController.text = group.defaultMax?.toString() ?? '';
    });
  }

  String? _validateMinAge(String? value) {
    final age = int.tryParse(value ?? '');
    if (age == null) return 'Informe a idade';
    final (min, max) = (_ageGroup.minAllowed!, _ageGroup.maxAllowed!);
    if (age < min || age > max) return 'Entre $min e $max';
    return null;
  }

  String? _validateMaxAge(String? value) {
    final age = int.tryParse(value ?? '');
    if (age == null) return 'Informe a idade';
    final min = int.tryParse(_minAgeController.text) ?? _ageGroup.minAllowed!;
    final max = _ageGroup.maxAllowed!;
    if (age < min || age > max) return 'Entre $min e $max';
    return null;
  }

  List<Widget> _details(BuildContext context) {
    final theme = Theme.of(context);
    final mutedStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final foundedOn = _foundedOn;

    return [
      Text('Joga como', style: theme.textTheme.titleSmall),
      const SizedBox(height: 8),
      SegmentedButton<PlaysAs>(
        segments: [
          for (final playsAs in PlaysAs.values)
            ButtonSegment(value: playsAs, label: Text(playsAs.label)),
        ],
        selected: {_playsAs},
        onSelectionChanged: (selection) =>
            setState(() => _playsAs = selection.first),
      ),
      const SizedBox(height: 4),
      Text(_playsAs.description, style: mutedStyle),
      const SizedBox(height: 24),
      InkWell(
        onTap: _loading ? null : _pickHomeVenue,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: 'Local do time (opcional)',
            helperText:
                _homeVenue?.address ??
                'Vem preenchido nos amistosos em que o time é mandante',
            helperMaxLines: 2,
            suffixIcon: _homeVenue == null
                ? const Icon(Icons.place_outlined)
                : IconButton(
                    tooltip: 'Remover local do time',
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _homeVenue = null),
                  ),
          ),
          isEmpty: _homeVenue == null,
          child: Text(_homeVenue?.name ?? ''),
        ),
      ),
      const SizedBox(height: 24),
      InkWell(
        onTap: _pickFoundedOn,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: 'Data de fundação',
            suffixIcon: const Icon(Icons.event),
            errorText: _showChoiceErrors && foundedOn == null
                ? 'Informe a data de fundação'
                : null,
          ),
          isEmpty: foundedOn == null,
          child: Text(
            foundedOn == null
                ? ''
                : MaterialLocalizations.of(context).formatMediumDate(foundedOn),
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
              decoration: const InputDecoration(labelText: 'Cidade'),
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              validator: (value) =>
                  Validators.required(value, message: 'Informe a cidade'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              controller: _stateController,
              decoration: const InputDecoration(
                labelText: 'UF',
                counterText: '',
              ),
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.next,
              maxLength: 2,
              validator: Validators.state,
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _descriptionController,
        decoration: const InputDecoration(labelText: 'Descrição (opcional)'),
        textCapitalization: TextCapitalization.sentences,
        minLines: 2,
        maxLines: 4,
      ),
    ];
  }

  List<Widget> _contacts(BuildContext context) {
    final theme = Theme.of(context);
    return [
      Text(
        'Opcional: ajuda os adversários a falar com o time.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _phoneController,
        decoration: const InputDecoration(
          labelText: 'Telefone / WhatsApp',
          hintText: 'DDD + número',
          prefixIcon: Icon(Icons.phone_outlined),
        ),
        keyboardType: TextInputType.phone,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        maxLength: 11,
        textInputAction: TextInputAction.next,
        validator: Validators.optionalPhone,
      ),
      const SizedBox(height: 8),
      TextFormField(
        controller: _instagramController,
        decoration: const InputDecoration(
          labelText: 'Instagram',
          prefixText: '@',
          prefixIcon: Icon(Icons.camera_alt_outlined),
        ),
        textInputAction: TextInputAction.next,
        maxLength: 100,
        validator: Validators.optionalHandle,
      ),
      const SizedBox(height: 8),
      TextFormField(
        controller: _facebookController,
        decoration: const InputDecoration(
          labelText: 'Facebook',
          hintText: 'Endereço ou nome da página',
          prefixIcon: Icon(Icons.facebook),
        ),
        keyboardType: TextInputType.url,
        textInputAction: TextInputAction.next,
        maxLength: 200,
      ),
      const SizedBox(height: 8),
      TextFormField(
        controller: _youtubeController,
        decoration: const InputDecoration(
          labelText: 'YouTube',
          hintText: 'Endereço ou nome do canal',
          prefixIcon: Icon(Icons.smart_display_outlined),
        ),
        keyboardType: TextInputType.url,
        textInputAction: TextInputAction.next,
        maxLength: 200,
      ),
      const SizedBox(height: 8),
      TextFormField(
        controller: _websiteController,
        decoration: const InputDecoration(
          labelText: 'Site',
          hintText: 'www.seutime.com.br',
          prefixIcon: Icon(Icons.language),
        ),
        keyboardType: TextInputType.url,
        maxLength: 200,
        validator: Validators.optionalWebsite,
      ),
    ];
  }

  List<Widget> _media(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final mutedStyle = theme.textTheme.bodyMedium?.copyWith(
      color: colors.onSurfaceVariant,
    );
    final ImageProvider? cover = switch ((_newCover, _currentCoverUrl)) {
      (final image?, _) => MemoryImage(image.bytes),
      (null, final url?) => NetworkImage(url),
      _ => null,
    };

    return [
      Text('Capa', style: theme.textTheme.titleSmall),
      const SizedBox(height: 4),
      Text('Uma foto do time para o perfil.', style: mutedStyle),
      const SizedBox(height: 8),
      _ImageTile(
        aspectRatio: 16 / 9,
        image: cover,
        label: cover == null ? 'Adicionar capa' : 'Trocar capa',
        icon: Icons.add_photo_alternate_outlined,
        onTap: _loading ? null : _chooseCover,
      ),
      const SizedBox(height: 24),
      Text('Uniformes', style: theme.textTheme.titleSmall),
      const SizedBox(height: 4),
      Text(
        'Até $maxKits fotos das camisas, para o adversário saber as cores e '
        'não confundir na hora do jogo.',
        style: mutedStyle,
      ),
      const SizedBox(height: 8),
      GridView.count(
        crossAxisCount: maxKits,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 3 / 4,
        children: [
          for (final (index, kit) in _kits.indexed)
            _ImageTile(
              image: switch (kit) {
                (url: _, image: final image?) => MemoryImage(image.bytes),
                (url: final url?, image: null) => NetworkImage(url),
                _ => null,
              },
              label: 'Uniforme ${index + 1}',
              icon: Icons.checkroom,
              onTap: _loading ? null : () => _chooseKit(index),
            ),
          if (_kits.length < maxKits)
            _ImageTile(
              label: 'Adicionar uniforme',
              icon: Icons.add,
              onTap: _loading ? null : _chooseKit,
            ),
        ],
      ),
    ];
  }
}

/// Campo de idade em anos (só números).
class _AgeField extends StatelessWidget {
  const _AgeField({
    required this.controller,
    required this.label,
    required this.validator,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final FormFieldValidator<String> validator;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        suffixText: 'anos',
        counterText: '',
      ),
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      maxLength: 2,
      validator: validator,
      onChanged: onChanged,
    );
  }
}

/// Imagem retangular tocável; sem imagem mostra o [icon] e o [label].
class _ImageTile extends StatelessWidget {
  const _ImageTile({
    required this.label,
    required this.icon,
    required this.onTap,
    this.image,
    this.aspectRatio,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final ImageProvider? image;
  final double? aspectRatio;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final image = this.image;
    final tile = Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (image == null)
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: colors.onSurfaceVariant),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  ),
                ],
              )
            else
              Image(
                image: image,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Icon(
                  Icons.broken_image_outlined,
                  color: colors.onSurfaceVariant,
                ),
              ),
            Material(
              type: MaterialType.transparency,
              child: InkWell(onTap: onTap),
            ),
          ],
        ),
      ),
    );
    return switch (aspectRatio) {
      final ratio? => AspectRatio(aspectRatio: ratio, child: tile),
      null => tile,
    };
  }
}
