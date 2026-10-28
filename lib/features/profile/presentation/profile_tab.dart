import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/media/photo_picker.dart';
import '../../../core/router/routes.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../data/profile_repository.dart';
import '../domain/profile.dart';

/// Aba Perfil: a foto, o nome e, do jogador, os dados de atleta. O resto
/// (Meu código, cor do time, endereço e Sair) fica na aba Config.
class ProfileTab extends ConsumerWidget {
  const ProfileTab({super.key, required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(child: _Avatar(profile: profile)),
        const SizedBox(height: 12),
        if (profile.isPlayer)
          // O jogador troca o próprio nome pelo lápis.
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(width: 48),
              Flexible(
                child: Text(
                  profile.fullName,
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
              ),
              IconButton(
                tooltip: 'Editar nome',
                icon: const Icon(Icons.edit_outlined, size: 20),
                onPressed: () => _editName(context, ref, profile),
              ),
            ],
          )
        else
          Text(
            profile.fullName,
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
        const SizedBox(height: 24),
        if (profile.isPlayer) _AthleteDataCard(profile: profile),
      ],
    );
  }
}

/// Abre a troca do nome e salva; o perfil é recarregado com o nome novo.
Future<void> _editName(
  BuildContext context,
  WidgetRef ref,
  Profile profile,
) async {
  final name = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _EditNameSheet(initial: profile.fullName),
  );
  if (name == null || name == profile.fullName) return;
  try {
    await ref.read(profileRepositoryProvider).updateName(profile.id, name);
    ref.invalidate(currentProfileProvider);
  } catch (error) {
    if (context.mounted) {
      showErrorSnackBar(context, friendlyErrorMessage(error));
    }
  }
}

/// Campo do nome, acima do teclado; devolve o nome no `pop`.
class _EditNameSheet extends StatefulWidget {
  const _EditNameSheet({required this.initial});

  final String initial;

  @override
  State<_EditNameSheet> createState() => _EditNameSheetState();
}

class _EditNameSheetState extends State<_EditNameSheet> {
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
            Text('Editar nome', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextFormField(
              controller: _controller,
              autofocus: true,
              maxLength: 120,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(labelText: 'Nome'),
              onFieldSubmitted: (_) => _save(),
              validator: (value) => (value ?? '').trim().length < 2
                  ? 'Informe o seu nome'
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

/// Dados de atleta do jogador, um por linha, com o Editar. O que não foi
/// preenchido aparece como "Não informado".
class _AthleteDataCard extends StatelessWidget {
  const _AthleteDataCard({required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final birthDate = profile.birthDate;
    final rows = [
      (Icons.sports_soccer, 'Posição', profile.preferredPosition),
      (
        Icons.directions_walk,
        'Pé dominante',
        switch (profile.preferredFoot) {
          null => null,
          PreferredFoot.both => 'Ambidestro',
          final foot => foot.label,
        },
      ),
      (
        Icons.height,
        'Altura',
        switch (profile.heightCm) {
          final height? =>
            '${(height / 100).toStringAsFixed(2).replaceAll('.', ',')} m',
          null => null,
        },
      ),
      (
        Icons.cake_outlined,
        'Nascimento',
        switch (birthDate) {
          final date? =>
            '${MaterialLocalizations.of(context).formatCompactDate(date)}'
                '${profile.age() == null ? '' : ' · ${profile.age()} anos'}',
          null => null,
        },
      ),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Dados de atleta',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                TextButton.icon(
                  onPressed: () =>
                      context.push(Routes.athleteData, extra: profile),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Editar'),
                ),
              ],
            ),
            for (final (icon, label, value) in rows)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(icon, color: muted),
                title: Text(label),
                trailing: Text(
                  value ?? 'Não informado',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: value == null ? muted : null,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Foto do perfil; o técnico e o jogador tocam para enviar, trocar ou remover
/// a deles.
class _Avatar extends ConsumerStatefulWidget {
  const _Avatar({required this.profile});

  final Profile profile;

  @override
  ConsumerState<_Avatar> createState() => _AvatarState();
}

class _AvatarState extends ConsumerState<_Avatar> {
  var _saving = false;

  Future<void> _choose() async {
    final profile = widget.profile;
    final choice = await chooseImage(
      context,
      ref,
      noun: 'foto',
      canRemove: profile.avatarUrl != null,
      cropSquare: true,
    );
    if (choice == null) return;
    setState(() => _saving = true);
    try {
      final repository = ref.read(profileRepositoryProvider);
      switch (choice) {
        case ImagePicked(:final image):
          await repository.uploadPhoto(profile.id, image);
        case ImageRemoved():
          await repository.removePhoto(profile.id);
      }
      ref.invalidate(currentProfileProvider);
    } catch (_) {
      if (mounted) {
        showErrorSnackBar(context, 'Não foi possível salvar a foto.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final colorScheme = Theme.of(context).colorScheme;
    final initials = profile.fullName
        .split(' ')
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();
    final avatarUrl = profile.avatarUrl;
    final avatar = CircleAvatar(
      radius: 40,
      foregroundImage: avatarUrl == null ? null : NetworkImage(avatarUrl),
      onForegroundImageError: avatarUrl == null ? null : (_, _) {},
      child: Text(initials, style: Theme.of(context).textTheme.headlineSmall),
    );
    if (!profile.isCoach && !profile.isPlayer) return avatar;

    return Semantics(
      button: true,
      label: avatarUrl == null ? 'Adicionar foto' : 'Trocar foto',
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: _saving ? null : _choose,
        child: Stack(
          children: [
            avatar,
            if (_saving)
              const Positioned.fill(
                child: Center(child: CircularProgressIndicator()),
              ),
            Positioned(
              right: 0,
              bottom: 0,
              child: CircleAvatar(
                radius: 14,
                backgroundColor: colorScheme.primary,
                child: Icon(
                  Icons.photo_camera,
                  size: 14,
                  color: colorScheme.onPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
