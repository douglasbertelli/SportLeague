import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/address/data/address_repository.dart';
import '../../features/address/presentation/address_page.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/auth/presentation/sign_up_page.dart';
import '../../features/home/presentation/home_page.dart';
import '../../features/splash/presentation/splash_page.dart';
import '../supabase/supabase_providers.dart';
import 'routes.dart';

const _publicRoutes = {Routes.login, Routes.signUp};

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier(0);
  void notify(_, _) => refresh.value++;
  ref.listen(authSessionProvider, notify);
  ref.listen(myAddressProvider, notify);

  final router = GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: (context, state) => appRedirect(
      location: state.matchedLocation,
      session: ref.read(authSessionProvider),
      address: ref.read(myAddressProvider),
    ),
    routes: [
      GoRoute(path: Routes.splash, builder: (_, _) => const SplashPage()),
      GoRoute(path: Routes.login, builder: (_, _) => const LoginPage()),
      GoRoute(path: Routes.signUp, builder: (_, _) => const SignUpPage()),
      GoRoute(
        path: Routes.onboardingAddress,
        builder: (_, _) => const AddressPage(isOnboarding: true),
      ),
      GoRoute(
        path: Routes.home,
        builder: (_, _) => const HomePage(),
        routes: [
          GoRoute(path: 'address', builder: (_, _) => const AddressPage()),
        ],
      ),
    ],
  );

  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});

/// Fluxo: sem sessão -> login; sem endereço -> cadastro de endereço; -> home.
@visibleForTesting
String? appRedirect({
  required String location,
  required AsyncValue<Object?> session,
  required AsyncValue<Object?> address,
}) {
  if (session.isLoading && !session.hasValue) return Routes.splash;

  final loggedIn = session.value != null;
  if (!loggedIn) return _publicRoutes.contains(location) ? null : Routes.login;

  // Recarga explícita (ref.invalidate) mantém a tela atual; troca de usuário
  // ou primeira carga mostra a splash.
  if (address.isLoading && !address.isRefreshing) return Routes.splash;
  if (address.hasError && !address.isLoading) return Routes.splash;

  if (address.value == null) {
    return location == Routes.onboardingAddress
        ? null
        : Routes.onboardingAddress;
  }

  const entryRoutes = {
    ..._publicRoutes,
    Routes.splash,
    Routes.onboardingAddress,
  };
  return entryRoutes.contains(location) ? Routes.home : null;
}
