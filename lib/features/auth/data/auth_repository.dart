import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/env.dart';
import '../../../core/push/push_notifications.dart';
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

/// Se a pessoa fechou a janela do Google (sem mensagem de erro).
///
/// No Android, o Credential Manager também devolve "cancelado" para falhas
/// que não são da pessoa, como "[16] Account reauth failed" (app sem o
/// cliente OAuth certo no Google Cloud, ou sem internet). Nesses casos o
/// login falhava sem aviso; agora só conta como desistência quando a
/// descrição diz que foi a pessoa que cancelou.
bool isGoogleUserCancel(GoogleSignInException error) {
  if (error.code != GoogleSignInExceptionCode.canceled) return false;
  final description = error.description;
  if (description == null || description.trim().isEmpty) return true;
  if (description.contains('[16]')) return false;
  return RegExp(
    r'cancel+ed by (the )?user|user cancel+ed|canceled the sign-in',
    caseSensitive: false,
  ).hasMatch(description);
}

class AuthRepository {
  AuthRepository(this._auth, {this.beforeSignOut});

  final GoTrueClient _auth;

  /// Roda ainda logado, antes de sair (tira o aparelho do push).
  final Future<void> Function()? beforeSignOut;
  Future<void>? _googleInit;

  /// Cria a conta. O perfil é criado no banco pelo trigger `handle_new_user`
  /// a partir de `full_name`, já com o aceite dos Termos dado no cadastro
  /// (`terms_accepted_at`) e ainda sem tipo de perfil: ele é escolhido na
  /// etapa seguinte, como no login social.
  ///
  /// O link de confirmação do e-mail leva à página Conta confirmada do site
  /// (a mesma do cadastro do site vindo do app), que abre o app; sem ele, o
  /// Supabase mandaria para o login do site.
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
      emailRedirectTo: '${Env.siteUrl}/conta-confirmada',
      data: {
        'full_name': fullName.trim(),
        'terms_accepted_at': DateTime.now().toUtc().toIso8601String(),
      },
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
      if (isGoogleUserCancel(error)) return false;
      debugPrint('Google sign-in: ${error.code} ${error.description}');
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

  /// Manda o link para criar uma senha nova. O link abre a página Nova senha
  /// do site (passando por /auth/callback, que entra na conta pelo token do
  /// link); depois a pessoa volta ao app e entra com a senha nova.
  Future<void> sendPasswordReset(String email) => _auth.resetPasswordForEmail(
    email.trim(),
    redirectTo: '${Env.siteUrl}/auth/callback?next=/nova-senha',
  );

  Future<void> signOut() async {
    await beforeSignOut?.call();
    if (_googleInit != null) {
      // Sem isso o Android reaproveita a última conta sem mostrar a escolha.
      await GoogleSignIn.instance.signOut().catchError((_) {});
    }
    await _auth.signOut();
  }
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(
    ref.watch(supabaseClientProvider).auth,
    beforeSignOut: () => ref.read(pushRegistrationProvider).unregister(),
  ),
);
