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
import '../../address/data/zip_code_service.dart';
import '../../teams/data/team_repository.dart';
import '../../teams/domain/team.dart';
import '../data/venue_repository.dart';
import '../domain/venue.dart';
import 'venue_photo.dart';

/// O que a rota do cadastro de local recebe em `extra`.
typedef NewVenueArgs = ({String name, bool offerTeamLink});

/// Cadastra um local ou edita um que o usuário cadastrou. Antes de cadastrar,
/// sugere os locais parecidos que já existem. Fecha devolvendo o [Venue]
/// salvo ou o existente escolhido.
class VenueFormPage extends ConsumerStatefulWidget {
  const VenueFormPage({
    super.key,
    this.venue,
    this.initialName,
    this.offerTeamLink = true,
  });

  final Venue? venue;

  /// Nome digitado na pesquisa, para não precisar digitar de novo.
  final String? initialName;

  /// Mostra "Local do time" no cadastro.
  final bool offerTeamLink;

  @override
  ConsumerState<VenueFormPage> createState() => _VenueFormPageState();
}

class _VenueFormPageState extends ConsumerState<VenueFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(
    text: widget.venue?.name ?? widget.initialName,
  );
  late final _zipCodeController = TextEditingController(
    text: widget.venue?.zipCode,
  );
  late final _streetController = TextEditingController(
    text: widget.venue?.street,
  );
  late final _numberController = TextEditingController(
    text: widget.venue?.number,
  );
  late final _complementController = TextEditingController(
    text: widget.venue?.complement,
  );
  late final _neighborhoodController = TextEditingController(
    text: widget.venue?.neighborhood,
  );
  late final _cityController = TextEditingController(text: widget.venue?.city);
  late final _stateController = TextEditingController(
    text: widget.venue?.state,
  );
  final _numberFocus = FocusNode();

  /// Último estado salvo (para reenviar só a foto se ela falhar).
  late Venue? _saved = widget.venue;
  PickedImage? _newPhoto;
  bool _removePhoto = false;
  bool _loading = false;
  bool _searchingZipCode = false;

  /// Escolha do usuário em "Local do time"; nulo segue o padrão.
  bool? _linkTeamChoice;

  bool get _isEditing => widget.venue != null;

  @override
  void dispose() {
    _nameController.dispose();
    _zipCodeController.dispose();
    _streetController.dispose();
    _numberController.dispose();
    _complementController.dispose();
    _neighborhoodController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _numberFocus.dispose();
    super.dispose();
  }

  Future<void> _lookupZipCode(String value) async {
    if (value.length != 8) return;
    setState(() => _searchingZipCode = true);
    try {
      final result = await ref.read(zipCodeServiceProvider).lookup(value);
      if (!mounted) return;
      if (result == null) {
        showErrorSnackBar(
          context,
          'CEP não encontrado. Preencha o endereço manualmente.',
        );
        return;
      }
      _streetController.text = result.street;
      _neighborhoodController.text = result.neighborhood;
      _cityController.text = result.city;
      _stateController.text = result.state;
      _numberFocus.requestFocus();
    } catch (_) {
      if (mounted) {
        showErrorSnackBar(
          context,
          'Não foi possível consultar o CEP. Preencha manualmente.',
        );
      }
    } finally {
      if (mounted) setState(() => _searchingZipCode = false);
    }
  }

  Future<void> _save() async {
    if (_loading || !_formKey.currentState!.validate()) return;
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;

    final venue = Venue(
      id: _saved?.id,
      createdBy: _saved?.createdBy ?? userId,
      name: _nameController.text,
      zipCode: _zipCodeController.text,
      street: _streetController.text,
      number: _numberController.text,
      complement: _complementController.text,
      neighborhood: _neighborhoodController.text,
      city: _cityController.text,
      state: _stateController.text.trim().toUpperCase(),
      photoUrl: _removePhoto ? null : _saved?.photoUrl,
    );
    final repository = ref.read(venueRepositoryProvider);

    setState(() => _loading = true);
    try {
      // Antes de cadastrar, sugere o local que talvez já exista.
      if (_saved == null) {
        final similar = await repository.findSimilar(venue);
        if (!mounted) return;
        if (similar.isNotEmpty) {
          // O botão não fica carregando enquanto o usuário decide.
          setState(() => _loading = false);
          final choice = await showAppSheet<_SimilarChoice>(
            context,
            builder: (_) => _SimilarVenuesSheet(venues: similar),
          );
          if (!mounted) return;
          switch (choice) {
            case null:
              return;
            case _UseExisting(:final venue):
              await _linkToTeam(venue);
              if (mounted) context.pop(venue);
              return;
            case _CreateAnyway():
              setState(() => _loading = true);
          }
        }
      }

      final hadPhoto = _saved?.photoUrl != null;
      if (_saved == null) {
        _saved = await repository.create(venue);
      } else {
        await repository.update(venue);
        _saved = venue;
      }

      if (_newPhoto case final photo?) {
        final url = await repository.uploadPhoto(_saved!, photo);
        _saved = _saved!.copyWith(photoUrl: url);
        await repository.update(_saved!);
        _newPhoto = null;
      } else if (_removePhoto && hadPhoto) {
        try {
          await repository.removePhoto(_saved!);
        } catch (_) {
          // O local já foi salvo sem foto; falhar aqui só deixa o arquivo
          // órfão no Storage.
        }
      }
      if (!_isEditing) await _linkToTeam(_saved!);
      if (mounted) context.pop(_saved);
    } catch (error) {
      if (mounted) showErrorSnackBar(context, friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Com a opção marcada, o local passa a ser o do time ativo e vem
  /// preenchido nos próximos amistosos.
  Future<void> _linkToTeam(Venue venue) async {
    final team = ref.read(selectedTeamProvider).value;
    if (!widget.offerTeamLink || team == null || !_linkTeam(team)) return;
    await ref
        .read(teamRepositoryProvider)
        .update(team.copyWith(homeVenue: venue));
    ref.invalidate(myTeamsProvider);
  }

  /// Marcado por padrão quando o time ainda não tem local.
  bool _linkTeam(Team team) => _linkTeamChoice ?? team.homeVenue == null;

  Future<void> _delete() async {
    final venue = widget.venue!;
    final confirmed = await confirmDelete(
      context,
      title: 'Excluir local?',
      message:
          '${venue.name} será excluído. Os amistosos marcados nele ficam sem '
          'local.',
    );
    if (!confirmed) return;
    setState(() => _loading = true);
    try {
      await ref.read(venueRepositoryProvider).delete(venue);
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
        title: Text(_isEditing ? 'Editar local' : 'Novo local'),
        actions: [
          if (_isEditing)
            IconButton(
              tooltip: 'Excluir local',
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
            placeholderIcon: Icons.place_outlined,
            maxSize: largeImageSize,
            enabled: !_loading,
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
        const SizedBox(height: 8),
        Text(
          'Uma foto da fachada ou da quadra ajuda a encontrar o local.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 24),
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Nome do local',
                  hintText: 'Arena, quadra, campo…',
                ),
                textCapitalization: TextCapitalization.words,
                maxLength: 120,
                validator: (value) =>
                    Validators.name(value, message: 'Informe o nome do local'),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _zipCodeController,
                decoration: InputDecoration(
                  labelText: 'CEP',
                  counterText: '',
                  suffixIcon: _searchingZipCode
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 8,
                onChanged: _lookupZipCode,
                validator: Validators.zipCode,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _streetController,
                decoration: const InputDecoration(labelText: 'Rua'),
                textCapitalization: TextCapitalization.words,
                validator: Validators.required,
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _numberController,
                      focusNode: _numberFocus,
                      decoration: const InputDecoration(labelText: 'Número'),
                      validator: Validators.required,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _complementController,
                      decoration: const InputDecoration(
                        labelText: 'Complemento (opcional)',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _neighborhoodController,
                decoration: const InputDecoration(labelText: 'Bairro'),
                textCapitalization: TextCapitalization.words,
                validator: Validators.required,
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
                      validator: Validators.required,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _stateController,
                      decoration: const InputDecoration(
                        labelText: 'UF',
                        counterText: '',
                      ),
                      textCapitalization: TextCapitalization.characters,
                      maxLength: 2,
                      validator: Validators.state,
                    ),
                  ),
                ],
              ),
              // Só no cadastro: o local passa a ser o do time ativo.
              if (!_isEditing && widget.offerTeamLink)
                if (ref.watch(selectedTeamProvider).value case final team?)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _linkTeam(team),
                    onChanged: _loading
                        ? null
                        : (value) => setState(() => _linkTeamChoice = value),
                    title: Text('Local do ${team.name}'),
                    subtitle: Text(
                      team.homeVenue == null
                          ? 'Vem preenchido ao marcar amistoso como mandante'
                          : 'Substitui ${team.homeVenue!.name}',
                    ),
                  ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        LoadingButton(
          label: _isEditing ? 'Salvar' : 'Cadastrar local',
          loading: _loading,
          onPressed: _save,
        ),
      ],
    );
  }
}

/// Resposta da sugestão de local existente.
sealed class _SimilarChoice {
  const _SimilarChoice();
}

class _UseExisting extends _SimilarChoice {
  const _UseExisting(this.venue);

  final Venue venue;
}

class _CreateAnyway extends _SimilarChoice {
  const _CreateAnyway();
}

/// "Esse local já existe?": lista os parecidos para usar um deles ou cadastrar
/// mesmo assim.
class _SimilarVenuesSheet extends StatelessWidget {
  const _SimilarVenuesSheet({required this.venues});

  final List<Venue> venues;

  @override
  Widget build(BuildContext context) {
    return AppSheet(
      title: 'Esse local já existe?',
      message:
          'Encontramos locais parecidos. Toque em um para usá-lo em vez de '
          'cadastrar outro.',
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final venue in venues)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: VenuePhoto(venue: venue),
              title: Text(venue.name),
              subtitle: Text(venue.address),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).pop(_UseExisting(venue)),
            ),
        ],
      ),
      actions: [
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).pop(const _CreateAnyway()),
          icon: const Icon(Icons.add_location_alt_outlined),
          label: const Text('Cadastrar mesmo assim'),
        ),
        const SheetBackButton(label: 'Voltar'),
      ],
    );
  }
}
