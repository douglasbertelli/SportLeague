import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../domain/board_post.dart';

/// Mural do time: tudo pelas funções do banco (team_board e companhia), que
/// conferem quem é do time e quem publica.
class BoardRepository {
  BoardRepository(this._client);

  final SupabaseClient _client;

  Future<TeamBoard> fetch(String teamId) async {
    final data = await _client.rpc<Map<String, dynamic>>(
      'team_board',
      params: {'p_team': teamId},
    );
    return TeamBoard.fromMap(data);
  }

  /// Novo aviso ou enquete (dono ou técnico).
  Future<void> create({
    required String teamId,
    required BoardPostKind kind,
    required String body,
    List<String> options = const [],
    bool multiple = false,
    bool anonymous = false,
    DateTime? closesAt,
    bool pinned = false,
  }) => _client.rpc(
    'create_team_post',
    params: {
      'p_team': teamId,
      'p_kind': kind.name,
      'p_body': body,
      'p_options': kind == BoardPostKind.poll ? options : null,
      'p_multiple': multiple,
      'p_anonymous': anonymous,
      'p_closes_at': closesAt?.toUtc().toIso8601String(),
      'p_pinned': pinned,
    },
  );

  Future<void> setPinned(String postId, {required bool pinned}) => _client.rpc(
    'set_team_post_pinned',
    params: {'p_post': postId, 'p_pinned': pinned},
  );

  Future<void> delete(String postId) =>
      _client.rpc('delete_team_post', params: {'p_post': postId});

  Future<void> markRead(List<String> postIds) => postIds.isEmpty
      ? Future.value()
      : _client.rpc('mark_team_posts_read', params: {'p_posts': postIds});

  /// Troca os votos de quem vê pelos de [optionIds] (vazio tira o voto).
  Future<void> vote(String postId, List<String> optionIds) => _client.rpc(
    'vote_team_poll',
    params: {'p_post': postId, 'p_options': optionIds},
  );

  /// Lembra quem ainda não votou; devolve quantos.
  Future<int> remind(String postId) async =>
      await _client.rpc<int>('remind_team_poll', params: {'p_post': postId});

  Future<void> toggleReaction(String postId, String emoji) => _client.rpc(
    'toggle_team_post_reaction',
    params: {'p_post': postId, 'p_emoji': emoji},
  );

  Future<List<PostComment>> comments(String postId) async {
    final rows = await _client.rpc<List<dynamic>>(
      'team_post_comments',
      params: {'p_post': postId},
    );
    return [
      for (final row in rows) PostComment.fromMap(row as Map<String, dynamic>),
    ];
  }

  Future<void> addComment(String postId, String body) => _client.rpc(
    'add_team_post_comment',
    params: {'p_post': postId, 'p_body': body},
  );

  Future<void> deleteComment(String commentId) =>
      _client.rpc('delete_team_post_comment', params: {'p_comment': commentId});

  Future<List<PostReader>> readers(String postId) async {
    final rows = await _client.rpc<List<dynamic>>(
      'team_post_readers',
      params: {'p_post': postId},
    );
    return [
      for (final row in rows) PostReader.fromMap(row as Map<String, dynamic>),
    ];
  }
}

final boardRepositoryProvider = Provider<BoardRepository>(
  (ref) => BoardRepository(ref.watch(supabaseClientProvider)),
);

/// Mural de um time.
final teamBoardProvider = FutureProvider.autoDispose.family<TeamBoard, String>(
  (ref, teamId) => ref.watch(boardRepositoryProvider).fetch(teamId),
);

/// Comentários de um aviso.
final postCommentsProvider = FutureProvider.autoDispose
    .family<List<PostComment>, String>(
      (ref, postId) => ref.watch(boardRepositoryProvider).comments(postId),
    );

/// Quem leu um aviso (dono e técnicos).
final postReadersProvider = FutureProvider.autoDispose
    .family<List<PostReader>, String>(
      (ref, postId) => ref.watch(boardRepositoryProvider).readers(postId),
    );
