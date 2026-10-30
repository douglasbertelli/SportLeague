import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Guarda a sessão do Supabase no cofre do aparelho (Keystore no Android,
/// Keychain no iPhone) em vez das preferências comuns. Na primeira vez, traz
/// a sessão que já estava salva lá, para ninguém precisar entrar de novo.
class SecureSessionStorage extends LocalStorage {
  SecureSessionStorage({required this.supabaseUrl});

  final String supabaseUrl;

  static const _storage = FlutterSecureStorage();

  /// A mesma chave que o supabase_flutter usa nas preferências.
  String get _key =>
      'sb-${Uri.parse(supabaseUrl).host.split('.').first}-auth-token';

  @override
  Future<void> initialize() async {
    final preferences = await SharedPreferences.getInstance();
    final legacy = preferences.getString(_key);
    if (legacy == null) return;
    if (!await _storage.containsKey(key: _key)) {
      await _storage.write(key: _key, value: legacy);
    }
    await preferences.remove(_key);
  }

  @override
  Future<bool> hasAccessToken() => _storage.containsKey(key: _key);

  @override
  Future<String?> accessToken() => _storage.read(key: _key);

  @override
  Future<void> removePersistedSession() => _storage.delete(key: _key);

  @override
  Future<void> persistSession(String persistSessionString) =>
      _storage.write(key: _key, value: persistSessionString);
}
