import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sport_league/core/media/picked_image.dart';
import 'package:sport_league/core/media/square_crop_page.dart';
import 'package:sport_league/core/storage/preferences_provider.dart';
import 'package:sport_league/core/supabase/supabase_providers.dart';
import 'package:sport_league/features/address/data/address_repository.dart';
import 'package:sport_league/features/games/data/player_stats_repository.dart';
import 'package:sport_league/features/games/domain/player_stats.dart';
import 'package:sport_league/features/profile/data/profile_repository.dart';
import 'package:sport_league/features/profile/domain/profile.dart';
import 'package:sport_league/features/profile/presentation/my_code_page.dart';
import 'package:sport_league/features/profile/presentation/profile_tab.dart';
import 'package:sport_league/features/profile/presentation/settings_tab.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../teams/fakes.dart';

class _FakeProfileRepository implements ProfileRepository {
  final uploaded = <String>[];
  final removed = <String>[];
  var regenerated = 0;
  String? renamed;

  @override
  Future<void> updateName(String userId, String fullName) async =>
      renamed = fullName;

  @override
  Future<String> regenerateCode() async {
    regenerated++;
    return 'JG9Z8Y7X';
  }

  @override
  Future<void> uploadPhoto(String userId, PickedImage image) async =>
      uploaded.add(userId);

  @override
  Future<void> removePhoto(String userId) async => removed.add(userId);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Profile _profile(UserRole role, {String? avatarUrl, String? code}) => Profile(
  id: 'u1',
  fullName: 'Ana Souza',
  role: role,
  plan: SubscriptionPlan.free,
  avatarUrl: avatarUrl,
  code: code,
);

Future<_FakeProfileRepository> _pump(
  WidgetTester tester,
  Profile profile, {
  List<MyTeamTotals> myTotals = const [],
  // Tela aberta no lugar da aba Perfil (ex.: Meu código).
  Widget? page,
}) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
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
        sharedPreferencesProvider.overrideWithValue(preferences),
        currentUserIdProvider.overrideWithValue('u1'),
        currentProfileProvider.overrideWith((ref) async => profile),
        myAddressProvider.overrideWith((ref) async => null),
        profileRepositoryProvider.overrideWithValue(profiles),
        playerStatsRepositoryProvider.overrideWithValue(
          FakePlayerStatsRepository(mine: myTotals),
        ),
        pickImageProvider.overrideWithValue(
          (source, {maxSize = smallImageSize}) async =>
              PickedImage(bytes: kTransparentImage, contentType: 'image/png'),
        ),
        cropSquareProvider.overrideWithValue((context, image) async => image),
      ],
      child: MaterialApp(
        home: page ?? Scaffold(body: ProfileTab(profile: profile)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return profiles;
}

void main() {
  testWidgets('o técnico envia a foto de perfil', (tester) async {
    final profiles = await _pump(tester, _profile(UserRole.coach));
    await tester.tap(find.bySemanticsLabel(RegExp('Adicionar foto')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Escolher da galeria'));
    await tester.pumpAndSettle();
    expect(profiles.uploaded, ['u1']);
  });

  testWidgets('Perfil do jogador: foto, nome e dados de atleta', (
    tester,
  ) async {
    await _pump(tester, _profile(UserRole.player, code: 'JG7K3M9Q'));
    expect(find.text('Ana Souza'), findsOneWidget);
    expect(find.text('Dados de atleta'), findsOneWidget);
    // Esses ficam na aba Config.
    expect(find.text('Meu código'), findsNothing);
    expect(find.text('Endereço'), findsNothing);
    expect(find.text('Sair'), findsNothing);

    await _pump(tester, _profile(UserRole.admin));
    expect(find.text('Dados de atleta'), findsNothing);
  });

  testWidgets('o jogador edita o próprio nome', (tester) async {
    final profiles = await _pump(tester, _profile(UserRole.player));
    await tester.tap(find.byTooltip('Editar nome'));
    await tester.pumpAndSettle();

    final field = find.widgetWithText(TextFormField, 'Nome');
    await tester.enterText(field, ' ');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(find.text('Informe o seu nome'), findsOneWidget);
    expect(profiles.renamed, isNull);

    await tester.enterText(field, '  Ana Paula Souza ');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(profiles.renamed, 'Ana Paula Souza');

    // O administrador e o técnico não têm o lápis.
    await _pump(tester, _profile(UserRole.admin));
    expect(find.byTooltip('Editar nome'), findsNothing);
  });

  testWidgets('Configurações: código, cor e endereço; o Sair por último', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    await _pump(
      tester,
      _profile(UserRole.player, code: 'JG7K3M9Q'),
      page: const Scaffold(body: SettingsTab()),
    );
    expect(
      find.text('JG7K3M9Q · para o administrador te convidar'),
      findsOneWidget,
    );
    // Jogador e técnico não têm plano.
    expect(find.text('Jogador'), findsOneWidget);
    expect(find.textContaining('Plano'), findsNothing);
    double top(String text) => tester.getTopLeft(find.text(text)).dy;
    expect(top('Meu código'), lessThan(top('Cor do app')));
    expect(top('Cor do app'), lessThan(top('Endereço')));
    expect(top('Endereço'), lessThan(top('Sair')));
    // Os três no mesmo card; o Sair em outro.
    final group = find.ancestor(
      of: find.text('Meu código'),
      matching: find.byType(Card),
    );
    expect(
      find.descendant(of: group, matching: find.text('Endereço')),
      findsOneWidget,
    );
    expect(find.descendant(of: group, matching: find.text('Sair')), findsNothing);
  });

  testWidgets('página Meu código do jogador: JG e gerar outro', (
    tester,
  ) async {
    final profiles = await _pump(
      tester,
      _profile(UserRole.player, code: 'JG7K3M9Q'),
      page: const MyCodePage(),
    );
    expect(find.text('JG7K3M9Q'), findsOneWidget);
    expect(find.textContaining('como jogador'), findsOneWidget);

    await tester.tap(find.text('Gerar outro'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gerar outro').last);
    await tester.pumpAndSettle();
    expect(profiles.regenerated, 1);
  });

  testWidgets('página Meu código do técnico: TC', (tester) async {
    await _pump(
      tester,
      _profile(UserRole.coach, code: 'TC2345AB'),
      page: const MyCodePage(),
    );
    expect(find.text('TC2345AB'), findsOneWidget);
    expect(find.textContaining('como técnico'), findsOneWidget);
  });

  testWidgets('o técnico remove a foto atual', (tester) async {
    final profiles = await _pump(
      tester,
      _profile(UserRole.coach, avatarUrl: 'http://localhost/foto.png'),
    );
    await tester.tap(find.bySemanticsLabel(RegExp('Trocar foto')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remover foto'));
    await tester.pumpAndSettle();
    expect(profiles.removed, ['u1']);
  });

  testWidgets('o jogador também envia a foto de perfil', (tester) async {
    final profiles = await _pump(tester, _profile(UserRole.player));
    await tester.tap(find.bySemanticsLabel(RegExp('Adicionar foto')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Escolher da galeria'));
    await tester.pumpAndSettle();
    expect(profiles.uploaded, ['u1']);
  });

  testWidgets('o administrador não troca a foto por aqui', (tester) async {
    await _pump(tester, _profile(UserRole.admin));
    expect(find.bySemanticsLabel(RegExp('Adicionar foto')), findsNothing);
    expect(find.text('Dados de atleta'), findsNothing);
    expect(find.text('Meus números'), findsNothing);
  });

  testWidgets('o jogador vê os dados de atleta no Perfil', (tester) async {
    final today = DateTime.now();
    await _pump(
      tester,
      Profile(
        id: 'u1',
        fullName: 'Ana Souza',
        role: UserRole.player,
        plan: SubscriptionPlan.free,
        preferredPosition: 'Meia',
        preferredFoot: PreferredFoot.left,
        heightCm: 178,
        birthDate: DateTime(today.year - 24, 1, 1),
      ),
    );
    expect(find.text('Meia'), findsOneWidget);
    expect(find.text('Esquerdo'), findsOneWidget);
    expect(find.text('1,78 m'), findsOneWidget);
    expect(find.textContaining('24 anos'), findsOneWidget);
    expect(find.text('Editar'), findsOneWidget);

    // Sem dados: cada linha avisa.
    await _pump(tester, _profile(UserRole.player));
    expect(find.text('Não informado'), findsNWidgets(4));
  });

  testWidgets('os números do jogador ficam no Início, não no Perfil', (
    tester,
  ) async {
    await _pump(tester, _profile(UserRole.player));
    expect(find.text('Dados de atleta'), findsOneWidget);
    expect(find.text('Meus números'), findsNothing);
  });

  test('a idade conta o aniversário do ano', () {
    final profile = Profile(
      id: 'u1',
      fullName: 'Ana Souza',
      plan: SubscriptionPlan.free,
      birthDate: DateTime(2000, 6, 15),
    );
    expect(profile.age(DateTime(2026, 6, 14)), 25);
    expect(profile.age(DateTime(2026, 6, 15)), 26);
  });
}

/// PNG 1x1 transparente.
final kTransparentImage = Uint8List.fromList([
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);
