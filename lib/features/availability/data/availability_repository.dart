import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../domain/availability.dart';

class AvailabilityRepository {
  AvailabilityRepository(this._client);

  final SupabaseClient _client;

  /// Horários cadastrados do time (avulsos e recorrentes).
  Future<List<Availability>> fetchByTeam(String teamId) async {
    final rows = await _client
        .from('team_availability')
        .select('*, team_availability_skips(on_date)')
        .eq('team_id', teamId)
        .order('starts_at')
        .order('weekday')
        .order('start_time');
    return rows.map(Availability.fromMap).toList();
  }

  Future<void> add(Availability availability) =>
      _client.from('team_availability').insert(availability.toMap());

  Future<void> update(Availability availability) => _client
      .from('team_availability')
      .update(availability.toMap())
      .eq('id', availability.id!);

  Future<void> delete(String id) =>
      _client.from('team_availability').delete().eq('id', id);

  /// Tira o dia [date] do horário recorrente [availabilityId] (imprevisto).
  Future<void> skipDate(String availabilityId, DateTime date) => _client
      .from('team_availability_skips')
      .insert({'availability_id': availabilityId, 'on_date': dateToDb(date)});

  /// Horários livres do time entre [from] e [to]: avulsos e recorrentes, já
  /// sem os que têm amistoso pendente ou marcado. Vem do banco (rpc), que não
  /// expõe os jogos do outro time.
  Future<List<DateTime>> freeSlots(
    String teamId, {
    required DateTime from,
    required DateTime to,
  }) async {
    final rows = await _client.rpc<List<dynamic>>(
      'available_slots',
      params: {
        'p_team': teamId,
        'p_from': from.toUtc().toIso8601String(),
        'p_to': to.toUtc().toIso8601String(),
      },
    );
    return [
      for (final row in rows)
        DateTime.parse((row as Map)['starts_at'] as String).toLocal(),
    ];
  }
}

final availabilityRepositoryProvider = Provider<AvailabilityRepository>(
  (ref) => AvailabilityRepository(ref.watch(supabaseClientProvider)),
);

/// Horários cadastrados de um time.
final teamAvailabilityProvider =
    FutureProvider.family<List<Availability>, String>(
      (ref, teamId) =>
          ref.watch(availabilityRepositoryProvider).fetchByTeam(teamId),
    );

/// Quantos dias à frente o app mostra horários livres para marcar.
const freeSlotsWindow = Duration(days: 90);

/// Horários livres de um time nos próximos [freeSlotsWindow] dias.
final freeSlotsProvider = FutureProvider.family<List<DateTime>, String>((
  ref,
  teamId,
) {
  final now = DateTime.now();
  return ref
      .watch(availabilityRepositoryProvider)
      .freeSlots(teamId, from: now, to: now.add(freeSlotsWindow));
});
