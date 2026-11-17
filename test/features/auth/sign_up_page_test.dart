import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sport_league/features/auth/data/auth_repository.dart';
import 'package:sport_league/features/auth/presentation/sign_up_page.dart';

class _FakeAuthRepository implements AuthRepository {
  ({String fullName, String email, String password})? signedUp;

  @override
  Future<bool> signUp({
    required String fullName,
    required String email,
    required String password,
  }) async {
    signedUp = (fullName: fullName, email: email, password: password);
    return false;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('cadastra só com nome, e-mail e senha, sem escolher perfil', (
    tester,
  ) async {
    final fake = _FakeAuthRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(fake)],
        child: const MaterialApp(home: SignUpPage()),
      ),
    );

    expect(find.text('Tipo de perfil'), findsNothing);

    final fields = find.byType(TextFormField);
    expect(fields, findsNWidgets(4));
    await tester.enterText(fields.at(0), 'João Silva');
    await tester.enterText(fields.at(1), 'joao@time.com');
    await tester.enterText(fields.at(2), 'Senha@1234');
    await tester.enterText(fields.at(3), 'Senha@1234');

    final submit = find.text('Cadastrar');
    await tester.ensureVisible(submit);

    // Sem o aceite dos Termos, não cadastra.
    await tester.tap(submit);
    await tester.pump();
    expect(fake.signedUp, isNull);
    expect(find.textContaining('Aceite os Termos'), findsOneWidget);

    await tester.ensureVisible(find.byType(Checkbox));
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pump();

    expect(fake.signedUp?.fullName, 'João Silva');
    expect(fake.signedUp?.email, 'joao@time.com');
    expect(fake.signedUp?.password, 'Senha@1234');
  });

  testWidgets('senha fraca não cadastra e a lista mostra o que falta', (
    tester,
  ) async {
    final fake = _FakeAuthRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(fake)],
        child: const MaterialApp(home: SignUpPage()),
      ),
    );

    expect(find.text('Força da senha'), findsOneWidget);

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'João Silva');
    await tester.enterText(fields.at(1), 'joao@time.com');
    await tester.enterText(fields.at(2), 'senha1234');
    await tester.enterText(fields.at(3), 'senha1234');
    await tester.pump();
    expect(find.text('Média'), findsOneWidget);

    await tester.ensureVisible(find.byType(Checkbox));
    await tester.tap(find.byType(Checkbox));
    final submit = find.text('Cadastrar');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pump();

    expect(
      find.text('A senha precisa ter: uma letra maiúscula.'),
      findsOneWidget,
    );
    expect(fake.signedUp, isNull);

    // Com o e-mail dentro da senha, também não.
    await tester.enterText(fields.at(2), 'Joao@2024x');
    await tester.pump();
    expect(find.text('Não use o seu e-mail na senha'), findsOneWidget);
  });

  testWidgets('senhas diferentes não cadastram', (tester) async {
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
    await tester.enterText(fields.at(3), 'outra1234');

    final submit = find.text('Cadastrar');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pump();

    expect(find.text('As senhas não conferem'), findsOneWidget);
    expect(fake.signedUp, isNull);
  });
}
