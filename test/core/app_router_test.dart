import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sport_league/core/router/app_router.dart';
import 'package:sport_league/core/router/routes.dart';
import 'package:sport_league/features/profile/domain/profile.dart';

void main() {
  const loggedIn = AsyncData<Object?>('session');
  const loggedOut = AsyncData<Object?>(null);
  const hasAddress = AsyncData<Object?>('address');
  const noAddress = AsyncData<Object?>(null);
  const withRole = AsyncData<Profile?>(
    Profile(
      id: 'u1',
      fullName: 'Ana Souza',
      role: UserRole.player,
      plan: SubscriptionPlan.free,
    ),
  );
  const withoutRole = AsyncData<Profile?>(
    Profile(id: 'u1', fullName: 'Ana Souza', plan: SubscriptionPlan.free),
  );

  String? redirect(
    String location, {
    required AsyncValue<Object?> session,
    AsyncValue<Profile?> profile = withRole,
    AsyncValue<Object?> address = noAddress,
  }) => appRedirect(
    location: location,
    session: session,
    profile: profile,
    address: address,
  );

  test('sem sessão vai para o login, mas permite o cadastro', () {
    expect(redirect(Routes.home, session: loggedOut), Routes.login);
    expect(redirect(Routes.signUp, session: loggedOut), isNull);
  });

  test('sessão carregando mostra a splash', () {
    expect(
      redirect(Routes.login, session: const AsyncLoading()),
      Routes.splash,
    );
  });

  test('logado sem endereço vai para o cadastro de endereço', () {
    expect(redirect(Routes.login, session: loggedIn), Routes.onboardingAddress);
    expect(redirect(Routes.onboardingAddress, session: loggedIn), isNull);
  });

  test('logado com endereço vai para a home', () {
    expect(
      redirect(
        Routes.onboardingAddress,
        session: loggedIn,
        address: hasAddress,
      ),
      Routes.home,
    );
    expect(
      redirect(Routes.editAddress, session: loggedIn, address: hasAddress),
      isNull,
    );
  });

  test('login social sem tipo de perfil vai para completar cadastro', () {
    expect(
      redirect(Routes.login, session: loggedIn, profile: withoutRole),
      Routes.onboardingProfile,
    );
    expect(
      redirect(
        Routes.home,
        session: loggedIn,
        profile: withoutRole,
        address: hasAddress,
      ),
      Routes.onboardingProfile,
    );
    expect(
      redirect(
        Routes.onboardingProfile,
        session: loggedIn,
        profile: withoutRole,
      ),
      isNull,
    );
  });

  test('depois de escolher o perfil segue para o endereço', () {
    expect(
      redirect(Routes.onboardingProfile, session: loggedIn),
      Routes.onboardingAddress,
    );
  });

  test('perfil carregando mostra a splash', () {
    expect(
      redirect(Routes.login, session: loggedIn, profile: const AsyncLoading()),
      Routes.splash,
    );
  });

  test('erro ao carregar endereço mostra a splash', () {
    expect(
      redirect(
        Routes.home,
        session: loggedIn,
        address: AsyncError<Object?>('falha', StackTrace.empty),
      ),
      Routes.splash,
    );
  });
}
