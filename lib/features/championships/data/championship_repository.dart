import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../domain/championship.dart';
import '../domain/championship_rules.dart';

class ChampionshipRepository {
  ChampionshipRepository(this._client);

  final SupabaseClient _client;

  /// Campeonatos que o usuário organiza ou em que um time dele está (o banco
  /// filtra), os mais novos primeiro.
  Future<List<Championship>> fetchMine() async {
    final rows = await _client
        .from('championships')
        .select()
        .order('created_at', ascending: false);
    return rows.map(Championship.fromMap).toList();
  }

  Future<Championship> fetch(String id) async {
    final row = await _client
        .from('championships')
        .select()
        .eq('id', id)
        .single();
    return Championship.fromMap(row);
  }

  Future<Championship> create(Championship championship) async {
    final row = await _client
        .from('championships')
        .insert(championship.toMap())
        .select()
        .single();
    return Championship.fromMap(row);
  }

  Future<void> update(Championship championship) => _client
      .from('championships')
      .update(championship.toMap())
      .eq('id', championship.id!);

  Future<void> delete(String id) =>
      _client.from('championships').delete().eq('id', id);

  Future<List<ChampionshipTeam>> fetchTeams(String championshipId) async {
    final rows = await _client
        .from('championship_teams')
        .select('*, team:teams(logo_url, owner_id)')
        .eq('championship_id', championshipId)
        .order('created_at');
    return rows.map(ChampionshipTeam.fromMap).toList();
  }

  /// Inscreve um time da plataforma ([teamId], convidado se não for do
  /// organizador) ou fictício ([guestTeamId], já confirmado).
  Future<void> addTeam(
    String championshipId, {
    String? teamId,
    String? guestTeamId,
  }) => _client.from('championship_teams').insert({
    'championship_id': championshipId,
    'team_id': teamId,
    'guest_team_id': guestTeamId,
  });

  Future<void> removeTeam(String entryId) =>
      _client.from('championship_teams').delete().eq('id', entryId);

  /// O dono do time convidado aceita ou recusa.
  Future<void> respond(String entryId, {required bool accept}) => _client.rpc(
    'respond_championship_invite',
    params: {'p_entry': entryId, 'p_accept': accept},
  );

  Future<List<ChampionshipMatch>> fetchMatches(String championshipId) async {
    final rows = await _client
        .from('championship_matches')
        .select('*, venue:venues(name)')
        .eq('championship_id', championshipId)
        .order('stage')
        .order('round')
        .order('slot');
    return rows.map(ChampionshipMatch.fromMap).toList();
  }

  /// Começa o campeonato: grava os grupos sorteados, cria os jogos e muda
  /// a situação para em andamento.
  Future<void> start(
    Championship championship,
    List<PlannedMatch> matches, {
    Map<String, String> groups = const {},
  }) async {
    for (final MapEntry(key: entryId, value: label) in groups.entries) {
      await _client
          .from('championship_teams')
          .update({'group_label': label})
          .eq('id', entryId);
    }
    await addMatches(championship.id!, matches);
    await _client
        .from('championships')
        .update({'status': ChampionshipStatus.running.name})
        .eq('id', championship.id!);
  }

  Future<void> addMatches(String championshipId, List<PlannedMatch> matches) =>
      _client.from('championship_matches').insert([
        for (final match in matches) match.toMap(championshipId),
      ]);

  /// Data, hora e local do jogo.
  Future<void> schedule(
    String matchId, {
    required DateTime? at,
    required String? venueId,
  }) => _client
      .from('championship_matches')
      .update({
        'scheduled_at': at?.toUtc().toIso8601String(),
        'venue_id': venueId,
      })
      .eq('id', matchId);

  /// Placar (e pênaltis) do jogo; nulos apagam o placar.
  Future<void> setScore(
    String matchId, {
    required int? home,
    required int? away,
    int? homePenalties,
    int? awayPenalties,
  }) => _client
      .from('championship_matches')
      .update({
        'home_score': home,
        'away_score': away,
        'home_penalties': homePenalties,
        'away_penalties': awayPenalties,
      })
      .eq('id', matchId);

  /// Põe (ou tira, com nulo) um time num lado do jogo do mata-mata.
  Future<void> setSide(String matchId, {required bool home, String? teamId}) =>
      _client
          .from('championship_matches')
          .update({home ? 'home_id' : 'away_id': teamId})
          .eq('id', matchId);

  Future<void> setStatus(String championshipId, ChampionshipStatus status) =>
      _client
          .from('championships')
          .update({'status': status.name})
          .eq('id', championshipId);
}

final championshipRepositoryProvider = Provider<ChampionshipRepository>(
  (ref) => ChampionshipRepository(ref.watch(supabaseClientProvider)),
);

final myChampionshipsProvider = FutureProvider.autoDispose<List<Championship>>(
  (ref) => ref.watch(championshipRepositoryProvider).fetchMine(),
);

final championshipProvider = FutureProvider.autoDispose
    .family<Championship, String>(
      (ref, id) => ref.watch(championshipRepositoryProvider).fetch(id),
    );

final championshipTeamsProvider = FutureProvider.autoDispose
    .family<List<ChampionshipTeam>, String>(
      (ref, id) => ref.watch(championshipRepositoryProvider).fetchTeams(id),
    );

final championshipMatchesProvider = FutureProvider.autoDispose
    .family<List<ChampionshipMatch>, String>(
      (ref, id) => ref.watch(championshipRepositoryProvider).fetchMatches(id),
    );
