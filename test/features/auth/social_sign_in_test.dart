import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sport_league/core/supabase/supabase_providers.dart';
import 'package:sport_league/core/utils/error_messages.dart';
import 'package:sport_league/features/auth/data/auth_repository.dart';
import 'package:sport_league/features/auth/presentation/complete_profile_page.dart';
import 'package:sport_league/features/auth/presentation/social_sign_in_buttons.dart';
import 'package:sport_league/features/profile/data/profile_repository.dart';
import 'package:sport_league/features/profile/domain/profile.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository({this.googleError});

  final Object? googleError;
  final calls = <String>[];

  @override
  Future<bool> signInWithGoogle() async {
    calls.add('google');
    if (googleError case final error?) throw error;
    return true;
  }

  @override
  Future<bool> signInWithApple() async {
    calls.add('apple');
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProfileRepository implements ProfileRepository {
  ({String userId, UserRole role, String? fullName})? completed;

  @override
  Future<void> completeProfile({
    required String userId,
    required UserRole role,
    String? fullName,
  }) async {
    completed = (userId: userId, role: role, fullName: fullName);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('perfil sem role vindo do login social', () {
    final profile = Profile.fromMap({
      'id': 'u1',
      'full_name': 'Ana Souza',
      'role': null,
      'plan': 'free',
    });
    expect(profile.role, isNull);
    expect(profile.needsRole, isTrue);
    expect(profile.isAdmin, isFalse);
  });

  test('erro do Google vira mensagem amigável', () {
    const error = GoogleSignInException(
      code: GoogleSignInExceptionCode.unknownError,
    );
    expect(friendlyErrorMessage(error), contains('entrar com o Google'));
  });

  testWidgets('botões chamam o login do provedor escolhido', (tester) async {
    final fake = _FakeAuthRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(fake)],
        child: const MaterialApp(home: Scaffold(body: SocialSignInButtons())),
      ),
    );

    await tester.tap(find.text('Continuar com Google'));
    await tester.pump();
    await tester.tap(find.text('Continuar com Apple'));
    await tester.pump();

    expect(fake.calls, ['google', 'apple']);
  });

  testWidgets('falha no login social mostra a mensagem', (tester) async {
    final fake = _FakeAuthRepository(
      googleError: const AuthException(
        'Login com Google não configurado neste app.',
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(fake)],
        child: const MaterialApp(home: Scaffold(body: SocialSignInButtons())),
      ),
    );

    await tester.tap(find.text('Continuar com Google'));
    await tester.pump();

    expect(
      find.text('Login com Google não configurado neste app.'),
      findsOneWidget,
    );
  });

  Future<_FakeProfileRepository> pumpChooseProfile(
    WidgetTester tester, {
    required String fullName,
  }) async {
    final profiles = _FakeProfileRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          supabaseClientProvider.overrideWithValue(
            SupabaseClient(
              'http://localhost',
              'anon-key',
              authOptions: const AuthClientOptions(autoRefreshToken: false),
            ),
          ),
          currentUserIdProvider.overrideWithValue('u1'),
          currentProfileProvider.overrideWithValue(
            AsyncData(
              Profile(
                id: 'u1',
                fullName: fullName,
                plan: SubscriptionPlan.free,
              ),
            ),
          ),
          profileRepositoryProvider.overrideWithValue(profiles),
        ],
        child: const MaterialApp(home: CompleteProfilePage()),
      ),
    );
    return profiles;
  }

  Future<void> tapContinue(WidgetTester tester) async {
    final submit = find.text('Continuar');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pump();
  }

  testWidgets('escolha de perfil exige o perfil e não pede o nome de novo', (
    tester,
  ) async {
    final profiles = await pumpChooseProfile(tester, fullName: 'Ana Souza');

    expect(find.byType(TextFormField), findsNothing);

    await tapContinue(tester);
    expect(find.text('Escolha o tipo de perfil'), findsOneWidget);
    expect(profiles.completed, isNull);

    await tester.ensureVisible(find.text('Administrador'));
    await tester.tap(find.text('Administrador'));
    await tapContinue(tester);

    expect(profiles.completed?.userId, 'u1');
    expect(profiles.completed?.role, UserRole.admin);
    expect(profiles.completed?.fullName, isNull);
  });

  testWidgets('pede o nome quando o cadastro não trouxe um', (tester) async {
    final profiles = await pumpChooseProfile(
      tester,
      fullName: Profile.placeholderName,
    );

    await tester.enterText(find.byType(TextFormField), 'Bruno Lima');
    await tester.ensureVisible(find.text('Jogador'));
    await tester.tap(find.text('Jogador'));
    await tapContinue(tester);

    expect(profiles.completed?.role, UserRole.player);
    expect(profiles.completed?.fullName, 'Bruno Lima');
  });
}
