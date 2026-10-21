import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../domain/address.dart';

class AddressRepository {
  AddressRepository(this._client);

  final SupabaseClient _client;

  Future<Address?> fetchByProfile(String profileId) async {
    final row = await _client
        .from('addresses')
        .select()
        .eq('profile_id', profileId)
        .maybeSingle();
    return row == null ? null : Address.fromMap(row);
  }

  /// Cria ou atualiza o endereço do perfil (um endereço por perfil).
  Future<Address> save(Address address) async {
    final row = await _client
        .from('addresses')
        .upsert(address.toMap(), onConflict: 'profile_id')
        .select()
        .single();
    return Address.fromMap(row);
  }
}

final addressRepositoryProvider = Provider<AddressRepository>(
  (ref) => AddressRepository(ref.watch(supabaseClientProvider)),
);

/// Endereço do usuário logado (`null` se ainda não cadastrado).
final myAddressProvider = FutureProvider<Address?>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return null;
  return ref.watch(addressRepositoryProvider).fetchByProfile(userId);
});
