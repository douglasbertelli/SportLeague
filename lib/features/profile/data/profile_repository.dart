import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../domain/profile.dart';

class ProfileRepository {
  ProfileRepository(this._client);

  final SupabaseClient _client;

  Future<Profile?> fetch(String userId) async {
    final row = await _client
        .from('profiles')
        .select()
        .eq('id', userId)
        .maybeSingle();
    return row == null ? null : Profile.fromMap(row);
  }

  /// Define o tipo de perfil logo depois de criar a conta (e o nome, quando o
  /// cadastro não trouxe um). O banco só aceita definir o role enquanto ele
  /// ainda está nulo.
  Future<void> completeProfile({
    required String userId,
    required UserRole role,
    String? fullName,
  }) => _client
      .from('profiles')
      .update({
        'role': role.name,
        if (fullName != null) 'full_name': fullName.trim(),
      })
      .eq('id', userId);
}

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => ProfileRepository(ref.watch(supabaseClientProvider)),
);

/// Perfil do usuário logado.
final currentProfileProvider = FutureProvider<Profile?>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return null;
  return ref.watch(profileRepositoryProvider).fetch(userId);
});
