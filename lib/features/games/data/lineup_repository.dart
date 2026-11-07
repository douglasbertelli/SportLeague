import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../teams/domain/team.dart';

/// Um atleta na escalação do jogo: titular ou reserva e, na escalação no
/// campo, a posição do titular na formação ([slot], 0 = goleiro).
typedef LineupEntry = ({
  String teamId,
  String athleteId,
  bool starter,
  int? slot,
});

/// Como a escalação abre no time.
enum LineupStyle {
  /// Titulares, reservas e fora, em lista (o padrão).
  list,

  /// No campo, com a formação (Premium).
  field;

  static LineupStyle fromName(String? name) =>
      values.where((style) => style.name == name).firstOrNull ?? list;
}

/// Escolha do time e se o plano do dono libera o campo.
typedef LineupSettings = ({
  LineupStyle style,
  bool fieldAvailable,
  String? ownerId,
});

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
        .select('team_id, athlete_id, starter, slot')
        .eq('game_id', gameId);
    return [
      for (final row in rows)
        (
          teamId: row['team_id'] as String,
          athleteId: row['athlete_id'] as String,
          starter: row['starter'] as bool,
          slot: row['slot'] as int?,
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
          'slot': entry.starter ? entry.slot : null,
        },
    ]);
  }

  /// Formação do time no jogo (nula se ainda não escolheu).
  Future<String?> fetchFormation(String gameId, String teamId) async {
    final row = await _client
        .from('game_formations')
        .select('formation')
        .eq('game_id', gameId)
        .eq('team_id', teamId)
        .maybeSingle();
    return row?['formation'] as String?;
  }

  Future<void> saveFormation({
    required String gameId,
    required String teamId,
    required String formation,
  }) => _client.from('game_formations').upsert({
    'game_id': gameId,
    'team_id': teamId,
    'formation': formation,
    'updated_at': DateTime.now().toUtc().toIso8601String(),
  });

  /// Como a escalação abre no time e se o plano do dono libera o campo.
  Future<LineupSettings> fetchSettings(String teamId) async {
    final results = await Future.wait<Object?>([
      _client
          .from('teams')
          .select('lineup_style, owner_id')
          .eq('id', teamId)
          .maybeSingle(),
      _client.rpc<bool>(
        'team_has_feature',
        params: {'p_team': teamId, 'p_feature': 'tactical_lineup'},
      ),
    ]);
    final row = results[0] as Map<String, dynamic>?;
    return (
      style: LineupStyle.fromName(row?['lineup_style'] as String?),
      fieldAvailable: results[1] == true,
      ownerId: row?['owner_id'] as String?,
    );
  }

  /// O administrador escolhe como a escalação abre no time.
  Future<void> setStyle(String teamId, LineupStyle style) => _client
      .from('teams')
      .update({'lineup_style': style.name})
      .eq('id', teamId);
}

final lineupRepositoryProvider = Provider<LineupRepository>(
  (ref) => LineupRepository(ref.watch(supabaseClientProvider)),
);

/// Escalação do jogo.
final gameLineupProvider = FutureProvider.autoDispose
    .family<List<LineupEntry>, String>(
      (ref, gameId) => ref.watch(lineupRepositoryProvider).fetchGame(gameId),
    );

/// Como a escalação do time abre e se o campo está liberado.
final lineupSettingsProvider = FutureProvider.autoDispose
    .family<LineupSettings, String>(
      (ref, teamId) =>
          ref.watch(lineupRepositoryProvider).fetchSettings(teamId),
    );

/// Formação do time no jogo.
final gameFormationProvider = FutureProvider.autoDispose
    .family<String?, ({String gameId, String teamId})>(
      (ref, key) => ref
          .watch(lineupRepositoryProvider)
          .fetchFormation(key.gameId, key.teamId),
    );
