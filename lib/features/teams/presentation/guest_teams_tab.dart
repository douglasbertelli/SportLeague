import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/media/photo_picker.dart';
import '../../../core/media/picked_image.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/circle_image.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/empty_state.dart';
import '../../games/data/opponent_repository.dart';
import '../../games/domain/opponent.dart';
import 'team_logo.dart';

/// Aba Fictícios de Meus times: os adversários fora da plataforma que o
/// administrador criou, com o nome e o símbolo para editar.
class GuestTeamsTab extends ConsumerWidget {
  const GuestTeamsTab({super.key});

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    GuestTeam guest,
  ) async {
    final result = await showAppSheet<_GuestEdit>(
      context,
      builder: (_) => _EditGuestSheet(guest: guest),
    );
    if (result == null || !context.mounted) return;
    final repository = ref.read(opponentRepositoryProvider);
    try {
      if (result.name != guest.name) {
        await repository.renameGuest(guest.id!, result.name);
      }
      switch (result.logo) {
        case ImagePicked(:final image):
          await repository.setGuestLogo(guest.id!, image);
        case ImageRemoved():
          await repository.setGuestLogo(guest.id!, null);
        case null:
          break;
      }
      ref.invalidate(myGuestTeamsProvider);
    } catch (error) {
      ref.invalidate(myGuestTeamsProvider);
      if (context.mounted) {
        showErrorSnackBar(context, friendlyErrorMessage(error));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final guests = ref.watch(myGuestTeamsProvider);
    return guests.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => Center(
        child: TextButton.icon(
          onPressed: () => ref.invalidate(myGuestTeamsProvider),
          icon: const Icon(Icons.refresh),
          label: const Text('Erro ao carregar os fictícios. Tentar novamente'),
        ),
      ),
      data: (guests) => guests.isEmpty
          ? const EmptyState(
              icon: Icons.shield_outlined,
              title: 'Nenhum time fictício',
              message:
                  'Times fictícios são adversários que não estão no '
                  'SportLeague. Crie ao marcar um amistoso ou ao adicionar um '
                  'time num campeonato.',
            )
          : RefreshIndicator(
              onRefresh: () => ref.refresh(myGuestTeamsProvider.future),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  Text(
                    'Só você vê os seus times fictícios.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final guest in guests)
                    Card(
                      child: ListTile(
                        leading: TeamLogo.url(logoUrl: guest.logoUrl),
                        title: Text(guest.name),
                        subtitle: Text(guest.modality.label),
                        trailing: IconButton(
                          tooltip: 'Editar ${guest.name}',
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => _edit(context, ref, guest),
                        ),
                        onTap: () => _edit(context, ref, guest),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

/// O que mudou: o nome e, se mexeu no símbolo, a escolha (nova ou remover).
typedef _GuestEdit = ({String name, ImageChoice? logo});

class _EditGuestSheet extends ConsumerStatefulWidget {
  const _EditGuestSheet({required this.guest});

  final GuestTeam guest;

  @override
  ConsumerState<_EditGuestSheet> createState() => _EditGuestSheetState();
}

class _EditGuestSheetState extends ConsumerState<_EditGuestSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.guest.name);
  ImageChoice? _logo;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _hasLogo => switch (_logo) {
    ImagePicked() => true,
    ImageRemoved() => false,
    null => widget.guest.logoUrl != null,
  };

  Future<void> _chooseLogo() async {
    final choice = await chooseImage(
      context,
      ref,
      noun: 'símbolo',
      canRemove: _hasLogo,
      cropSquare: true,
    );
    if (choice != null && mounted) setState(() => _logo = choice);
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context)
        .pop<_GuestEdit>((name: _name.text.trim(), logo: _logo));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final ImageProvider? image = switch (_logo) {
      ImagePicked(:final PickedImage image) => MemoryImage(image.bytes),
      ImageRemoved() => null,
      null => switch (widget.guest.logoUrl) {
        final String url => NetworkImage(url),
        _ => null,
      },
    };
    return AppSheet(
      title: 'Editar time fictício',
      message: '${widget.guest.modality.label} · só você vê este time.',
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            Semantics(
              button: true,
              label: _hasLogo ? 'Trocar símbolo' : 'Adicionar símbolo',
              child: InkWell(
                onTap: _chooseLogo,
                customBorder: const CircleBorder(),
                // O símbolo inteiro, sem cortar no círculo (como o TeamLogo).
                child: CircleImage(
                  image: image,
                  radius: 40,
                  whole: true,
                  placeholder: Icon(
                    Icons.shield_outlined,
                    size: 36,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            TextButton(
              onPressed: _chooseLogo,
              child: Text(_hasLogo ? 'Trocar símbolo' : 'Adicionar símbolo'),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Nome do time',
                prefixIcon: Icon(Icons.shield_outlined),
              ),
              textCapitalization: TextCapitalization.words,
              maxLength: 80,
              onFieldSubmitted: (_) => _save(),
              validator: (value) =>
                  Validators.name(value, message: 'Informe o nome do time'),
            ),
            Text(
              'Os amistosos por jogar e os campeonatos passam a mostrar o '
              'nome novo.',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.check),
          label: const Text('Salvar'),
        ),
        const SheetBackButton(),
      ],
    );
  }
}
