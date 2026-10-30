import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/security/biometrics.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../../profile/data/profile_repository.dart';
import 'auth_repository.dart';

/// "Sair": com a biometria ligada, guarda a conta (a sessão continua no
/// cofre e a tela de login oferece "Entrar como ..."); sem ela, sai de vez.
Future<void> signOutOrPark(WidgetRef ref) async {
  final userId = ref.read(currentUserIdProvider);
  if (userId != null && ref.read(biometricLockProvider)) {
    final name = ref.read(currentProfileProvider).value?.displayName ?? '';
    await ref
        .read(biometricParkingProvider.notifier)
        .park(userId: userId, name: name);
    return;
  }
  await ref.read(authRepositoryProvider).signOut();
}

/// Volta para a conta guardada depois da digital, do rosto ou do PIN.
/// `false` se a pessoa cancelou; [AuthException] se a sessão não vale mais
/// (aí a conta guardada é esquecida e é preciso entrar com a senha).
Future<bool> signInWithBiometrics(WidgetRef ref) async {
  if (!await ref
      .read(biometricsProvider)
      .authenticate('Entre no SportLeague')) {
    return false;
  }
  final auth = ref.read(supabaseClientProvider).auth;
  final parked = ref.read(biometricParkingProvider);
  const expired = AuthException('Sua sessão expirou. Entre com a senha.');
  if (parked == null || auth.currentSession?.user.id != parked.userId) {
    await forgetBiometrics(ref);
    throw expired;
  }
  try {
    await auth.refreshSession();
  } on AuthRetryableFetchException {
    // Sem internet: entra com a sessão que tem; ela renova depois.
  } on AuthException {
    await forgetBiometrics(ref);
    throw expired;
  }
  await ref.read(biometricParkingProvider.notifier).clear();
  return true;
}

/// "Remover biometria deste aparelho": sai de vez (encerra a sessão no
/// servidor) e desliga a biometria.
Future<void> forgetBiometrics(WidgetRef ref) async {
  // Sai antes de liberar a conta guardada, para o app não voltar a ela.
  await ref.read(authRepositoryProvider).signOut();
  await ref.read(biometricParkingProvider.notifier).clear();
  await ref.read(biometricLockProvider.notifier).reset();
}
