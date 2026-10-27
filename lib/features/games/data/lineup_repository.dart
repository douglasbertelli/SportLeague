import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../teams/domain/team.dart';

/// Um atleta na escalação do jogo: titular ou reserva.
typedef LineupEntry = ({String teamId, String athleteId, bool starter});

/// Quantos titulares cada modalidade tem em campo.
int startersFor(Modality? modality) => switch (modality) {
  Modality.futsal || Modality.beach => 5,
  Modality.society => 7,
  Modality.field => 11,
  Modality.challenge || null => 5,
};

class LineupRepository {
  LineupRepository(this._client);

  final SupabaseClient _client;

  /// Escalação do jogo (os dois times).
  Future<List<LineupEntry>> fetchGame(String gameId) async {
    final rows = await _client
        .from('game_lineups')
        .select('team_id, athlete_id, starter')
        .eq('game_id', gameId);
    return [
      for (final row in rows)
        (
          teamId: row['team_id'] as String,
          athleteId: row['athlete_id'] as String,
          starter: row['starter'] as bool,
        ),
    ];
  }

  /// Salva a escalação de um time: quem está em [entries] foi escalado; quem
  /// saiu da lista sai da escalação.
  Future<void> saveTeam({
    required String gameId,
    required String teamId,
    required List<LineupEntry> entries,
  }) async {
    final keep = [for (final entry in entries) entry.athleteId];
    var remove = _client
        .from('game_lineups')
        .delete()
        .eq('game_id', gameId)
        .eq('team_id', teamId);
    if (keep.isNotEmpty) {
      remove = remove.not('athlete_id', 'in', '(${keep.join(',')})');
    }
    await remove;
    if (entries.isEmpty) return;
    await _client.from('game_lineups').upsert([
      for (final entry in entries)
        {
          'game_id': gameId,
          'team_id': teamId,
          'athlete_id': entry.athleteId,
          'starter': entry.starter,
        },
    ]);
  }
}

final lineupRepositoryProvider = Provider<LineupRepository>(
  (ref) => LineupRepository(ref.watch(supabaseClientProvider)),
);

/// Escalação do jogo.
final gameLineupProvider = FutureProvider.autoDispose
    .family<List<LineupEntry>, String>(
      (ref, gameId) => ref.watch(lineupRepositoryProvider).fetchGame(gameId),
    );
