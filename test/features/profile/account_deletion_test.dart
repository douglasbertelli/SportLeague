import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sport_league/features/profile/domain/profile.dart';
import 'package:sport_league/features/profile/presentation/account_deletion.dart';

void main() {
  Future<void> pump(WidgetTester tester, Profile profile) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: DeleteAccountButton(profile: profile)),
        ),
      ),
    );
    await tester.tap(find.text('Excluir conta'));
    await tester.pumpAndSettle();
  }

  FilledButton confirmButton(WidgetTester tester) =>
      tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Excluir minha conta'),
          matching: find.byWidgetPredicate((w) => w is FilledButton),
        ),
      );

  testWidgets('avisa que é irreversível e pede para digitar EXCLUIR', (
    tester,
  ) async {
    await pump(
      tester,
      const Profile(
        id: 'u1',
        fullName: 'Ana Souza',
        role: UserRole.admin,
        plan: SubscriptionPlan.free,
      ),
    );
    expect(find.text('Excluir conta?'), findsOneWidget);
    expect(find.textContaining('Esta ação é irreversível'), findsOneWidget);
    expect(find.textContaining('não há como recuperar'), findsOneWidget);
    expect(find.textContaining('inativa por 7 dias'), findsOneWidget);
    // Administrador: os times entram na lista do que é apagado.
    expect(find.textContaining('Seus times'), findsOneWidget);

    expect(confirmButton(tester).onPressed, isNull);
    await tester.enterText(find.byType(TextField), 'excluir');
    await tester.pump();
    expect(confirmButton(tester).onPressed, isNotNull);
  });

  testWidgets('jogador: os times continuam, sem ele', (tester) async {
    await pump(
      tester,
      const Profile(
        id: 'u2',
        fullName: 'Caio',
        role: UserRole.player,
        plan: SubscriptionPlan.free,
      ),
    );
    expect(find.textContaining('Seus times'), findsNothing);
    expect(find.textContaining('o time continua'), findsOneWidget);
  });
}
