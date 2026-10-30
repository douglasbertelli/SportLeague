import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sport_league/core/security/biometric_gate.dart';
import 'package:sport_league/core/security/biometric_tile.dart';
import 'package:sport_league/core/security/biometrics.dart';
import 'package:sport_league/core/storage/preferences_provider.dart';
import 'package:sport_league/core/supabase/supabase_providers.dart';
import 'package:sport_league/features/auth/data/auth_repository.dart';
import 'package:sport_league/features/auth/data/biometric_sign_in.dart';
import 'package:sport_league/features/auth/presentation/login_page.dart';
import 'package:sport_league/features/profile/data/profile_repository.dart';
import 'package:sport_league/features/profile/domain/profile.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeAuthRepository implements AuthRepository {
  var signedOut = 0;

  @override
  Future<void> signOut() async => signedOut++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Um botão que chama [action] com o `ref` (para os ajudantes de login).
Widget _button(String label, Future<void> Function(WidgetRef ref) action) =>
    Consumer(
      builder: (context, ref, _) => Scaffold(
        body: TextButton(onPressed: () => action(ref), child: Text(label)),
      ),
    );

AuthState _signedIn(String userId) => AuthState(
  AuthChangeEvent.signedIn,
  Session(
    accessToken: 'token',
    tokenType: 'bearer',
    user: User(
      id: userId,
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: '2026-10-30T00:00:00Z',
    ),
  ),
);

class _FakeBiometrics implements Biometrics {
  _FakeBiometrics({this.available = true, this.succeed = true});

  final bool available;
  bool succeed;
  var asked = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> authenticate(String reason) async {
    asked++;
    return succeed;
  }
}

Future<(ProviderContainer, SharedPreferences)> _pump(
  WidgetTester tester, {
  required _FakeBiometrics biometrics,
  Map<String, Object> preferences = const {},
  String? userId = 'u1',
  Widget? home,
  Duration relockAfter = const Duration(minutes: 1),
  Stream<AuthState> authEvents = const Stream.empty(),
  List<Override> overrides = const [],
}) async {
  SharedPreferences.setMockInitialValues(preferences);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      currentUserIdProvider.overrideWithValue(userId),
      biometricsProvider.overrideWithValue(biometrics),
      authEventsProvider.overrideWith((ref) => authEvents),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        builder: (context, child) =>
            BiometricGate(relockAfter: relockAfter, child: child!),
        home: home ?? const Scaffold(body: Text('Conteúdo do app')),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (container, prefs);
}

void main() {
  testWidgets('ligada: abre bloqueado e a biometria desbloqueia', (
    tester,
  ) async {
    final biometrics = _FakeBiometrics(succeed: false);
    await _pump(
      tester,
      biometrics: biometrics,
      preferences: {'biometric_lock': true},
    );
    // Pede sozinho ao abrir; cancelado, continua bloqueado.
    expect(biometrics.asked, 1);
    expect(find.text('SportLeague bloqueado'), findsOneWidget);

    biometrics.succeed = true;
    await tester.tap(find.text('Desbloquear'));
    await tester.pumpAndSettle();
    expect(biometrics.asked, 2);
    expect(find.text('SportLeague bloqueado'), findsNothing);
    expect(find.text('Conteúdo do app'), findsOneWidget);
  });

  testWidgets('desligada, ou sem conta, não bloqueia', (tester) async {
    final biometrics = _FakeBiometrics();
    await _pump(tester, biometrics: biometrics);
    expect(find.text('SportLeague bloqueado'), findsNothing);

    await _pump(
      tester,
      biometrics: biometrics,
      preferences: {'biometric_lock': true},
      userId: null,
    );
    expect(find.text('SportLeague bloqueado'), findsNothing);
    expect(biometrics.asked, 0);
  });

  testWidgets('bloqueia de novo ao voltar depois de um tempo fora', (
    tester,
  ) async {
    final biometrics = _FakeBiometrics();
    await _pump(
      tester,
      biometrics: biometrics,
      preferences: {'biometric_lock': true},
      relockAfter: Duration.zero,
    );
    expect(find.text('SportLeague bloqueado'), findsNothing);

    biometrics.succeed = false;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('SportLeague bloqueado'), findsOneWidget);
  });

  testWidgets('o item liga só depois de confirmar a biometria', (tester) async {
    final biometrics = _FakeBiometrics(succeed: false);
    final (container, _) = await _pump(
      tester,
      biometrics: biometrics,
      home: const Scaffold(body: BiometricTile()),
    );
    await tester.tap(find.text('Entrar com biometria'));
    await tester.pumpAndSettle();
    expect(container.read(biometricLockProvider), isFalse);

    biometrics.succeed = true;
    await tester.tap(find.text('Entrar com biometria'));
    await tester.pumpAndSettle();
    expect(container.read(biometricLockProvider), isTrue);
    // Ligar durante o uso não bloqueia na hora.
    expect(find.text('SportLeague bloqueado'), findsNothing);

    await tester.tap(find.text('Entrar com biometria'));
    await tester.pumpAndSettle();
    expect(container.read(biometricLockProvider), isFalse);
  });

  testWidgets('oferece uma vez depois de entrar', (tester) async {
    final biometrics = _FakeBiometrics();
    final (container, prefs) = await _pump(
      tester,
      biometrics: biometrics,
      home: Consumer(
        builder: (context, ref, _) => Scaffold(
          body: TextButton(
            onPressed: () => offerBiometrics(context, ref),
            child: const Text('Entrou'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Entrou'));
    await tester.pumpAndSettle();
    expect(find.text('Entrar com biometria?'), findsOneWidget);
    await tester.tap(find.text('Usar biometria'));
    await tester.pumpAndSettle();
    expect(container.read(biometricLockProvider), isTrue);

    // Já ligada (ou já oferecida): não pergunta de novo.
    await container.read(biometricLockProvider.notifier).set(false);
    await tester.tap(find.text('Entrou'));
    await tester.pumpAndSettle();
    expect(find.text('Entrar com biometria?'), findsNothing);
    expect(prefs.getBool(BiometricLock.offeredKey), isTrue);
  });

  testWidgets('sem biometria no aparelho, não oferece', (tester) async {
    await _pump(
      tester,
      biometrics: _FakeBiometrics(available: false),
      home: Consumer(
        builder: (context, ref, _) => Scaffold(
          body: TextButton(
            onPressed: () => offerBiometrics(context, ref),
            child: const Text('Entrou'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Entrou'));
    await tester.pumpAndSettle();
    expect(find.text('Entrar com biometria?'), findsNothing);
  });

  const ana = Profile(
    id: 'u1',
    fullName: 'Ana Souza',
    role: UserRole.player,
    plan: SubscriptionPlan.free,
  );

  testWidgets('Sair com a biometria ligada guarda a conta', (tester) async {
    final auth = _FakeAuthRepository();
    final (container, _) = await _pump(
      tester,
      biometrics: _FakeBiometrics(),
      preferences: {'biometric_lock': true},
      home: _button('Sair', signOutOrPark),
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        currentProfileProvider.overrideWithValue(const AsyncData(ana)),
      ],
    );
    await tester.tap(find.text('Sair'));
    await tester.pumpAndSettle();
    expect(auth.signedOut, 0);
    expect(container.read(biometricParkingProvider), (
      userId: 'u1',
      name: 'Ana Souza',
    ));
  });

  testWidgets('Sair sem a biometria sai de vez', (tester) async {
    final auth = _FakeAuthRepository();
    final (container, _) = await _pump(
      tester,
      biometrics: _FakeBiometrics(),
      home: _button('Sair', signOutOrPark),
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        currentProfileProvider.overrideWithValue(const AsyncData(ana)),
      ],
    );
    await tester.tap(find.text('Sair'));
    await tester.pumpAndSettle();
    expect(auth.signedOut, 1);
    expect(container.read(biometricParkingProvider), isNull);
  });

  testWidgets('login com a conta guardada: pede a biometria e dá para '
      'remover', (tester) async {
    final auth = _FakeAuthRepository();
    final biometrics = _FakeBiometrics(succeed: false);
    final (container, _) = await _pump(
      tester,
      biometrics: biometrics,
      userId: null,
      preferences: {
        'biometric_lock': true,
        'biometric_parked_user': 'u1',
        'biometric_parked_name': 'Ana',
      },
      home: const LoginPage(),
      overrides: [authRepositoryProvider.overrideWithValue(auth)],
    );
    // Já pede ao abrir; cancelado, fica na tela de login.
    expect(biometrics.asked, 1);
    // Só a biometria; o formulário fica em "Usar outra conta".
    expect(find.text('Olá, Ana'), findsOneWidget);
    expect(find.text('Entrar com biometria'), findsOneWidget);
    expect(find.text('E-mail'), findsNothing);

    await tester.tap(find.text('Usar outra conta'));
    await tester.pumpAndSettle();
    expect(find.text('E-mail'), findsOneWidget);
    expect(find.text('Google'), findsOneWidget);
    expect(find.text('Criar conta'), findsOneWidget);
    // E dá para voltar para a biometria.
    await tester.ensureVisible(find.text('Entrar como Ana'));
    await tester.tap(find.text('Entrar como Ana'));
    await tester.pumpAndSettle();
    expect(find.text('Olá, Ana'), findsOneWidget);

    await tester.ensureVisible(find.text('Remover biometria deste aparelho'));
    await tester.tap(find.text('Remover biometria deste aparelho'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remover'));
    await tester.pumpAndSettle();
    expect(auth.signedOut, 1);
    expect(container.read(biometricParkingProvider), isNull);
    expect(container.read(biometricLockProvider), isFalse);
    // Sem conta guardada, volta o formulário.
    expect(find.text('Olá, Ana'), findsNothing);
    expect(find.text('E-mail'), findsOneWidget);
  });

  testWidgets('entrar com outra conta esquece a guardada', (tester) async {
    final (container, _) = await _pump(
      tester,
      biometrics: _FakeBiometrics(),
      userId: null,
      preferences: {
        'biometric_lock': true,
        'biometric_parked_user': 'u1',
        'biometric_parked_name': 'Ana',
      },
      authEvents: Stream.value(_signedIn('u2')),
    );
    await tester.pumpAndSettle();
    expect(container.read(biometricParkingProvider), isNull);
    expect(container.read(biometricLockProvider), isFalse);
  });

  testWidgets('entrar com a senha da mesma conta mantém a biometria', (
    tester,
  ) async {
    final (container, _) = await _pump(
      tester,
      biometrics: _FakeBiometrics(),
      userId: null,
      preferences: {
        'biometric_lock': true,
        'biometric_parked_user': 'u1',
        'biometric_parked_name': 'Ana',
      },
      authEvents: Stream.value(_signedIn('u1')),
    );
    await tester.pumpAndSettle();
    expect(container.read(biometricParkingProvider), isNull);
    expect(container.read(biometricLockProvider), isTrue);
  });
}
