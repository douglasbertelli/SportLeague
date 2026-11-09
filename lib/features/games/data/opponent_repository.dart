import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/media/picked_image.dart';
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
          .isFilter('inactive_at', null)
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

  /// Envia (ou, com [image] nulo, remove) o símbolo do time fictício
  /// [guestTeamId]. Fica no bucket público dos logos, na pasta do dono; as
  /// inscrições nos campeonatos acompanham pelo banco.
  Future<void> setGuestLogo(String guestTeamId, PickedImage? image) async {
    final storage = _client.storage.from('team-logos');
    final path = '${_client.auth.currentUser!.id}/guest-$guestTeamId';
    String? url;
    if (image == null) {
      await storage.remove([path]);
    } else {
      await storage.uploadBinary(
        path,
        image.bytes,
        fileOptions: FileOptions(contentType: image.contentType, upsert: true),
      );
      url = storage.getPublicUrl(
        path,
        cacheNonce: DateTime.now().millisecondsSinceEpoch.toString(),
      );
    }
    await _client
        .from('guest_teams')
        .update({'logo_url': url})
        .eq('id', guestTeamId);
  }

  /// Todos os times fictícios do administrador, em ordem alfabética.
  Future<List<GuestTeam>> fetchGuests(String ownerId) async {
    final rows = await _client
        .from('guest_teams')
        .select()
        .eq('owner_id', ownerId)
        .order('name');
    return rows.map(GuestTeam.fromMap).toList();
  }

  /// Troca o nome do fictício (os amistosos por jogar e os campeonatos
  /// acompanham pelo banco).
  Future<void> renameGuest(String guestTeamId, String name) => _client
      .from('guest_teams')
      .update({'name': name.trim()})
      .eq('id', guestTeamId);

  /// `%` e `_` digitados pelo usuário são texto, não curingas.
  static String _escapeLike(String value) =>
      value.replaceAllMapped(RegExp(r'[\\%_]'), (m) => '\\${m[0]}');
}

final opponentRepositoryProvider = Provider<OpponentRepository>(
  (ref) => OpponentRepository(ref.watch(supabaseClientProvider)),
);

/// Times fictícios do administrador logado.
final myGuestTeamsProvider = FutureProvider.autoDispose<List<GuestTeam>>((
  ref,
) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return const [];
  return ref.watch(opponentRepositoryProvider).fetchGuests(userId);
});
