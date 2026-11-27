import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../sports/domain/sport_rules.dart';
import '../../../core/media/picked_image.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../../games/data/opponent_repository.dart';
import '../domain/championship.dart';
import '../domain/championship_stats.dart';
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
    return rows
        .where(isSupportedModalityRow)
        .map(Championship.fromMap)
        .toList();
  }

  Future<Championship> fetch(String id) async {
    final row = await _client
        .from('championships')
        .select()
        .eq('id', id)
        .single();
    // Campeonato de um esporte que esta versão não tem (por um link ou uma
    // notificação): a tela mostra o erro pedindo para atualizar.
    if (!isSupportedModalityRow(row)) throw const UnsupportedSportException();
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

  /// Liga ou desliga o link público do campeonato [id] (só o organizador);
  /// com [newLink], troca o código (o link antigo para de funcionar).
  /// Devolve o código atual.
  Future<String> setPublic(
    String id, {
    required bool enabled,
    bool newLink = false,
  }) => _client.rpc<String>(
    'set_championship_public',
    params: {'p_championship': id, 'p_enabled': enabled, 'p_new_link': newLink},
  );

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

  /// Envia (ou, com [image] nulo, remove) o símbolo do time fictício
  /// [guestTeamId]. Fica no bucket público dos logos, na pasta do dono; as
  /// inscrições nos campeonatos acompanham pelo banco.
  Future<void> setGuestLogo(String guestTeamId, PickedImage? image) =>
      OpponentRepository(_client).setGuestLogo(guestTeamId, image);

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

  /// Gols, assistências, jogos e craque de cada atleta no campeonato.
  Future<List<ChampionshipPlayerTotal>> fetchPlayerTotals(
    String championshipId,
  ) async {
    final rows = await _client.rpc(
      'championship_player_totals',
      params: {'p_championship': championshipId},
    );
    return [
      for (final row in rows as List)
        ChampionshipPlayerTotal.fromMap(row as Map<String, dynamic>),
    ];
  }

  /// Liga ou desliga a inscrição por link (só o organizador); com
  /// [newCode], troca o código. Devolve o código atual.
  Future<String> setSignup(
    String id, {
    required bool enabled,
    bool newCode = false,
  }) => _client.rpc<String>(
    'set_championship_signup',
    params: {'p_championship': id, 'p_enabled': enabled, 'p_new_code': newCode},
  );

  /// Pedidos de inscrição pelo link (o organizador).
  Future<List<ChampionshipRequest>> fetchRequests(String championshipId) async {
    final rows = await _client.rpc<List<dynamic>>(
      'championship_requests_list',
      params: {'p_championship': championshipId},
    );
    return [
      for (final row in rows)
        ChampionshipRequest.fromMap(row as Map<String, dynamic>),
    ];
  }

  Future<void> answerRequest(String requestId, {required bool accept}) =>
      _client.rpc(
        'answer_championship_request',
        params: {'p_request': requestId, 'p_accept': accept},
      );

  /// Artilharia, assistências, cartões, times, suspensos e seleção da
  /// rodada.
  Future<ChampionshipStats> fetchStats(String championshipId) async {
    final data = await _client.rpc<Map<String, dynamic>>(
      'championship_stats',
      params: {'p_championship': championshipId},
    );
    return ChampionshipStats.fromMap(data);
  }

  /// Atletas suspensos no jogo [gameId] (id do atleta → motivo).
  Future<Map<String, String>> gameSuspensions(String gameId) async {
    final rows = await _client.rpc<List<dynamic>>(
      'game_suspensions',
      params: {'p_game': gameId},
    );
    return {
      for (final row in rows.cast<Map<String, dynamic>>())
        row['athlete_id'] as String: row['reason'] as String? ?? 'Suspenso',
    };
  }

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

/// Estatísticas do campeonato.
final championshipStatsProvider = FutureProvider.autoDispose
    .family<ChampionshipStats, String>(
      (ref, id) => ref.watch(championshipRepositoryProvider).fetchStats(id),
    );

/// Pedidos de inscrição pelo link (o organizador).
final championshipRequestsProvider = FutureProvider.autoDispose
    .family<List<ChampionshipRequest>, String>(
      (ref, id) => ref.watch(championshipRepositoryProvider).fetchRequests(id),
    );

/// Atletas suspensos num jogo de campeonato (id do atleta → motivo).
final gameSuspensionsProvider = FutureProvider.autoDispose
    .family<Map<String, String>, String>(
      (ref, gameId) =>
          ref.watch(championshipRepositoryProvider).gameSuspensions(gameId),
    );

/// Artilharia e garçons do campeonato.
final championshipPlayerTotalsProvider = FutureProvider.autoDispose
    .family<List<ChampionshipPlayerTotal>, String>(
      (ref, id) =>
          ref.watch(championshipRepositoryProvider).fetchPlayerTotals(id),
    );
