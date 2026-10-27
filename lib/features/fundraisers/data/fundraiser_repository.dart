import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../domain/fundraiser.dart';

class FundraiserRepository {
  FundraiserRepository(this._client);

  final SupabaseClient _client;

  /// Vaquinhas do time: abertas primeiro, as mais novas no topo.
  Future<List<Fundraiser>> fetchTeam(String teamId) async {
    final rows = await _client
        .from('fundraisers')
        .select()
        .eq('team_id', teamId)
        .order('closed')
        .order('created_at', ascending: false);
    return rows.map(Fundraiser.fromMap).toList();
  }

  Future<Fundraiser> create(Fundraiser fundraiser) async {
    final row = await _client
        .from('fundraisers')
        .insert(fundraiser.toMap())
        .select()
        .single();
    return Fundraiser.fromMap(row);
  }

  Future<void> update(Fundraiser fundraiser) => _client
      .from('fundraisers')
      .update(fundraiser.toMap())
      .eq('id', fundraiser.id!);

  Future<void> delete(String fundraiserId) =>
      _client.from('fundraisers').delete().eq('id', fundraiserId);

  /// Quem já pagou ([FundraiserParticipant.key]).
  Future<FundraiserPayments> fetchPayments(String fundraiserId) async {
    final rows = await _client
        .from('fundraiser_payments')
        .select('athlete_id, profile_id')
        .eq('fundraiser_id', fundraiserId);
    return {
      for (final row in rows)
        (row['athlete_id'] as String?) ?? 'profile:${row['profile_id']}',
    };
  }

  /// Marca ([paid]) ou desmarca o pagamento do participante.
  Future<void> setPaid(
    String fundraiserId,
    FundraiserParticipant participant, {
    required bool paid,
  }) async {
    if (paid) {
      await _client.from('fundraiser_payments').insert({
        'fundraiser_id': fundraiserId,
        'athlete_id': participant.athleteId,
        'profile_id': participant.profileId,
      });
      return;
    }
    final remove = _client
        .from('fundraiser_payments')
        .delete()
        .eq('fundraiser_id', fundraiserId);
    await (participant.athleteId != null
        ? remove.eq('athlete_id', participant.athleteId!)
        : remove.eq('profile_id', participant.profileId!));
  }

  /// Nome e foto do administrador (dono do time).
  Future<({String name, String? photoUrl})> fetchOwner(String ownerId) async {
    final row = await _client
        .from('profiles')
        .select('full_name, avatar_url')
        .eq('id', ownerId)
        .single();
    return (
      name: row['full_name'] as String,
      photoUrl: row['avatar_url'] as String?,
    );
  }
}

final fundraiserRepositoryProvider = Provider<FundraiserRepository>(
  (ref) => FundraiserRepository(ref.watch(supabaseClientProvider)),
);

/// Vaquinhas do time.
final teamFundraisersProvider = FutureProvider.autoDispose
    .family<List<Fundraiser>, String>(
      (ref, teamId) =>
          ref.watch(fundraiserRepositoryProvider).fetchTeam(teamId),
    );

/// Quem pagou a vaquinha.
final fundraiserPaymentsProvider = FutureProvider.autoDispose
    .family<FundraiserPayments, String>(
      (ref, fundraiserId) =>
          ref.watch(fundraiserRepositoryProvider).fetchPayments(fundraiserId),
    );

/// Nome e foto do dono do time.
final teamOwnerProvider = FutureProvider.autoDispose
    .family<({String name, String? photoUrl}), String>(
      (ref, ownerId) =>
          ref.watch(fundraiserRepositoryProvider).fetchOwner(ownerId),
    );
