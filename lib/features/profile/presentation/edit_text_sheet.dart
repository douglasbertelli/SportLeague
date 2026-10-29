import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/error_messages.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../data/profile_repository.dart';
import '../domain/profile.dart';

/// Troca o nome completo (Config) e salva; o perfil é recarregado.
Future<void> editFullName(
  BuildContext context,
  WidgetRef ref,
  Profile profile,
) async {
  final name = await _showEditTextSheet(
    context,
    title: 'Editar nome',
    label: 'Nome',
    initial: profile.fullName,
    maxLength: 120,
    emptyMessage: 'Informe o seu nome',
    capitalization: TextCapitalization.words,
  );
  if (name == null || name == profile.fullName) return;
  if (!context.mounted) return;
  await _save(
    context,
    ref,
    () => ref.read(profileRepositoryProvider).updateName(profile.id, name),
  );
}

/// Troca o apelido (Perfil do jogador) e salva; vazio tira o apelido, e o
/// perfil volta a mostrar o nome.
Future<void> editNickname(
  BuildContext context,
  WidgetRef ref,
  Profile profile,
) async {
  final nickname = await _showEditTextSheet(
    context,
    title: 'Editar apelido',
    label: 'Apelido',
    helper: 'É o nome mostrado no seu perfil. Em branco, mostra o nome.',
    initial: profile.nickname ?? '',
    maxLength: 40,
    capitalization: TextCapitalization.words,
  );
  if (nickname == null || nickname == (profile.nickname ?? '')) return;
  if (!context.mounted) return;
  await _save(
    context,
    ref,
    () => ref
        .read(profileRepositoryProvider)
        .updateNickname(profile.id, nickname),
  );
}

Future<void> _save(
  BuildContext context,
  WidgetRef ref,
  Future<void> Function() save,
) async {
  try {
    await save();
    ref.invalidate(currentProfileProvider);
  } catch (error) {
    if (context.mounted) {
      showErrorSnackBar(context, friendlyErrorMessage(error));
    }
  }
}

/// Folha com um campo de texto, acima do teclado; devolve o texto (sem os
/// espaços das pontas) no `pop`. Com [emptyMessage], o campo é obrigatório
/// (pelo menos 2 caracteres).
Future<String?> _showEditTextSheet(
  BuildContext context, {
  required String title,
  required String label,
  required String initial,
  required int maxLength,
  String? helper,
  String? emptyMessage,
  TextCapitalization capitalization = TextCapitalization.none,
}) => showModalBottomSheet<String>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) => _EditTextSheet(
    title: title,
    label: label,
    initial: initial,
    maxLength: maxLength,
    helper: helper,
    emptyMessage: emptyMessage,
    capitalization: capitalization,
  ),
);

class _EditTextSheet extends StatefulWidget {
  const _EditTextSheet({
    required this.title,
    required this.label,
    required this.initial,
    required this.maxLength,
    required this.helper,
    required this.emptyMessage,
    required this.capitalization,
  });

  final String title;
  final String label;
  final String initial;
  final int maxLength;
  final String? helper;
  final String? emptyMessage;
  final TextCapitalization capitalization;

  @override
  State<_EditTextSheet> createState() => _EditTextSheetState();
}

class _EditTextSheetState extends State<_EditTextSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final emptyMessage = widget.emptyMessage;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextFormField(
              controller: _controller,
              autofocus: true,
              maxLength: widget.maxLength,
              textCapitalization: widget.capitalization,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: widget.label,
                helperText: widget.helper,
                helperMaxLines: 2,
              ),
              onFieldSubmitted: (_) => _save(),
              validator: (value) =>
                  emptyMessage != null && (value ?? '').trim().length < 2
                  ? emptyMessage
                  : null,
            ),
            const SizedBox(height: 8),
            FilledButton(onPressed: _save, child: const Text('Salvar')),
          ],
        ),
      ),
    );
  }
}
