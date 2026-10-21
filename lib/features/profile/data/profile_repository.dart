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

  /// Conclui o cadastro de contas criadas por login social. O banco só aceita
  /// definir o role enquanto ele ainda está nulo.
  Future<void> completeProfile({
    required String userId,
    required String fullName,
    required UserRole role,
  }) => _client
      .from('profiles')
      .update({'full_name': fullName.trim(), 'role': role.name})
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
