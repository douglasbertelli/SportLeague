import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sport_league/core/router/app_router.dart';
import 'package:sport_league/core/router/routes.dart';
import 'package:sport_league/features/legal/presentation/legal_page.dart';
import 'package:sport_league/features/profile/domain/profile.dart';

void main() {
  const loggedIn = AsyncData<Object?>('session');
  const loggedOut = AsyncData<Object?>(null);
  const hasAddress = AsyncData<Object?>('address');
  const noAddress = AsyncData<Object?>(null);
  final withRole = AsyncData<Profile?>(
    Profile(
      id: 'u1',
      fullName: 'Ana Souza',
      role: UserRole.player,
      plan: SubscriptionPlan.free,
      termsAcceptedAt: legalVersion,
    ),
  );
  const withoutRole = AsyncData<Profile?>(
    Profile(id: 'u1', fullName: 'Ana Souza', plan: SubscriptionPlan.free),
  );

  String? redirect(
    String location, {
    required AsyncValue<Object?> session,
    AsyncValue<Profile?>? profile,
    AsyncValue<Object?> address = noAddress,
  }) => appRedirect(
    location: location,
    session: session,
    profile: profile ?? withRole,
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

  test('técnico não abre o cadastro de time', () {
    final coach = AsyncData<Profile?>(
      Profile(
        id: 'u1',
        fullName: 'Ana Souza',
        role: UserRole.coach,
        plan: SubscriptionPlan.free,
        termsAcceptedAt: legalVersion,
      ),
    );
    final admin = AsyncData<Profile?>(
      Profile(
        id: 'u1',
        fullName: 'Ana Souza',
        role: UserRole.admin,
        plan: SubscriptionPlan.free,
        termsAcceptedAt: legalVersion,
      ),
    );
    expect(
      redirect(
        Routes.newTeam,
        session: loggedIn,
        profile: coach,
        address: hasAddress,
      ),
      Routes.home,
    );
    expect(
      redirect(
        Routes.newTeam,
        session: loggedIn,
        profile: admin,
        address: hasAddress,
      ),
      isNull,
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

  test('conta marcada para exclusão só reativa ou sai', () {
    final inactive = AsyncData<Profile?>(
      Profile(
        id: 'u1',
        fullName: 'Ana Souza',
        role: UserRole.player,
        plan: SubscriptionPlan.free,
        deletedAt: DateTime(2026, 11, 8),
      ),
    );
    for (final location in [Routes.home, Routes.splash, Routes.teams]) {
      expect(
        redirect(
          location,
          session: loggedIn,
          profile: inactive,
          address: hasAddress,
        ),
        Routes.accountInactive,
      );
    }
    expect(
      redirect(
        Routes.accountInactive,
        session: loggedIn,
        profile: inactive,
        address: hasAddress,
      ),
      isNull,
    );
    // Reativada: sai da tela de conta inativa para o início.
    expect(
      redirect(Routes.accountInactive, session: loggedIn, address: hasAddress),
      Routes.home,
    );
    expect(inactive.value!.deletionDate, DateTime(2026, 11, 15));
  });

  test('sem o aceite da versão atual, pede os Termos e a Política', () {
    final old = AsyncData<Profile?>(
      Profile(
        id: 'u1',
        fullName: 'Ana Souza',
        role: UserRole.player,
        plan: SubscriptionPlan.free,
        termsAcceptedAt: legalVersion.subtract(const Duration(days: 1)),
      ),
    );
    const never = AsyncData<Profile?>(
      Profile(
        id: 'u1',
        fullName: 'Ana Souza',
        role: UserRole.player,
        plan: SubscriptionPlan.free,
      ),
    );
    for (final profile in [old, never]) {
      expect(
        redirect(
          Routes.home,
          session: loggedIn,
          profile: profile,
          address: hasAddress,
        ),
        Routes.acceptTerms,
      );
    }
    // Os documentos abrem mesmo antes do aceite (e sem login).
    expect(redirect(Routes.terms, session: loggedIn, profile: never), isNull);
    expect(redirect(Routes.privacy, session: loggedOut), isNull);
    // Aceitou: sai da tela de aceite.
    expect(
      redirect(Routes.acceptTerms, session: loggedIn, address: hasAddress),
      Routes.home,
    );
  });
}
