import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sport_league/features/auth/data/auth_repository.dart';
import 'package:sport_league/features/auth/presentation/forgot_password_page.dart';

class _FakeAuthRepository implements AuthRepository {
  final sent = <String>[];

  @override
  Future<void> sendPasswordReset(String email) async => sent.add(email);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<_FakeAuthRepository> _pump(WidgetTester tester, {String? email}) async {
  final auth = _FakeAuthRepository();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(auth)],
      child: MaterialApp(home: ForgotPasswordPage(email: email)),
    ),
  );
  await tester.pumpAndSettle();
  return auth;
}

void main() {
  testWidgets('vem com o e-mail do login e manda o link', (tester) async {
    final auth = await _pump(tester, email: 'ana@exemplo.com');
    expect(find.text('ana@exemplo.com'), findsOneWidget);

    await tester.tap(find.text('Enviar link'));
    await tester.pumpAndSettle();

    expect(auth.sent, ['ana@exemplo.com']);
    expect(find.text('Confira o seu e-mail'), findsOneWidget);
    expect(find.textContaining('ana@exemplo.com'), findsOneWidget);
    expect(find.text('Voltar para entrar'), findsOneWidget);
  });

  testWidgets('e-mail inválido não manda nada', (tester) async {
    final auth = await _pump(tester);
    await tester.enterText(find.byType(TextFormField), 'ana');
    await tester.tap(find.text('Enviar link'));
    await tester.pumpAndSettle();

    expect(auth.sent, isEmpty);
    expect(find.text('Confira o seu e-mail'), findsNothing);
  });
}
