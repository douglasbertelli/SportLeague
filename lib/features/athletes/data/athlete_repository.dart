import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/media/picked_image.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../domain/athlete.dart';

/// Bucket privado das fotos dos atletas.
const athletePhotosBucket = 'athlete-photos';

class AthleteRepository {
  AthleteRepository(this._client);

  final SupabaseClient _client;

  /// Validade das URLs assinadas das fotos.
  static const _photoUrlTtl = Duration(hours: 1);

  StorageFileApi get _photos => _client.storage.from(athletePhotosBucket);

  /// Atletas do time, em ordem alfabética, com URL temporária da foto (ou,
  /// sem foto de atleta, a foto do perfil do jogador vinculado).
  Future<List<Athlete>> fetchByTeam(String teamId) async {
    final rows = await _client
        .from('team_players')
        .select('*, profile:profiles(avatar_url)')
        .eq('team_id', teamId)
        .order('name');
    final athletes = rows
        .map(Athlete.fromMap)
        .map((athlete) => athlete.copyWith(photoUrl: athlete.profilePhotoUrl))
        .toList();

    final paths = [for (final a in athletes) ?a.photoPath];
    if (paths.isEmpty) return athletes;
    // Uma foto que não pôde ser assinada (ex.: arquivo removido) só fica sem
    // URL; a lista mostra a inicial no lugar.
    final signed = await _photos.createSignedUrlsResult(
      paths,
      _photoUrlTtl.inSeconds,
    );
    final urlByPath = {
      for (final result in signed)
        if (result case SignedUrlSuccess(:final path, :final signedUrl))
          path: signedUrl,
    };
    return [
      for (final athlete in athletes)
        athlete.copyWith(
          photoUrl: urlByPath[athlete.photoPath] ?? athlete.profilePhotoUrl,
        ),
    ];
  }

  Future<Athlete> create(Athlete athlete) async {
    final row = await _client
        .from('team_players')
        .insert(athlete.toMap())
        .select()
        .single();
    return Athlete.fromMap(row);
  }

  Future<void> update(Athlete athlete) => _client
      .from('team_players')
      .update(athlete.toMap())
      .eq('id', athlete.id!);

  Future<void> delete(Athlete athlete) async {
    await _client.from('team_players').delete().eq('id', athlete.id!);
    if (athlete.photoPath case final path?) await removePhoto(path);
  }

  /// Envia (ou substitui) a foto e retorna o caminho no bucket:
  /// `<dono do time>/<time>/<atleta>`. As regras do Storage só deixam o dono
  /// do time gravar.
  Future<String> uploadPhoto({
    required String ownerId,
    required Athlete athlete,
    required PickedImage image,
  }) async {
    final path = '$ownerId/${athlete.teamId}/${athlete.id}';
    await _photos.uploadBinary(
      path,
      image.bytes,
      fileOptions: FileOptions(contentType: image.contentType, upsert: true),
    );
    return path;
  }

  Future<void> removePhoto(String path) => _photos.remove([path]);
}

final athleteRepositoryProvider = Provider<AthleteRepository>(
  (ref) => AthleteRepository(ref.watch(supabaseClientProvider)),
);

/// Atletas de um time.
final teamAthletesProvider = FutureProvider.family<List<Athlete>, String>(
  (ref, teamId) => ref.watch(athleteRepositoryProvider).fetchByTeam(teamId),
);
