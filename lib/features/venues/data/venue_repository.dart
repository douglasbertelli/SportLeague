import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/media/picked_image.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../domain/venue.dart';

class VenueRepository {
  VenueRepository(this._client);

  final SupabaseClient _client;

  /// Locais pelo nome, bairro ou cidade, em ordem alfabética. Vazio lista os
  /// primeiros.
  Future<List<Venue>> search(String query) async {
    var request = _client.from('venues').select();
    // Vírgula e parênteses quebram o filtro "or" do PostgREST.
    final term = query.trim().replaceAll(RegExp(r'[,()]'), ' ');
    if (term.isNotEmpty) {
      request = request.or(
        'name.ilike.%$term%,neighborhood.ilike.%$term%,city.ilike.%$term%',
      );
    }
    final rows = await request.order('name').limit(50);
    return rows.map(Venue.fromMap).toList();
  }

  /// Locais que parecem ser o mesmo que [venue]: mesmo CEP e número, ou nome
  /// parecido na mesma cidade. Ignora o próprio [venue] na edição.
  Future<List<Venue>> findSimilar(Venue venue) async {
    final rows = await _client.rpc<List<dynamic>>(
      'similar_venues',
      params: {
        'p_name': venue.name,
        'p_zip_code': venue.zipCode,
        'p_number': venue.number,
        'p_city': venue.city,
        'p_state': venue.state,
        'p_except': venue.id,
      },
    );
    return [for (final row in rows) Venue.fromMap(row as Map<String, dynamic>)];
  }

  Future<Venue> create(Venue venue) async {
    final row = await _client
        .from('venues')
        .insert(venue.toMap())
        .select()
        .single();
    return Venue.fromMap(row);
  }

  Future<void> update(Venue venue) =>
      _client.from('venues').update(venue.toMap()).eq('id', venue.id!);

  /// Remove o local e a foto. Os amistosos marcados nele ficam sem local.
  Future<void> delete(Venue venue) async {
    await _client.from('venues').delete().eq('id', venue.id!);
    if (venue.photoUrl != null) await removePhoto(venue);
  }

  static const _photoBucket = 'venue-photos';

  /// Pasta de quem cadastrou + id do local: as regras do Storage só deixam
  /// essa pessoa gravar.
  static String _photoPath(Venue venue) => '${venue.createdBy}/${venue.id}';

  /// Envia (ou substitui) a foto e retorna a URL pública. A URL muda a cada
  /// envio para o app não mostrar a imagem antiga do cache.
  Future<String> uploadPhoto(Venue venue, PickedImage image) async {
    final storage = _client.storage.from(_photoBucket);
    final path = _photoPath(venue);
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

  Future<void> removePhoto(Venue venue) =>
      _client.storage.from(_photoBucket).remove([_photoPath(venue)]);
}

final venueRepositoryProvider = Provider<VenueRepository>(
  (ref) => VenueRepository(ref.watch(supabaseClientProvider)),
);
