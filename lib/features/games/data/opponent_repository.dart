import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../teams/data/team_repository.dart';
import '../../teams/domain/team.dart';
import '../domain/opponent.dart';

class OpponentRepository {
  OpponentRepository(this._client);

  final SupabaseClient _client;

  static const _limit = 20;

  /// Adversários possíveis para um amistoso de [teamId] na [modality]: times
  /// da plataforma (menos o próprio time) e os times fictícios do
  /// administrador, filtrados pelo nome.
  Future<({List<Team> registered, List<GuestTeam> guests})> search({
    required String teamId,
    required String ownerId,
    required Modality modality,
    required String query,
  }) async {
    final pattern = '%${_escapeLike(query.trim())}%';
    final results = await Future.wait([
      _client
          .from('teams')
          .select(teamColumns)
          .contains('modalities', [modality.name])
          .neq('id', teamId)
          .ilike('name', pattern)
          .order('name')
          .limit(_limit),
      _client
          .from('guest_teams')
          .select()
          .eq('owner_id', ownerId)
          .eq('modality', modality.name)
          .ilike('name', pattern)
          .order('name')
          .limit(_limit),
    ]);
    return (
      registered: results[0].map(Team.fromMap).toList(),
      guests: results[1].map(GuestTeam.fromMap).toList(),
    );
  }

  Future<GuestTeam> createGuest(GuestTeam guest) async {
    final row = await _client
        .from('guest_teams')
        .insert(guest.toMap())
        .select()
        .single();
    return GuestTeam.fromMap(row);
  }

  /// `%` e `_` digitados pelo usuário são texto, não curingas.
  static String _escapeLike(String value) =>
      value.replaceAllMapped(RegExp(r'[\\%_]'), (m) => '\\${m[0]}');
}

final opponentRepositoryProvider = Provider<OpponentRepository>(
  (ref) => OpponentRepository(ref.watch(supabaseClientProvider)),
);
