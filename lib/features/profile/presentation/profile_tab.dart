import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/media/photo_picker.dart';
import '../../../core/media/picked_image.dart';
import '../../../core/router/routes.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../data/profile_repository.dart';
import '../domain/profile.dart';
import 'edit_text_sheet.dart';

/// Aba Perfil: a foto, o nome e, do jogador, os dados de atleta. O resto
/// (Meu código, cor do time, endereço e Sair) fica na aba Config.
class ProfileTab extends ConsumerWidget {
  const ProfileTab({super.key, required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        // O jogador tem a capa, com a foto sobreposta na borda de baixo.
        if (profile.isPlayer)
          _CoverHeader(profile: profile)
        else
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Center(child: _Avatar(profile: profile)),
          ),
        const SizedBox(height: 12),
        // Nome e dados de atleta, com a margem dos lados (a capa vai de
        // borda a borda).
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _details(context, ref, theme),
          ),
        ),
      ],
    );
  }

  List<Widget> _details(BuildContext context, WidgetRef ref, ThemeData theme) {
    return [
      if (profile.isPlayer)
        // O jogador mostra o apelido (ou o nome, sem apelido) e troca pelo
        // lápis; o nome completo fica em Config.
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(width: 48),
            Flexible(
              child: Text(
                profile.displayName,
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
            ),
            IconButton(
              tooltip: profile.nickname == null
                  ? 'Adicionar apelido'
                  : 'Editar apelido',
              icon: const Icon(Icons.edit_outlined, size: 20),
              onPressed: () => editNickname(context, ref, profile),
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
    ];
  }
}

/// Capa do jogador, larga (16:9), com a foto centralizada na borda de baixo,
/// metade sobre a capa. O jogador toca na capa (ou no botão da câmera) para
/// enviar, trocar ou remover; a foto continua com o toque dela.
class _CoverHeader extends ConsumerStatefulWidget {
  const _CoverHeader({required this.profile});

  final Profile profile;

  @override
  ConsumerState<_CoverHeader> createState() => _CoverHeaderState();
}

class _CoverHeaderState extends ConsumerState<_CoverHeader> {
  /// Raio da foto (o mesmo do [_Avatar]): quanto ela desce abaixo da capa.
  static const _avatarRadius = 40.0;

  var _saving = false;

  Future<void> _choose() async {
    final profile = widget.profile;
    final choice = await chooseImage(
      context,
      ref,
      noun: 'capa',
      canRemove: profile.coverUrl != null,
      maxSize: largeImageSize,
    );
    if (choice == null) return;
    setState(() => _saving = true);
    try {
      final repository = ref.read(profileRepositoryProvider);
      switch (choice) {
        case ImagePicked(:final image):
          await repository.uploadCover(profile.id, image);
        case ImageRemoved():
          await repository.removeCover(profile.id);
      }
      ref.invalidate(currentProfileProvider);
    } catch (_) {
      if (mounted) {
        showErrorSnackBar(context, 'Não foi possível salvar a capa.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final coverUrl = widget.profile.coverUrl;

    return LayoutBuilder(
      builder: (context, constraints) {
        final coverHeight = constraints.maxWidth * 9 / 16;
        return SizedBox(
          height: coverHeight + _avatarRadius,
          child: Stack(
            children: [
              SizedBox(
                height: coverHeight,
                width: double.infinity,
                child: Semantics(
                  button: true,
                  label: coverUrl == null ? 'Adicionar capa' : 'Trocar capa',
                  child: InkWell(
                    onTap: _saving ? null : _choose,
                    child: Ink(
                      color: colors.surfaceContainerHigh,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (coverUrl != null)
                            Image.network(
                              coverUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  const SizedBox.shrink(),
                            )
                          else
                            Icon(
                              Icons.image_outlined,
                              size: 56,
                              color: colors.onSurfaceVariant,
                            ),
                          if (_saving)
                            const Center(child: CircularProgressIndicator()),
                          Positioned(
                            top: 12,
                            right: 12,
                            child: CircleAvatar(
                              radius: 18,
                              backgroundColor: colors.surface.withValues(
                                alpha: 0.85,
                              ),
                              child: Icon(
                                Icons.photo_camera_outlined,
                                size: 18,
                                color: colors.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // A foto, metade sobre a capa.
              Align(
                alignment: Alignment.bottomCenter,
                child: _Avatar(profile: widget.profile),
              ),
            ],
          ),
        );
      },
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
