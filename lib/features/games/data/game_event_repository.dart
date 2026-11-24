import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/env.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../domain/game_event.dart';

/// Lances da súmula ao vivo (tabela game_events). O banco soma os gols no
/// placar, leva gols, assistências e cartões para a súmula dos atletas e
/// avisa os times.
class GameEventRepository {
  GameEventRepository(this._client);

  final SupabaseClient _client;

  static const _select =
      '*, athlete:team_players!athlete_id(name, profile:profiles(nickname)), '
      'related:team_players!related_athlete_id(name, profile:profiles(nickname))';

  /// Lances do jogo, do mais antigo para o mais novo.
  Future<List<GameEvent>> fetch(String gameId) async {
    final rows = await _client
        .from('game_events')
        .select(_select)
        .eq('game_id', gameId)
        // Sem `ascending`, o PostgREST do Dart ordena do mais novo ao mais
        // antigo; a lista sai do mais antigo e a tela inverte.
        .order('created_at', ascending: true);
    return rows.map(GameEvent.fromMap).toList();
  }

  /// Lança um lance; o minuto vem do relógio da partida.
  Future<void> add({
    required String gameId,
    required GameSide side,
    required GameEventKind kind,
    String? athleteId,
    String? relatedAthleteId,
    bool penalty = false,
  }) => _client.from('game_events').insert({
    'game_id': gameId,
    'side': side.name,
    'kind': kind.dbName,
    'athlete_id': athleteId,
    'related_athlete_id': relatedAthleteId,
    'penalty': penalty,
  });

  /// Completa autor e assistência (ou quem entrou) de um lance.
  Future<void> complete(
    String eventId, {
    String? athleteId,
    String? relatedAthleteId,
    bool? penalty,
  }) => _client
      .from('game_events')
      .update({
        'athlete_id': athleteId,
        'related_athlete_id': relatedAthleteId,
        'penalty': ?penalty,
      })
      .eq('id', eventId);

  /// Apaga o lance (o gol sai do placar e da súmula).
  Future<void> delete(String eventId) =>
      _client.from('game_events').delete().eq('id', eventId);

  /// Link público do jogo (cria o código na primeira vez).
  Future<String> publicLink(String gameId) async {
    final code = await _client.rpc<String>(
      'game_public_link',
      params: {'p_game': gameId},
    );
    return '${Env.siteUrl}/j/$code';
  }
}

final gameEventRepositoryProvider = Provider<GameEventRepository>(
  (ref) => GameEventRepository(ref.watch(supabaseClientProvider)),
);

/// Lances do jogo.
final gameEventsProvider = FutureProvider.autoDispose
    .family<List<GameEvent>, String>(
      (ref, gameId) => ref.watch(gameEventRepositoryProvider).fetch(gameId),
    );
