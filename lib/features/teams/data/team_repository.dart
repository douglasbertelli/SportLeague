import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/media/picked_image.dart';
import '../../../core/storage/preferences_provider.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../../athletes/data/athlete_repository.dart';
import '../domain/team.dart';
import '../domain/season.dart';
import '../domain/team_stats.dart';

/// Colunas do time com o local (home_venue) junto.
const teamColumns = '*, home_venue:venues!teams_home_venue_id_fkey(*)';

class TeamRepository {
  TeamRepository(this._client);

  final SupabaseClient _client;

  /// Times do administrador, em ordem alfabética.
  Future<List<Team>> fetchByOwner(String ownerId) async {
    final rows = await _client
        .from('teams')
        .select(teamColumns)
        .eq('owner_id', ownerId)
        .order('name');
    return rows.map(Team.fromMap).toList();
  }

  /// Times em que o usuário é técnico, em ordem alfabética.
  Future<List<Team>> fetchCoached(String profileId) async {
    final rows = await _client
        .from('teams')
        .select('$teamColumns, team_coaches!inner(profile_id)')
        .eq('team_coaches.profile_id', profileId)
        .order('name');
    return rows.map(Team.fromMap).toList();
  }

  /// Times em que o usuário é atleta (jogador vinculado), em ordem
  /// alfabética.
  Future<List<Team>> fetchPlayed(String profileId) async {
    final rows = await _client
        .from('teams')
        .select('$teamColumns, team_players!inner(profile_id)')
        .eq('team_players.profile_id', profileId)
        .order('name');
    return rows.map(Team.fromMap).toList();
  }

  /// Times da plataforma pelo nome, em ordem alfabética (vazio lista os
  /// primeiros).
  Future<List<Team>> search(String query) async {
    // %, _ e \ são curingas do ilike: procurados como texto.
    final term = query.trim().replaceAllMapped(
      RegExp(r'[%_\\]'),
      (match) => '\\${match[0]}',
    );
    final rows = await _client
        .from('teams')
        .select(teamColumns)
        .ilike('name', '%$term%')
        .order('name')
        .limit(30);
    return rows.map(Team.fromMap).toList();
  }

  /// Números e últimos resultados do time (função do banco).
  /// Números do time; com [season], só os jogos da temporada (últimos
  /// resultados, próximos jogos e seguidores não mudam).
  Future<TeamStats> stats(String teamId, {Season? season}) async {
    final data = await _client.rpc<Map<String, dynamic>>(
      'team_profile_stats',
      params: {
        'p_team': teamId,
        'p_from': season?.start.toUtc().toIso8601String(),
        'p_to': season?.end.toUtc().toIso8601String(),
      },
    );
    return TeamStats.fromMap(data);
  }

  /// Se o time [followerId] segue o time [followedId].
  Future<bool> isFollowing(String followerId, String followedId) async {
    final row = await _client
        .from('team_follows')
        .select('follower_team_id')
        .eq('follower_team_id', followerId)
        .eq('followed_team_id', followedId)
        .maybeSingle();
    return row != null;
  }

  Future<void> follow(String followerId, String followedId) => _client
      .from('team_follows')
      .insert({'follower_team_id': followerId, 'followed_team_id': followedId});

  Future<void> unfollow(String followerId, String followedId) => _client
      .from('team_follows')
      .delete()
      .eq('follower_team_id', followerId)
      .eq('followed_team_id', followedId);

  /// Qualquer time da plataforma (para o perfil); nulo se não existir mais.
  Future<Team?> fetchById(String teamId) async {
    final row = await _client
        .from('teams')
        .select(teamColumns)
        .eq('id', teamId)
        .maybeSingle();
    return row == null ? null : Team.fromMap(row);
  }

  Future<Team> create(Team team) async {
    final row = await _client
        .from('teams')
        .insert(team.toMap())
        .select(teamColumns)
        .single();
    return Team.fromMap(row);
  }

  Future<void> update(Team team) =>
      _client.from('teams').update(team.toMap()).eq('id', team.id!);

  /// Remove o time com os atletas e jogos dele (cascade no banco), o logo e as
  /// fotos dos atletas.
  Future<void> delete(Team team) async {
    final photoRows = await _client
        .from('team_players')
        .select('photo_path')
        .eq('team_id', team.id!)
        .not('photo_path', 'is', null);
    await _client.from('teams').delete().eq('id', team.id!);

    final photoPaths = [
      for (final row in photoRows) row['photo_path'] as String,
    ];
    if (photoPaths.isNotEmpty) {
      await _client.storage.from(athletePhotosBucket).remove(photoPaths);
    }
    if (team.logoUrl != null) await removeLogo(team);
    await removeImages([?team.coverUrl, ...team.kitUrls]);
  }

  static const _logoBucket = 'team-logos';

  /// Pasta do dono + id do time: as regras do Storage só deixam o dono gravar.
  static String _logoPath(Team team) => '${team.ownerId}/${team.id}';

  /// Envia (ou substitui) o logo e retorna a URL pública. A URL muda a cada
  /// envio para o app não mostrar a imagem antiga do cache.
  Future<String> uploadLogo(Team team, PickedImage image) async {
    final storage = _client.storage.from(_logoBucket);
    final path = _logoPath(team);
    await storage.uploadBinary(
      path,
      image.bytes,
      fileOptions: FileOptions(contentType: image.contentType, upsert: true),
    );
    return storage.getPublicUrl(
      path,
      cacheNonce: DateTime.now().millisecondsSinceEpoch.toString(),
    );
  }

  Future<void> removeLogo(Team team) =>
      _client.storage.from(_logoBucket).remove([_logoPath(team)]);

  /// Envia a capa (substituindo a anterior) e retorna a URL pública.
  Future<String> uploadCover(Team team, PickedImage image) =>
      _upload('${_logoPath(team)}-cover', image);

  /// Envia uma foto de uniforme num arquivo novo e retorna a URL pública.
  Future<String> uploadKit(Team team, PickedImage image) => _upload(
    '${_logoPath(team)}-kit-${DateTime.now().microsecondsSinceEpoch}',
    image,
  );

  Future<String> _upload(String path, PickedImage image) async {
    final storage = _client.storage.from(_logoBucket);
    await storage.uploadBinary(
      path,
      image.bytes,
      fileOptions: FileOptions(contentType: image.contentType, upsert: true),
    );
    return storage.getPublicUrl(
      path,
      cacheNonce: DateTime.now().millisecondsSinceEpoch.toString(),
    );
  }

  /// Remove do Storage as imagens das [urls] públicas (capa, uniformes).
  Future<void> removeImages(List<String> urls) async {
    final paths = [for (final url in urls) ?_pathOf(url)];
    if (paths.isNotEmpty) {
      await _client.storage.from(_logoBucket).remove(paths);
    }
  }

  /// Caminho no bucket a partir da URL pública: `.../team-logos/dono/arquivo?t=1`
  /// vira `dono/arquivo`.
  static String? _pathOf(String url) {
    const marker = '/$_logoBucket/';
    final start = url.indexOf(marker);
    if (start < 0) return null;
    return Uri.decodeComponent(
      url.substring(start + marker.length).split('?').first,
    );
  }
}

final teamRepositoryProvider = Provider<TeamRepository>(
  (ref) => TeamRepository(ref.watch(supabaseClientProvider)),
);

/// Se o usuário logado é técnico (os times dele vêm dos vínculos, não da
/// posse). O app liga ao perfil em `main.dart`; aqui é falso.
final isCoachProvider = Provider<bool>((ref) => false);

/// Se o usuário logado é jogador (os times dele são aqueles em que é
/// atleta). O app liga ao perfil em `main.dart`; aqui é falso.
final isPlayerProvider = Provider<bool>((ref) => false);

/// Times do administrador logado, os times em que o técnico está ou os
/// times em que o jogador é atleta.
final myTeamsProvider = FutureProvider<List<Team>>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return const [];
  final repository = ref.watch(teamRepositoryProvider);
  if (ref.watch(isPlayerProvider)) return repository.fetchPlayed(userId);
  return ref.watch(isCoachProvider)
      ? repository.fetchCoached(userId)
      : repository.fetchByOwner(userId);
});

/// Se o usuário é o dono do time ativo (o técnico só vê e escala). Sem time
/// ativo, falso.
final canManageTeamProvider = Provider<bool>((ref) {
  final team = ref.watch(selectedTeamProvider).value;
  return team != null && team.ownerId == ref.watch(currentUserIdProvider);
});

/// Se o usuário monta a escalação e a súmula do time ativo: o dono ou o
/// técnico. O jogador só acompanha.
final isTeamStaffProvider = Provider<bool>(
  (ref) => ref.watch(canManageTeamProvider) || ref.watch(isCoachProvider),
);

/// Um time pelo id, para o perfil.
final teamByIdProvider = FutureProvider.autoDispose.family<Team?, String>(
  (ref, teamId) => ref.watch(teamRepositoryProvider).fetchById(teamId),
);

/// Números do perfil de um time (como os jogos, buscados de novo ao voltar).
final teamStatsProvider = FutureProvider.autoDispose.family<TeamStats, String>(
  (ref, teamId) => ref
      .watch(teamRepositoryProvider)
      .stats(teamId, season: ref.watch(seasonProvider)),
);

/// Se o time ativo segue o time do perfil.
final isFollowingProvider =
    FutureProvider.family<bool, ({String follower, String followed})>(
      (ref, pair) => ref
          .watch(teamRepositoryProvider)
          .isFollowing(pair.follower, pair.followed),
    );

final selectedTeamIdProvider =
    NotifierProvider<SelectedTeamIdNotifier, String?>(
      SelectedTeamIdNotifier.new,
    );

/// Time escolhido no seletor da barra superior, salvo no aparelho.
class SelectedTeamIdNotifier extends Notifier<String?> {
  static const _key = 'selected_team_id';

  @override
  String? build() => ref.watch(sharedPreferencesProvider).getString(_key);

  Future<void> select(String teamId) async {
    state = teamId;
    await ref.read(sharedPreferencesProvider).setString(_key, teamId);
  }
}

/// Time ativo: o escolhido, ou o primeiro se a escolha não existe mais.
/// Nulo quando o administrador ainda não tem times.
final selectedTeamProvider = FutureProvider<Team?>((ref) async {
  final teams = await ref.watch(myTeamsProvider.future);
  final selectedId = ref.watch(selectedTeamIdProvider);
  for (final team in teams) {
    if (team.id == selectedId) return team;
  }
  return teams.firstOrNull;
});
