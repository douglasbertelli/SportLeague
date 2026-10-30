import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../security/biometrics.dart';

final supabaseClientProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);

/// Todos os acontecimentos do login (entrou, saiu, token renovado).
final authEventsProvider = StreamProvider<AuthState>(
  (ref) => ref.watch(supabaseClientProvider).auth.onAuthStateChange,
);

/// Sessão atual; emite um novo valor a cada login, logout ou refresh de token.
/// Com a conta guardada para a biometria (o "Sair" com biometria ligada), o
/// app se comporta como deslogado, mas a sessão continua no cofre.
final authSessionProvider = StreamProvider<Session?>((ref) {
  if (ref.watch(biometricParkingProvider) != null) return Stream.value(null);
  final auth = ref.watch(supabaseClientProvider).auth;
  return auth.onAuthStateChange.map((event) => event.session);
});

/// ID do usuário logado, ou `null` se não houver sessão.
final currentUserIdProvider = Provider<String?>(
  (ref) => ref.watch(authSessionProvider).value?.user.id,
);
