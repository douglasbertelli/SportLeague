import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/media/picked_image.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../domain/profile.dart';

class ProfileRepository {
  ProfileRepository(this._client);

  final SupabaseClient _client;

  Future<Profile?> fetch(String userId) async {
    final row = await _client
        .from('profiles')
        .select()
        .eq('id', userId)
        .maybeSingle();
    return row == null ? null : Profile.fromMap(row);
  }

  /// Define o tipo de perfil logo depois de criar a conta (e o nome, quando o
  /// cadastro não trouxe um). O banco só aceita definir o role enquanto ele
  /// ainda está nulo.
  Future<void> completeProfile({
    required String userId,
    required UserRole role,
    String? fullName,
  }) => _client
      .from('profiles')
      .update({
        'role': role.name,
        if (fullName != null) 'full_name': fullName.trim(),
      })
      .eq('id', userId);

  /// Troca o nome do usuário (o banco aceita de 2 a 120 caracteres).
  Future<void> updateName(String userId, String fullName) => _client
      .from('profiles')
      .update({'full_name': fullName.trim()})
      .eq('id', userId);

  /// Salva os dados de atleta do jogador (nulo limpa o campo).
  Future<void> updateAthleteData({
    required String userId,
    DateTime? birthDate,
    String? preferredPosition,
    PreferredFoot? preferredFoot,
    int? heightCm,
  }) => _client
      .from('profiles')
      .update({
        'birth_date': birthDate?.toIso8601String().substring(0, 10),
        'preferred_position': preferredPosition,
        'preferred_foot': preferredFoot?.name,
        'height_cm': heightCm,
      })
      .eq('id', userId);

  /// Gera outro código pessoal (JG ou TC); o antigo deixa de valer.
  Future<String> regenerateCode() => _client.rpc<String>('regenerate_my_code');

  static const _photoBucket = 'profile-photos';

  /// Pasta do próprio usuário: as regras do Storage só deixam ele gravar.
  static String _photoPath(String userId) => '$userId/avatar';

  /// Envia (ou substitui) a foto de perfil e grava a URL pública no perfil.
  /// A URL muda a cada envio para o app não mostrar a imagem antiga do cache.
  Future<void> uploadPhoto(String userId, PickedImage image) async {
    final storage = _client.storage.from(_photoBucket);
    final path = _photoPath(userId);
    await storage.uploadBinary(
      path,
      image.bytes,
      fileOptions: FileOptions(contentType: image.contentType, upsert: true),
    );
    final url = storage.getPublicUrl(
      path,
      cacheNonce: DateTime.now().millisecondsSinceEpoch.toString(),
    );
    await _client.from('profiles').update({'avatar_url': url}).eq('id', userId);
  }

  /// Tira a foto do perfil e apaga o arquivo.
  Future<void> removePhoto(String userId) async {
    await _client
        .from('profiles')
        .update({'avatar_url': null})
        .eq('id', userId);
    await _client.storage.from(_photoBucket).remove([_photoPath(userId)]);
  }
}

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => ProfileRepository(ref.watch(supabaseClientProvider)),
);

/// Perfil do usuário logado.
final currentProfileProvider = FutureProvider<Profile?>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return null;
  return ref.watch(profileRepositoryProvider).fetch(userId);
});
