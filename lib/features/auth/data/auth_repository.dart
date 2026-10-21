import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../profile/domain/profile.dart';

class AuthRepository {
  AuthRepository(this._auth);

  final GoTrueClient _auth;

  /// Cria a conta. O perfil é criado no banco pelo trigger `handle_new_user`
  /// a partir de `full_name` e `role`.
  ///
  /// Retorna `true` se o e-mail ainda precisa ser confirmado (sem sessão).
  Future<bool> signUp({
    required String fullName,
    required String email,
    required String password,
    required UserRole role,
  }) async {
    final response = await _auth.signUp(
      email: email.trim(),
      password: password,
      data: {'full_name': fullName.trim(), 'role': role.name},
    );
    return response.session == null;
  }

  Future<void> signIn({required String email, required String password}) =>
      _auth.signInWithPassword(email: email.trim(), password: password);

  Future<void> sendPasswordReset(String email) =>
      _auth.resetPasswordForEmail(email.trim());

  Future<void> signOut() => _auth.signOut();
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(supabaseClientProvider).auth),
);
