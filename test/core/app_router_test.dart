import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sport_league/core/router/app_router.dart';
import 'package:sport_league/core/router/routes.dart';

void main() {
  const loggedIn = AsyncData<Object?>('session');
  const loggedOut = AsyncData<Object?>(null);
  const hasAddress = AsyncData<Object?>('address');
  const noAddress = AsyncData<Object?>(null);

  String? redirect(
    String location, {
    required AsyncValue<Object?> session,
    AsyncValue<Object?> address = noAddress,
  }) => appRedirect(location: location, session: session, address: address);

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
