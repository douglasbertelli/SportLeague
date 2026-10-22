import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/storage/preferences_provider.dart';
import '../../../core/supabase/supabase_providers.dart';
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

  /// Remove o time com os atletas e jogos dele (cascade no banco).
  Future<void> delete(String teamId) =>
      _client.from('teams').delete().eq('id', teamId);
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
