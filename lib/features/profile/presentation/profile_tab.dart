import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../../address/data/address_repository.dart';
import '../../auth/data/auth_repository.dart';
import '../domain/profile.dart';

/// Aba Perfil: dados da conta, endereço e saída.
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

class _Avatar extends StatelessWidget {
  const _Avatar({required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context) {
    final initials = profile.fullName
        .split(' ')
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();
    final avatarUrl = profile.avatarUrl;
    return CircleAvatar(
      radius: 40,
      foregroundImage: avatarUrl == null ? null : NetworkImage(avatarUrl),
      onForegroundImageError: avatarUrl == null ? null : (_, _) {},
      child: Text(initials, style: Theme.of(context).textTheme.headlineSmall),
    );
  }
}
