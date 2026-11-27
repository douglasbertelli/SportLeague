import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sport_league/core/router/app_router.dart';
import 'package:sport_league/core/router/routes.dart';
import 'package:sport_league/features/app_update/data/app_update.dart';
import 'package:sport_league/features/legal/presentation/legal_page.dart';
import 'package:sport_league/features/profile/domain/profile.dart';

/// Versão mínima do app (Etapa 0 da Fase 2).
void main() {
  test('abaixo do mínimo precisa atualizar; igual ou acima, não', () {
    expect(isUpdateRequired(currentBuild: 7, minBuild: 8), isTrue);
    expect(isUpdateRequired(currentBuild: 8, minBuild: 8), isFalse);
    expect(isUpdateRequired(currentBuild: 9, minBuild: 8), isFalse);
    expect(isUpdateRequired(currentBuild: 7, minBuild: 0), isFalse);
  });

  group('provider', () {
    ProviderContainer container({MinVersion? min, int? current}) {
      final c = ProviderContainer(
        overrides: [
          minVersionProvider.overrideWith((_) async => min),
          currentBuildProvider.overrideWith((_) async => current),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    Future<bool> required(ProviderContainer c) async {
      await c.read(minVersionProvider.future);
      await c.read(currentBuildProvider.future);
      return c.read(updateRequiredProvider);
    }

    test('bloqueia só com o build instalado abaixo do mínimo', () async {
      expect(
        await required(
          container(min: (minBuild: 8, storeUrl: null), current: 7),
        ),
        isTrue,
      );
      expect(
        await required(
          container(min: (minBuild: 8, storeUrl: null), current: 8),
        ),
        isFalse,
      );
    });

    test('sem informação, nunca bloqueia', () async {
      expect(await required(container(current: 7)), isFalse);
      expect(
        await required(container(min: (minBuild: 8, storeUrl: null))),
        isFalse,
      );
    });
  });

  group('rotas', () {
    const loggedIn = AsyncData<Object?>('session');
    const loggedOut = AsyncData<Object?>(null);
    final profile = AsyncData<Profile?>(
      Profile(
        id: 'u1',
        fullName: 'Ana Souza',
        role: UserRole.player,
        plan: SubscriptionPlan.free,
        termsAcceptedAt: legalVersion,
      ),
    );
    const address = AsyncData<Object?>('address');

    String? redirect(
      String location, {
      AsyncValue<Object?> session = loggedIn,
      bool updateRequired = false,
    }) => appRedirect(
      location: location,
      session: session,
      profile: profile,
      address: address,
      updateRequired: updateRequired,
    );

    test('precisando atualizar, tudo leva à tela de atualizar', () {
      for (final location in [Routes.home, Routes.login, Routes.splash]) {
        expect(redirect(location, updateRequired: true), Routes.updateRequired);
        expect(
          redirect(location, session: loggedOut, updateRequired: true),
          Routes.updateRequired,
        );
      }
      expect(redirect(Routes.updateRequired, updateRequired: true), isNull);
    });

    test('os documentos legais continuam abertos', () {
      expect(redirect(Routes.terms, updateRequired: true), isNull);
      expect(redirect(Routes.privacy, updateRequired: true), isNull);
    });

    test('depois de atualizar, a tela de atualizar sai', () {
      expect(redirect(Routes.updateRequired), Routes.home);
      expect(redirect(Routes.updateRequired, session: loggedOut), Routes.login);
    });
  });
}
