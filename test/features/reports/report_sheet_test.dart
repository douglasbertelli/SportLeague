import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sport_league/core/utils/error_messages.dart';
import 'package:sport_league/features/reports/data/report_repository.dart';
import 'package:sport_league/features/reports/domain/content_report.dart';
import 'package:sport_league/features/reports/presentation/report_sheet.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeReportRepository implements ReportRepository {
  _FakeReportRepository({this.error});

  final Object? error;
  final sent =
      <
        ({
          ReportTarget target,
          String targetId,
          ReportReason reason,
          String? details,
        })
      >[];

  @override
  Future<void> report({
    required ReportTarget target,
    required String targetId,
    required ReportReason reason,
    String? details,
  }) async {
    if (error case final error?) throw error;
    sent.add((
      target: target,
      targetId: targetId,
      reason: reason,
      details: details,
    ));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Future<void> pumpMenu(WidgetTester tester, _FakeReportRepository fake) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [reportRepositoryProvider.overrideWithValue(fake)],
        child: MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              actions: const [
                ReportMenuButton(target: ReportTarget.team, targetId: 't1'),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Mais opções'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Denunciar o time'));
    await tester.pumpAndSettle();
  }

  Future<void> tapSend(WidgetTester tester) async {
    final send = find.text('Enviar denúncia');
    await tester.ensureVisible(send);
    await tester.tap(send);
    await tester.pumpAndSettle();
  }

  testWidgets('envia a denúncia com motivo e detalhes', (tester) async {
    final fake = _FakeReportRepository();
    await pumpMenu(tester, fake);

    // Sem motivo, não envia.
    await tapSend(tester);
    expect(find.text('Escolha o motivo da denúncia.'), findsOneWidget);
    expect(fake.sent, isEmpty);

    await tester.tap(find.text(ReportReason.spam.label));
    await tester.enterText(find.byType(TextField), 'Propaganda de aposta');
    await tapSend(tester);

    expect(fake.sent.single.target, ReportTarget.team);
    expect(fake.sent.single.targetId, 't1');
    expect(fake.sent.single.reason, ReportReason.spam);
    expect(fake.sent.single.details, 'Propaganda de aposta');
    expect(find.byType(ReportSheet), findsNothing);
    expect(find.textContaining('Denúncia enviada'), findsOneWidget);
  });

  testWidgets('falha mostra a mensagem e mantém a denúncia aberta', (
    tester,
  ) async {
    final fake = _FakeReportRepository(
      error: const PostgrestException(message: 'report_limit'),
    );
    await pumpMenu(tester, fake);

    await tester.tap(find.text(ReportReason.offensive.label));
    await tapSend(tester);

    expect(find.byType(ReportSheet), findsOneWidget);
    expect(find.textContaining('muitas denúncias hoje'), findsOneWidget);
  });

  test('conteúdo que sumiu tem mensagem própria', () {
    expect(
      friendlyErrorMessage(
        const PostgrestException(message: 'report_target_not_found'),
      ),
      'Esse conteúdo não existe mais.',
    );
  });
}
