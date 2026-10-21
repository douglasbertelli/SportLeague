import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabaseClientProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);

/// Sessão atual; emite um novo valor a cada login, logout ou refresh de token.
final authSessionProvider = StreamProvider<Session?>((ref) {
  final auth = ref.watch(supabaseClientProvider).auth;
  return auth.onAuthStateChange.map((event) => event.session);
});

/// ID do usuário logado, ou `null` se não houver sessão.
final currentUserIdProvider = Provider<String?>(
  (ref) => ref.watch(authSessionProvider).value?.user.id,
);
