import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/env.dart';
import '../../../core/supabase/supabase_providers.dart';

/// Deep link de retorno do login social feito pelo navegador. Precisa estar
/// em Authentication → URL Configuration → Redirect URLs no Supabase.
const authRedirectUrl = 'com.sportleague.sportleague://login-callback';

bool get _isAndroidOrIos =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

bool get _isApple =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS);

class AuthRepository {
  AuthRepository(this._auth);

  final GoTrueClient _auth;
  Future<void>? _googleInit;

  /// Cria a conta. O perfil é criado no banco pelo trigger `handle_new_user`
  /// a partir de `full_name`, ainda sem tipo de perfil: ele é escolhido na
  /// etapa seguinte, como no login social.
  ///
  /// Retorna `true` se o e-mail ainda precisa ser confirmado (sem sessão).
  Future<bool> signUp({
    required String fullName,
    required String email,
    required String password,
  }) async {
    final response = await _auth.signUp(
      email: email.trim(),
      password: password,
      data: {'full_name': fullName.trim()},
    );
    return response.session == null;
  }

  Future<void> signIn({required String email, required String password}) =>
      _auth.signInWithPassword(email: email.trim(), password: password);

  /// Entra (ou cria a conta) com Google. Nativo no Android e no iOS; nas
  /// demais plataformas abre o navegador.
  ///
  /// Retorna `false` se o usuário cancelou.
  Future<bool> signInWithGoogle() async {
    if (!_isAndroidOrIos) {
      return _auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: kIsWeb ? null : authRedirectUrl,
      );
    }

    if (Env.googleWebClientId.isEmpty) {
      throw const AuthException('Login com Google não configurado neste app.');
    }
    final google = GoogleSignIn.instance;
    await (_googleInit ??= google.initialize(
      serverClientId: Env.googleWebClientId,
      clientId: defaultTargetPlatform == TargetPlatform.iOS
          ? Env.googleIosClientId
          : null,
    ));

    final GoogleSignInAccount account;
    try {
      account = await google.authenticate();
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) return false;
      rethrow;
    }

    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw const AuthException('Google não retornou o ID token.');
    }
    await _auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
    );
    return true;
  }

  /// Entra (ou cria a conta) com Apple. Nativo no iOS e no macOS; no Android
  /// e nas demais plataformas abre o navegador.
  ///
  /// Retorna `false` se o usuário cancelou.
  Future<bool> signInWithApple() async {
    if (!_isApple) {
      return _auth.signInWithOAuth(
        OAuthProvider.apple,
        redirectTo: kIsWeb ? null : authRedirectUrl,
      );
    }

    final rawNonce = _auth.generateRawNonce();
    final AuthorizationCredentialAppleID credential;
    try {
      credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: sha256.convert(utf8.encode(rawNonce)).toString(),
      );
    } on SignInWithAppleAuthorizationException catch (error) {
      if (error.code == AuthorizationErrorCode.canceled) return false;
      rethrow;
    }

    final idToken = credential.identityToken;
    if (idToken == null) {
      throw const AuthException('Apple não retornou o ID token.');
    }
    await _auth.signInWithIdToken(
      provider: OAuthProvider.apple,
      idToken: idToken,
      nonce: rawNonce,
    );

    // A Apple só envia o nome no primeiro login e fora do ID token.
    final fullName = [
      credential.givenName,
      credential.familyName,
    ].whereType<String>().join(' ').trim();
    if (fullName.isNotEmpty) {
      await _auth.updateUser(UserAttributes(data: {'full_name': fullName}));
    }
    return true;
  }

  Future<void> sendPasswordReset(String email) =>
      _auth.resetPasswordForEmail(email.trim());

  Future<void> signOut() async {
    if (_googleInit != null) {
      // Sem isso o Android reaproveita a última conta sem mostrar a escolha.
      await GoogleSignIn.instance.signOut().catchError((_) {});
    }
    await _auth.signOut();
  }
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(supabaseClientProvider).auth),
);
