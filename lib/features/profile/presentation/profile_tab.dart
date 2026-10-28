import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/media/photo_picker.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_color_picker.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../address/data/address_repository.dart';
import '../../auth/data/auth_repository.dart';
import '../data/profile_repository.dart';
import '../domain/profile.dart';
import 'my_numbers_section.dart';

/// Aba Perfil: dados da conta, endereço e saída. O jogador vê também os dados
/// de atleta e os números dele em todos os times.
class ProfileTab extends ConsumerWidget {
  const ProfileTab({super.key, required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final email = ref.watch(supabaseClientProvider).auth.currentUser?.email;
    final address = ref.watch(myAddressProvider).value;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(child: _Avatar(profile: profile)),
        const SizedBox(height: 12),
        Text(
          profile.fullName,
          style: theme.textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        if (email != null)
          Text(
            email,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          children: [
            if (profile.role case final role?) Chip(label: Text(role.label)),
            Chip(label: Text('Plano ${profile.plan.label}')),
          ],
        ),
        const SizedBox(height: 24),
        if (profile.isPlayer) ...[
          Card(
            child: ListTile(
              leading: const Icon(Icons.sports_soccer),
              title: const Text('Dados de atleta'),
              subtitle: Text(
                profile.hasAthleteData
                    ? _athleteSummary(profile)
                    : 'Posição, pé dominante, altura e nascimento',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(Routes.athleteData, extra: profile),
            ),
          ),
          const SizedBox(height: 24),
          const MyNumbersSection(),
          const SizedBox(height: 24),
        ],
        const Card(child: AppColorTile()),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
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
              const Divider(height: 1),
              ListTile(
                leading: Icon(Icons.logout, color: theme.colorScheme.error),
                title: Text(
                  'Sair',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
                onTap: () => ref.read(authRepositoryProvider).signOut(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// "Meia · Pé direito · 1,78 m · 24 anos", só com o que foi preenchido.
String _athleteSummary(Profile profile) => [
  ?profile.preferredPosition,
  if (profile.preferredFoot case final foot?)
    foot == PreferredFoot.both
        ? 'Ambidestro'
        : 'Pé ${foot.label.toLowerCase()}',
  if (profile.heightCm case final height?)
    '${(height / 100).toStringAsFixed(2).replaceAll('.', ',')} m',
  if (profile.age() case final age?) '$age anos',
].join(' · ');

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
