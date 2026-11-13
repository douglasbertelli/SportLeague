import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/media/photo_picker.dart';
import '../../../core/media/picked_image.dart';
import '../../../core/router/routes.dart';
import '../../../core/security/biometric_tile.dart';
import '../../../core/security/biometrics.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../../../core/theme/app_color_picker.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/theme_mode_button.dart';
import '../../address/data/address_repository.dart';
import '../../auth/data/biometric_sign_in.dart';
import '../../plans/data/plan_repository.dart';
import '../../plans/domain/plan_status.dart';
import '../../plans/presentation/plan_gate.dart';
import 'account_deletion.dart';
import '../data/profile_repository.dart';
import '../domain/profile.dart';
import 'edit_text_sheet.dart';

/// Aba Perfil. Do jogador: a capa, a foto, o apelido e os dados de atleta (o
/// resto fica na aba Config). Do administrador e do técnico, tudo aqui: a
/// conta, Meu código (técnico), a cor do time, o endereço e o Sair.
class ProfileTab extends ConsumerWidget {
  const ProfileTab({super.key, required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!profile.isPlayer) return _StaffProfile(profile: profile);
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        // A capa, com a foto sobreposta na borda de baixo.
        _CoverHeader(profile: profile),
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
      // O apelido (ou o nome, sem apelido), trocado pelo lápis; com apelido,
      // o nome completo vem embaixo, discreto.
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(width: 40),
          Flexible(
            child: Text(
              profile.displayName,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          IconButton(
            tooltip: profile.nickname == null
                ? 'Adicionar apelido'
                : 'Editar apelido',
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.edit_outlined,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            onPressed: () => editNickname(context, ref, profile),
          ),
        ],
      ),
      if (profile.nickname != null)
        Text(
          profile.fullName,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      const SizedBox(height: 28),
      _AthleteDataCard(profile: profile),
    ];
  }
}

/// Perfil do administrador e do técnico: o cabeçalho compacto; num grupo,
/// Meu código (técnico), a cor do time, o tema e o endereço; o Sair à parte.
class _StaffProfile extends ConsumerWidget {
  const _StaffProfile({required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final email = ref.watch(supabaseClientProvider).auth.currentUser?.email;
    final address = ref.watch(myAddressProvider).value;
    final items = [
      if (profile.code case final code?)
        ListTile(
          leading: const Icon(Icons.qr_code_2),
          title: const Text('Meu código'),
          subtitle: Text('$code · para o administrador te convidar'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(Routes.myCode),
        ),
      ListTile(
        leading: const Icon(Icons.public),
        title: const Text('Perfil público'),
        subtitle: Text(
          profile.publicEnabled
              ? 'Ligado · ${profile.publicHandle == null ? 'link com código' : '@${profile.publicHandle}'}'
              : 'Uma página com seus números para compartilhar',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push(Routes.publicProfile),
      ),
      // Só o administrador tem plano.
      if (profile.isAdmin)
        ListTile(
          leading: const Icon(Icons.workspace_premium_outlined),
          title: const Text('Planos'),
          subtitle: Text(switch (ref.watch(planStatusProvider).value) {
            PlanStatus(trialEndsAt: final ends?) =>
              'Teste do Premium até ${formatDayMonth(ends)}',
            final status? => 'Você está no plano ${status.plan.label}',
            null => 'Você está no plano ${profile.plan.label}',
          }),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(Routes.plans),
        ),
      if (profile.isAdmin)
        ListTile(
          leading: const Icon(Icons.account_balance_wallet_outlined),
          title: const Text('Financeiro'),
          subtitle: const Text('Valor da assinatura e pagamentos'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(Routes.finance),
        ),
      const AppColorTile(),
      const ThemeModeTile(),
      // Some em aparelhos sem biometria cadastrada.
      if (ref.watch(biometricsAvailableProvider).value ?? false)
        const BiometricTile(),
      ListTile(
        leading: const Icon(Icons.location_on_outlined),
        title: const Text('Endereço'),
        subtitle: address == null
            ? null
            : Text(
                '${address.street}, ${address.number} - '
                '${address.city}/${address.state}',
              ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push(Routes.editAddress),
      ),
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ProfileHeader(profile: profile, email: email),
        const SizedBox(height: 16),
        SettingsGroup(items: items),
        const SizedBox(height: 16),
        const LegalLinks(),
        const SizedBox(height: 32),
        Card(
          child: ListTile(
            leading: Icon(Icons.logout, color: theme.colorScheme.error),
            title: Text(
              'Sair',
              style: TextStyle(color: theme.colorScheme.error),
            ),
            // Com a biometria ligada, guarda a conta para voltar com ela.
            onTap: () => signOutOrPark(ref),
          ),
        ),
        const SizedBox(height: 16),
        DeleteAccountButton(profile: profile),
      ],
    );
  }
}

/// Itens de configuração num só card, mais altos (com folga em volta do ícone
/// e do texto) e com o separador discreto, quase na cor do card. Usado no
/// Perfil do administrador e do técnico e na aba Config do jogador.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.items});

  final List<Widget> items;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListTileTheme(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      minVerticalPadding: 12,
      horizontalTitleGap: 20,
      child: Card(
        child: Column(
          children: [
            for (final (index, item) in items.indexed) ...[
              if (index > 0)
                Divider(
                  height: 1,
                  thickness: 1,
                  color: colors.outlineVariant.withValues(alpha: 0.35),
                ),
              item,
            ],
          ],
        ),
      ),
    );
  }
}

/// Cabeçalho compacto do perfil (administrador, técnico e, na aba Config, o
/// jogador): a foto, o nome e o e-mail numa linha; embaixo, em selos com
/// ícone, o tipo de perfil e (do administrador) o plano.
class ProfileHeader extends StatelessWidget {
  const ProfileHeader({super.key, required this.profile, this.email});

  final Profile profile;
  final String? email;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final email = this.email;

    // Compacto e discreto, no mesmo card dos itens: a foto, o nome e o
    // e-mail juntos numa linha e, embaixo, os selos dividindo a largura toda.
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _Avatar(profile: profile, radius: 26),
                const SizedBox(width: 14),
                Expanded(child: _identity(theme, colors, email)),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                if (profile.role case final role?)
                  Expanded(
                    child: _Badge(
                      icon: profile.isAdmin
                          ? Icons.admin_panel_settings_outlined
                          : Icons.sports_outlined,
                      label: role.label,
                    ),
                  ),
                // Só o administrador tem plano.
                if (profile.isAdmin) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    // O plano que vale agora (o Premium durante o teste).
                    child: Consumer(
                      builder: (context, ref, _) => _Badge(
                        icon: Icons.workspace_premium_outlined,
                        label:
                            'Plano ${(ref.watch(planStatusProvider).value?.plan ?? profile.plan).label}',
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// O nome e, embaixo, o e-mail com o ícone.
  Widget _identity(ThemeData theme, ColorScheme colors, String? email) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          profile.fullName,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (email != null)
          Row(
            children: [
              Icon(
                Icons.mail_outline,
                size: 14,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  email,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// Selo tonal com ícone, no tom do botão selecionado.
class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    // Ocupa a largura que receber, com o conteúdo centralizado.
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: colors.onSecondaryContainer),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: colors.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
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
  /// Raio da foto, com o anel: quanto ela desce abaixo da capa.
  static const _avatarRadius = 52.0 + _Avatar.ringWidth;

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
                  container: true,
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
                          // A capa se funde no fundo embaixo, onde fica a
                          // foto.
                          if (coverUrl != null)
                            DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  stops: const [0.5, 1],
                                  colors: [
                                    colors.surface.withValues(alpha: 0),
                                    colors.surface.withValues(alpha: 0.85),
                                  ],
                                ),
                              ),
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
                child: _Avatar(profile: widget.profile, radius: 52, ring: true),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Dados de atleta do jogador em blocos, dois por linha, com o Editar no
/// título. O que não foi preenchido aparece como "Não informado".
class _AthleteDataCard extends StatelessWidget {
  const _AthleteDataCard({required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final birthDate = profile.birthDate;
    final age = profile.age();
    final tiles = [
      _DataTile(
        icon: Icons.sports_soccer,
        label: 'Posição',
        value: profile.preferredPosition,
      ),
      _DataTile(
        icon: Icons.directions_walk,
        label: 'Pé dominante',
        value: switch (profile.preferredFoot) {
          null => null,
          PreferredFoot.both => 'Ambidestro',
          final foot => foot.label,
        },
      ),
      _DataTile(
        icon: Icons.height,
        label: 'Altura',
        value: switch (profile.heightCm) {
          final height? =>
            '${(height / 100).toStringAsFixed(2).replaceAll('.', ',')} m',
          null => null,
        },
      ),
      // A idade em destaque; a data, embaixo.
      _DataTile(
        icon: Icons.cake_outlined,
        label: switch (birthDate) {
          final date? =>
            'Nascimento · '
                '${MaterialLocalizations.of(context).formatCompactDate(date)}',
          null => 'Nascimento',
        },
        value: switch (age) {
          final years? => '$years anos',
          null => null,
        },
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Dados de atleta',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: () => context.push(Routes.athleteData, extra: profile),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Editar'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (var row = 0; row < tiles.length; row += 2) ...[
          if (row > 0) const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: tiles[row]),
                const SizedBox(width: 12),
                Expanded(child: tiles[row + 1]),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Um dado de atleta: o ícone num círculo, o valor em destaque e o nome
/// embaixo.
class _DataTile extends StatelessWidget {
  const _DataTile({required this.icon, required this.label, this.value});

  final IconData icon;
  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final value = this.value;
    // O mesmo card do Início, na mesma cor.
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 18,
              // O tom do botão selecionado (Sim/Não/Talvez, barra de baixo).
              backgroundColor: colors.secondaryContainer,
              child: Icon(icon, size: 20, color: colors.onSecondaryContainer),
            ),
            const SizedBox(height: 12),
            Text(
              value ?? 'Não informado',
              style: value == null
                  ? theme.textTheme.bodyLarge?.copyWith(
                      color: colors.onSurfaceVariant,
                    )
                  : theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
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
  const _Avatar({required this.profile, this.radius = 40, this.ring = false});

  /// Largura do anel da cor do fundo, que destaca a foto sobre a capa.
  static const ringWidth = 4.0;

  final Profile profile;
  final double radius;
  final bool ring;

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
    final photo = CircleAvatar(
      radius: widget.radius,
      foregroundImage: avatarUrl == null ? null : NetworkImage(avatarUrl),
      onForegroundImageError: avatarUrl == null ? null : (_, _) {},
      child: Text(initials, style: Theme.of(context).textTheme.headlineSmall),
    );
    final avatar = widget.ring
        ? Container(
            padding: const EdgeInsets.all(_Avatar.ringWidth),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              shape: BoxShape.circle,
            ),
            child: photo,
          )
        : photo;
    if (!profile.isCoach && !profile.isPlayer) return avatar;

    // Nó próprio, para o botão não se fundir com o card em volta.
    return Semantics(
      container: true,
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

/// Política de Privacidade e Termos de Uso, num grupo do perfil.
class LegalLinks extends StatelessWidget {
  const LegalLinks({super.key});

  @override
  Widget build(BuildContext context) => SettingsGroup(
    items: [
      ListTile(
        leading: const Icon(Icons.privacy_tip_outlined),
        title: const Text('Política de Privacidade'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push(Routes.privacy),
      ),
      ListTile(
        leading: const Icon(Icons.description_outlined),
        title: const Text('Termos de Uso'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push(Routes.terms),
      ),
    ],
  );
}
