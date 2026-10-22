import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/media/picked_image.dart';
import '../../../core/storage/preferences_provider.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../../athletes/data/athlete_repository.dart';
import '../domain/team.dart';

class TeamRepository {
  TeamRepository(this._client);

  final SupabaseClient _client;

  /// Times do administrador, em ordem alfabética.
  Future<List<Team>> fetchByOwner(String ownerId) async {
    final rows = await _client
        .from('teams')
        .select()
        .eq('owner_id', ownerId)
        .order('name');
    return rows.map(Team.fromMap).toList();
  }

  Future<Team> create(Team team) async {
    final row = await _client
        .from('teams')
        .insert(team.toMap())
        .select()
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
}

final teamRepositoryProvider = Provider<TeamRepository>(
  (ref) => TeamRepository(ref.watch(supabaseClientProvider)),
);

/// Times do administrador logado.
final myTeamsProvider = FutureProvider<List<Team>>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return const [];
  return ref.watch(teamRepositoryProvider).fetchByOwner(userId);
});

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
