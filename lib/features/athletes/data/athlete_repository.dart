import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../domain/athlete.dart';

class AthleteRepository {
  AthleteRepository(this._client);

  final SupabaseClient _client;

  /// Atletas do time, em ordem alfabética.
  Future<List<Athlete>> fetchByTeam(String teamId) async {
    final rows = await _client
        .from('team_players')
        .select()
        .eq('team_id', teamId)
        .order('name');
    return rows.map(Athlete.fromMap).toList();
  }

  Future<void> create(Athlete athlete) =>
      _client.from('team_players').insert(athlete.toMap());

  Future<void> update(Athlete athlete) => _client
      .from('team_players')
      .update(athlete.toMap())
      .eq('id', athlete.id!);

  Future<void> delete(String athleteId) =>
      _client.from('team_players').delete().eq('id', athleteId);
}

final athleteRepositoryProvider = Provider<AthleteRepository>(
  (ref) => AthleteRepository(ref.watch(supabaseClientProvider)),
);

/// Atletas de um time.
final teamAthletesProvider = FutureProvider.family<List<Athlete>, String>(
  (ref, teamId) => ref.watch(athleteRepositoryProvider).fetchByTeam(teamId),
);
