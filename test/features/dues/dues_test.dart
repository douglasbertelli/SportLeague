import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sport_league/core/supabase/supabase_providers.dart';
import 'package:sport_league/features/athletes/data/athlete_repository.dart';
import 'package:sport_league/features/athletes/domain/athlete.dart';
import 'package:sport_league/features/dues/data/dues_repository.dart';
import 'package:sport_league/features/dues/domain/team_dues.dart';
import 'package:sport_league/features/dues/presentation/dues_page.dart';
import 'package:sport_league/features/fundraisers/presentation/fundraisers_page.dart';
import 'package:sport_league/features/teams/data/team_repository.dart';
import 'package:sport_league/features/teams/domain/team.dart';

import '../teams/fakes.dart';

class FakeDuesRepository implements DuesRepository {
  FakeDuesRepository([this.dues]);

  TeamDues? dues;
  final payments = <String>{};
  var deleted = false;

  @override
  Future<TeamDues?> fetch(String teamId) async => dues;

  @override
  Future<void> save(TeamDues dues) async => this.dues = TeamDues(
    teamId: dues.teamId,
    amountCents: dues.amountCents,
    dueDay: dues.dueDay,
    pixKey: dues.toMap()['pix_key'] as String?,
    startMonth: this.dues?.startMonth ?? DateTime(2026, 11),
  );

  @override
  Future<void> delete(String teamId) async {
    dues = null;
    payments.clear();
    deleted = true;
  }

  @override
  Future<DuePayments> fetchPayments(String teamId) async => {...payments};

  @override
  Future<void> setPaid({
    required String teamId,
    required String athleteId,
    required DateTime month,
    required bool paid,
  }) async {
    final key = duePaymentKey(athleteId, month);
    paid ? payments.add(key) : payments.remove(key);
  }
}

const _team = Team(
  id: 'team-a',
  ownerId: 'u1',
  name: 'Amigos FC',
  modalities: {Modality.society},
);

final _athletes = FakeAthleteRepository({
  'team-a': const [
    Athlete(id: 'a1', teamId: 'team-a', name: 'Bruno Lima', jerseyNumber: 9),
    Athlete(
      id: 'a2',
      teamId: 'team-a',
      name: 'Caio Souza',
      jerseyNumber: 10,
      profileId: 'u2',
    ),
  ],
});

/// Mensalidade de R$ 50,00 que vence dia 10, cobrada desde outubro.
TeamDues _dues() => TeamDues(
  teamId: 'team-a',
  amountCents: 5000,
  dueDay: 10,
  pixKey: 'time@amigos.com',
  startMonth: DateTime(2026, 10),
);

Future<void> _pump(
  WidgetTester tester,
  FakeDuesRepository dues, {
  String userId = 'u1',
  DateTime? today,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.6;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserIdProvider.overrideWithValue(userId),
        duesRepositoryProvider.overrideWithValue(dues),
        athleteRepositoryProvider.overrideWithValue(_athletes),
        fundraiserTeamsProvider.overrideWith((ref) async => [_team]),
        selectedTeamProvider.overrideWith((ref) async => _team),
      ],
      child: MaterialApp(
        home: DuesPage(today: today ?? DateTime(2026, 11, 15)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));

  test('meses cobrados e atraso', () {
    final dues = _dues();
    expect(dues.monthsUntil(DateTime(2026, 11, 15)), [
      DateTime(2026, 10),
      DateTime(2026, 11),
    ]);
    // No dia do vencimento ainda não está atrasado.
    expect(dues.isLate(DateTime(2026, 11), DateTime(2026, 11, 10)), isFalse);
    expect(dues.isLate(DateTime(2026, 11), DateTime(2026, 11, 11)), isTrue);
    expect(formatMonth(DateTime(2026, 11)), 'Novembro de 2026');
  });

  testWidgets('o administrador configura a mensalidade', (tester) async {
    final repository = FakeDuesRepository();
    await _pump(tester, repository);
    expect(find.text('Sem mensalidade'), findsOneWidget);

    await tester.tap(find.text('Configurar mensalidade'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(find.text('Informe o valor'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Valor por mês'),
      '50',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Chave PIX (opcional)'),
      'time@amigos.com',
    );
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(repository.dues?.amountCents, 5000);
    expect(repository.dues?.dueDay, 10);
    expect(find.textContaining('50,00 por mês'), findsOneWidget);
    expect(find.text('Vence todo dia 10'), findsOneWidget);
  });

  testWidgets('o administrador marca quem pagou o mês', (tester) async {
    final repository = FakeDuesRepository(_dues());
    await _pump(tester, repository);

    expect(find.text('Novembro de 2026'), findsOneWidget);
    // Dia 15, depois do vencimento: quem não pagou está atrasado.
    expect(find.text('Atrasado'), findsNWidgets(2));
    expect(find.textContaining('100,00 · 0 de 2 pagaram'), findsOneWidget);

    await tester.tap(find.text('Bruno Lima'));
    await tester.pumpAndSettle();
    expect(repository.payments, {duePaymentKey('a1', DateTime(2026, 11))});
    expect(find.text('Pago'), findsOneWidget);
    expect(find.textContaining('100,00 · 1 de 2 pagaram'), findsOneWidget);

    // O mês anterior tem a sua lista.
    await tester.tap(find.byTooltip('Mês anterior'));
    await tester.pumpAndSettle();
    expect(find.text('Outubro de 2026'), findsOneWidget);
    expect(find.text('Pago'), findsNothing);
    expect(find.byTooltip('Mês anterior'), findsOneWidget);
    // Outubro é o primeiro mês: não volta mais.
    final previous = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.chevron_left),
    );
    expect(previous.onPressed, isNull);
  });

  testWidgets('o atleta vê os meses em atraso e copia o PIX', (tester) async {
    // Área de transferência do sistema, simulada.
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final repository = FakeDuesRepository(_dues())
      ..payments.add(duePaymentKey('a2', DateTime(2026, 10)));
    await _pump(tester, repository, userId: 'u2');

    // Pagou outubro; novembro passou do vencimento.
    expect(find.text('Você tem 1 mês em atraso'), findsOneWidget);
    expect(find.text('novembro'), findsOneWidget);
    // Só acompanha: sem as chaves de marcar nem o menu.
    expect(find.byType(Switch), findsNothing);
    expect(find.byTooltip('Ações da mensalidade'), findsNothing);
    expect(find.textContaining('Você'), findsWidgets);

    await tester.tap(find.byTooltip('Copiar chave PIX'));
    await tester.pumpAndSettle();
    expect(copied, 'time@amigos.com');
    expect(find.text('Chave PIX copiada'), findsOneWidget);
  });

  testWidgets('em dia antes do vencimento', (tester) async {
    final repository = FakeDuesRepository(_dues())
      ..payments.add(duePaymentKey('a2', DateTime(2026, 10)));
    await _pump(tester, repository, userId: 'u2', today: DateTime(2026, 11, 5));
    expect(find.text('Sua mensalidade está em dia'), findsOneWidget);
    expect(find.text('Em aberto'), findsNWidgets(2));
  });

  testWidgets('parar de cobrar', (tester) async {
    final repository = FakeDuesRepository(_dues());
    await _pump(tester, repository);
    await tester.tap(find.byTooltip('Ações da mensalidade'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Parar de cobrar'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Excluir'));
    await tester.pumpAndSettle();
    expect(repository.deleted, isTrue);
    expect(find.text('Sem mensalidade'), findsOneWidget);
  });
}
