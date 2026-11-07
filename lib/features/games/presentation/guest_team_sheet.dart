import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/media/photo_picker.dart';
import '../../../core/media/picked_image.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_sheet.dart';
import '../data/opponent_repository.dart';
import '../domain/opponent.dart';

/// O que o administrador preencheu ao criar o time fictício.
typedef GuestTeamDraft = ({String name, PickedImage? logo});

/// Cria um time fictício: o símbolo (opcional, recortado em quadrado) e o
/// nome. Fecha devolvendo o [GuestTeamDraft].
class GuestTeamSheet extends ConsumerStatefulWidget {
  const GuestTeamSheet({
    super.key,
    required this.initialName,
    required this.message,
    required this.submitLabel,
    this.submitIcon = Icons.add,
  });

  final String initialName;
  final String message;
  final String submitLabel;
  final IconData submitIcon;

  @override
  ConsumerState<GuestTeamSheet> createState() => _GuestTeamSheetState();
}

class _GuestTeamSheetState extends ConsumerState<GuestTeamSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initialName);
  PickedImage? _logo;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _chooseLogo() async {
    final choice = await chooseImage(
      context,
      ref,
      noun: 'símbolo',
      canRemove: _logo != null,
      cropSquare: true,
    );
    if (choice == null || !mounted) return;
    setState(
      () => _logo = switch (choice) {
        ImagePicked(:final image) => image,
        ImageRemoved() => null,
      },
    );
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.of(context)
          .pop<GuestTeamDraft>((name: _name.text.trim(), logo: _logo));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final logo = _logo;
    return AppSheet(
      title: 'Criar time fictício',
      message: widget.message,
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            Semantics(
              button: true,
              label: logo == null ? 'Adicionar símbolo' : 'Trocar símbolo',
              child: InkWell(
                onTap: _chooseLogo,
                customBorder: const CircleBorder(),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CircleAvatar(
                      radius: 40,
                      backgroundColor: colors.surfaceContainerHighest,
                      foregroundImage: logo == null
                          ? null
                          : MemoryImage(logo.bytes),
                      // Imagem que não abre: fica o escudo.
                      onForegroundImageError: logo == null ? null : (_, _) {},
                      child: Icon(
                        Icons.shield_outlined,
                        size: 36,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: CircleAvatar(
                        radius: 15,
                        backgroundColor: colors.primary,
                        child: Icon(
                          logo == null
                              ? Icons.add_a_photo_outlined
                              : Icons.edit,
                          size: 16,
                          color: colors.onPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: _chooseLogo,
              child: Text(
                logo == null
                    ? 'Adicionar símbolo (opcional)'
                    : 'Trocar símbolo',
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _name,
              autofocus: widget.initialName.isEmpty,
              decoration: const InputDecoration(
                labelText: 'Nome do time',
                prefixIcon: Icon(Icons.shield_outlined),
              ),
              textCapitalization: TextCapitalization.words,
              maxLength: 80,
              onFieldSubmitted: (_) => _submit(),
              validator: (value) =>
                  Validators.name(value, message: 'Informe o nome do time'),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton.icon(
          onPressed: _submit,
          icon: Icon(widget.submitIcon),
          label: Text(widget.submitLabel),
        ),
        const SheetBackButton(),
      ],
    );
  }
}

/// Cria o time fictício e, se veio, envia o símbolo. Se só o símbolo falhar,
/// o time continua criado: avisa por [onLogoError].
Future<GuestTeam> createGuestTeam(
  OpponentRepository repository,
  GuestTeam guest,
  PickedImage? logo, {
  required VoidCallback onLogoError,
}) async {
  final created = await repository.createGuest(guest);
  if (logo != null) {
    try {
      await repository.setGuestLogo(created.id!, logo);
    } catch (_) {
      onLogoError();
    }
  }
  return created;
}
