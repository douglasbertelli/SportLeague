import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/address/data/address_repository.dart';
import '../../features/address/presentation/address_page.dart';
import '../../features/athletes/domain/athlete.dart';
import '../../features/availability/presentation/availability_page.dart';
import '../../features/athletes/presentation/athlete_form_page.dart';
import '../../features/auth/presentation/complete_profile_page.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/auth/presentation/sign_up_page.dart';
import '../../features/games/domain/game.dart';
import '../../features/games/presentation/game_form_page.dart';
import '../../features/games/presentation/opponent_picker_page.dart';
import '../../features/home/presentation/home_page.dart';
import '../../features/profile/data/profile_repository.dart';
import '../../features/profile/domain/profile.dart';
import '../../features/splash/presentation/splash_page.dart';
import '../../features/teams/domain/team.dart';
import '../../features/teams/presentation/team_form_page.dart';
import '../../features/teams/presentation/teams_page.dart';
import '../supabase/supabase_providers.dart';
import 'routes.dart';

const _publicRoutes = {Routes.login, Routes.signUp};

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier(0);
  void notify(_, _) => refresh.value++;
  ref.listen(authSessionProvider, notify);
  ref.listen(currentProfileProvider, notify);
  ref.listen(myAddressProvider, notify);

  final router = GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: (context, state) => appRedirect(
      location: state.matchedLocation,
      session: ref.read(authSessionProvider),
      profile: ref.read(currentProfileProvider),
      address: ref.read(myAddressProvider),
    ),
    routes: [
      GoRoute(path: Routes.splash, builder: (_, _) => const SplashPage()),
      GoRoute(path: Routes.login, builder: (_, _) => const LoginPage()),
      GoRoute(path: Routes.signUp, builder: (_, _) => const SignUpPage()),
      GoRoute(
        path: Routes.onboardingProfile,
        builder: (_, _) => const CompleteProfilePage(),
      ),
      GoRoute(
        path: Routes.onboardingAddress,
        builder: (_, _) => const AddressPage(isOnboarding: true),
      ),
      GoRoute(
        path: Routes.home,
        builder: (_, _) => const HomePage(),
        routes: [
          GoRoute(path: 'address', builder: (_, _) => const AddressPage()),
          GoRoute(
            path: 'teams',
            builder: (_, _) => const TeamsPage(),
            routes: [
              GoRoute(path: 'new', builder: (_, _) => const TeamFormPage()),
              GoRoute(
                path: 'edit',
                builder: (_, state) => TeamFormPage(team: state.extra as Team),
              ),
            ],
          ),
          GoRoute(
            path: 'athletes/new',
            builder: (_, _) => const AthleteFormPage(),
          ),
          GoRoute(
            path: 'athletes/edit',
            builder: (_, state) =>
                AthleteFormPage(athlete: state.extra as Athlete),
          ),
          GoRoute(path: 'games/new', builder: (_, _) => const GameFormPage()),
          GoRoute(
            path: 'games/edit',
            builder: (_, state) => GameFormPage(game: state.extra as Game),
          ),
          GoRoute(
            path: 'games/opponent',
            builder: (_, state) {
              final (:teamId, :modalities, :modality) =
                  state.extra as OpponentPickerArgs;
              return OpponentPickerPage(
                teamId: teamId,
                modalities: modalities,
                modality: modality,
              );
            },
          ),
          GoRoute(
            path: 'availability',
            builder: (_, _) => const AvailabilityPage(),
          ),
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

/// Fluxo: sem sessão -> login; sem tipo de perfil (login social) -> completar
/// cadastro; sem endereço -> cadastro de endereço; -> home.
@visibleForTesting
String? appRedirect({
  required String location,
  required AsyncValue<Object?> session,
  required AsyncValue<Profile?> profile,
  required AsyncValue<Object?> address,
}) {
  if (session.isLoading && !session.hasValue) return Routes.splash;

  final loggedIn = session.value != null;
  if (!loggedIn) return _publicRoutes.contains(location) ? null : Routes.login;

  // Recarga explícita (ref.invalidate) mantém a tela atual; troca de usuário
  // ou primeira carga mostra a splash.
  for (final data in [profile, address]) {
    if (data.isLoading && !data.isRefreshing) return Routes.splash;
    if (data.hasError && !data.isLoading) return Routes.splash;
  }

  if (profile.value?.needsRole ?? false) {
    return location == Routes.onboardingProfile
        ? null
        : Routes.onboardingProfile;
  }

  if (address.value == null) {
    return location == Routes.onboardingAddress
        ? null
        : Routes.onboardingAddress;
  }

  const entryRoutes = {
    ..._publicRoutes,
    Routes.splash,
    Routes.onboardingProfile,
    Routes.onboardingAddress,
  };
  return entryRoutes.contains(location) ? Routes.home : null;
}
