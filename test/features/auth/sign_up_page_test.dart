import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sport_league/features/auth/data/auth_repository.dart';
import 'package:sport_league/features/auth/presentation/sign_up_page.dart';
import 'package:sport_league/features/profile/domain/profile.dart';

class _FakeAuthRepository implements AuthRepository {
  UserRole? signedUpRole;

  @override
  Future<bool> signUp({
    required String fullName,
    required String email,
    required String password,
    required UserRole role,
  }) async {
    signedUpRole = role;
    return false;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('exige a escolha do perfil e envia o perfil escolhido', (
    tester,
  ) async {
    final fake = _FakeAuthRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(fake)],
        child: const MaterialApp(home: SignUpPage()),
      ),
    );

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'João Silva');
    await tester.enterText(fields.at(1), 'joao@time.com');
    await tester.enterText(fields.at(2), 'senha1234');
    await tester.enterText(fields.at(3), 'senha1234');

    final submit = find.text('Cadastrar');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pump();
    expect(find.text('Escolha o tipo de perfil'), findsOneWidget);
    expect(fake.signedUpRole, isNull);

    await tester.ensureVisible(find.text('Jogador'));
    await tester.tap(find.text('Jogador'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pump();

    expect(fake.signedUpRole, UserRole.player);
  });
}
