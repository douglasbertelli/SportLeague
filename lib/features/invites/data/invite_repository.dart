import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../teams/data/team_repository.dart';
import '../../teams/domain/team.dart';
import '../domain/team_invite.dart';

class InviteRepository {
  InviteRepository(this._client);

  final SupabaseClient _client;

  static const _columns =
      '*, player:profiles!team_invites_profile_id_fkey(full_name, avatar_url), '
      'team:teams(name, logo_url)';

  /// Código de convite do time (só o dono vê).
  Future<String?> inviteCode(String teamId) async {
    final row = await _client
        .from('team_invite_codes')
        .select('code')
        .eq('team_id', teamId)
        .maybeSingle();
    return row?['code'] as String?;
  }

  /// Gera outro código; o antigo deixa de valer.
  Future<String> regenerateCode(String teamId) =>
      _client.rpc<String>('regenerate_invite_code', params: {'p_team': teamId});

  /// Pedidos para entrar no time, mais recentes primeiro.
  Future<List<TeamInvite>> teamRequests(String teamId) =>
      _teamInvites(teamId, direction: 'request');

  /// Convites que o time mandou, mais recentes primeiro.
  Future<List<TeamInvite>> teamSentInvites(String teamId) =>
      _teamInvites(teamId, direction: 'invite');

  Future<List<TeamInvite>> _teamInvites(
    String teamId, {
    required String direction,
  }) async {
    final rows = await _client
        .from('team_invites')
        .select(_columns)
        .eq('team_id', teamId)
        .eq('direction', direction)
        .order('created_at', ascending: false)
        .limit(50);
    return rows.map(TeamInvite.fromMap).toList();
  }

  /// Contas de jogador pelo nome, para convidar.
  Future<List<PlayerSummary>> searchPlayers(String query) async {
    // %, _ e \ são curingas do ilike: procurados como texto.
    final term = query.trim().replaceAllMapped(
      RegExp(r'[%_\\]'),
      (match) => '\\${match[0]}',
    );
    final rows = await _client
        .from('profiles')
        .select('id, full_name, avatar_url')
        .eq('role', 'player')
        .ilike('full_name', '%$term%')
        .order('full_name')
        .limit(30);
    return rows.map(PlayerSummary.fromMap).toList();
  }

  /// O dono do time convida o jogador [profileId].
  Future<void> invitePlayer({
    required String teamId,
    required String profileId,
    required String ownerId,
  }) => _client.from('team_invites').insert({
    'team_id': teamId,
    'profile_id': profileId,
    'created_by': ownerId,
    'direction': 'invite',
  });

  /// Convites e pedidos do jogador, mais recentes primeiro.
  Future<List<TeamInvite>> myInvites(String profileId) async {
    final rows = await _client
        .from('team_invites')
        .select(_columns)
        .eq('profile_id', profileId)
        .order('created_at', ascending: false)
        .limit(50);
    return rows.map(TeamInvite.fromMap).toList();
  }

  /// Times em que o usuário é atleta ou técnico.
  Future<List<Team>> myTeams(String profileId) async {
    final [players, coaches] = await Future.wait([
      _client
          .from('team_players')
          .select('team:teams($teamColumns)')
          .eq('profile_id', profileId),
      _client
          .from('team_coaches')
          .select('team:teams($teamColumns)')
          .eq('profile_id', profileId),
    ]);
    return [
      for (final row in [...players, ...coaches])
        if (row['team'] case final Map<String, dynamic> team)
          Team.fromMap(team),
    ];
  }

  /// Técnicos do time, com nome e foto.
  Future<List<PlayerSummary>> teamCoaches(String teamId) async {
    final rows = await _client
        .from('team_coaches')
        .select('profile:profiles(id, full_name, avatar_url)')
        .eq('team_id', teamId);
    return [
      for (final row in rows)
        if (row['profile'] case final Map<String, dynamic> profile)
          PlayerSummary.fromMap(profile),
    ];
  }

  /// O dono tira o técnico do time (ou o técnico sai).
  Future<void> removeCoach(String teamId, String profileId) => _client
      .from('team_coaches')
      .delete()
      .eq('team_id', teamId)
      .eq('profile_id', profileId);

  /// O dono aceita ([accept]) ou recusa um pedido; o jogador aceita ou
  /// recusa um convite.
  Future<void> respond(String inviteId, {required bool accept}) => _client
      .from('team_invites')
      .update({'status': accept ? 'accepted' : 'declined'})
      .eq('id', inviteId);

  /// Quem enviou desiste (o jogador cancela o pedido).
  Future<void> cancel(String inviteId) => _client
      .from('team_invites')
      .update({'status': 'canceled'})
      .eq('id', inviteId);

  /// O jogador pede para entrar no time.
  Future<void> requestToJoin(String teamId, String profileId) =>
      _client.from('team_invites').insert({
        'team_id': teamId,
        'profile_id': profileId,
        'created_by': profileId,
        'direction': 'request',
      });

  /// Time do código (nulo se o código não existir).
  Future<String?> teamIdByCode(String code) =>
      _client.rpc<String?>('team_by_invite_code', params: {'p_code': code});

  /// Entra no time do código; devolve o id do time.
  Future<String> joinWithCode(String code) =>
      _client.rpc<String>('join_team_with_code', params: {'p_code': code});
}

final inviteRepositoryProvider = Provider<InviteRepository>(
  (ref) => InviteRepository(ref.watch(supabaseClientProvider)),
);

/// Código de convite de um time.
final inviteCodeProvider = FutureProvider.family<String?, String>(
  (ref, teamId) => ref.watch(inviteRepositoryProvider).inviteCode(teamId),
);

/// Pedidos para entrar num time.
final teamRequestsProvider = FutureProvider.family<List<TeamInvite>, String>(
  (ref, teamId) => ref.watch(inviteRepositoryProvider).teamRequests(teamId),
);

/// Convites que o time mandou.
final teamSentInvitesProvider = FutureProvider.family<List<TeamInvite>, String>(
  (ref, teamId) => ref.watch(inviteRepositoryProvider).teamSentInvites(teamId),
);

/// Convites e pedidos do jogador logado.
final myInvitesProvider = FutureProvider<List<TeamInvite>>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return const [];
  return ref.watch(inviteRepositoryProvider).myInvites(userId);
});

/// Times em que o jogador logado é atleta.
final myPlayerTeamsProvider = FutureProvider<List<Team>>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return const [];
  return ref.watch(inviteRepositoryProvider).myTeams(userId);
});

/// Abre o compartilhamento do sistema (WhatsApp etc.). Substituível nos
/// testes.
final shareTextProvider = Provider<Future<void> Function(String text)>(
  (ref) =>
      (text) async => SharePlus.instance.share(ShareParams(text: text)),
);

/// Técnicos do time.
final teamCoachesProvider = FutureProvider.autoDispose
    .family<List<PlayerSummary>, String>(
      (ref, teamId) => ref.watch(inviteRepositoryProvider).teamCoaches(teamId),
    );
