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
import 'package:sport_league/features/profile/presentation/profile_tab.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../teams/fakes.dart';

class _FakeProfileRepository implements ProfileRepository {
  final uploaded = <String>[];
  final removed = <String>[];

  @override
  Future<void> uploadPhoto(String userId, PickedImage image) async =>
      uploaded.add(userId);

  @override
  Future<void> removePhoto(String userId) async => removed.add(userId);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Profile _profile(UserRole role, {String? avatarUrl}) => Profile(
  id: 'u1',
  fullName: 'Ana Souza',
  role: role,
  plan: SubscriptionPlan.free,
  avatarUrl: avatarUrl,
);

Future<_FakeProfileRepository> _pump(
  WidgetTester tester,
  Profile profile, {
  List<MyTeamTotals> myTotals = const [],
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
        home: Scaffold(body: ProfileTab(profile: profile)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return profiles;
}

void main() {
  testWidgets('o tÃ©cnico envia a foto de perfil', (tester) async {
    final profiles = await _pump(tester, _profile(UserRole.coach));
    await tester.tap(find.bySemanticsLabel(RegExp('Adicionar foto')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Escolher da galeria'));
    await tester.pumpAndSettle();
    expect(profiles.uploaded, ['u1']);
  });

  testWidgets('o tÃ©cnico remove a foto atual', (tester) async {
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

  testWidgets('o jogador vê o resumo dos dados de atleta', (tester) async {
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
    expect(find.text('Meia · Pé esquerdo · 1,78 m · 24 anos'), findsOneWidget);
  });

  testWidgets('o jogador vê os números somados e por time', (tester) async {
    await _pump(
      tester,
      _profile(UserRole.player),
      myTotals: const [
        MyTeamTotals(
          teamId: 't1',
          teamName: 'Amigos FC',
          totals: AthleteTotals(
            athleteId: 'a1',
            name: 'Amigos FC',
            jerseyNumber: 10,
            games: 3,
            goals: 4,
          ),
        ),
        MyTeamTotals(
          teamId: 't2',
          teamName: 'Unidos',
          totals: AthleteTotals(
            athleteId: 'a2',
            name: 'Unidos',
            games: 2,
            goals: 1,
          ),
        ),
      ],
    );
    expect(find.text('Meus números'), findsOneWidget);
    // Soma: 5 jogos e 5 gols.
    expect(find.text('5'), findsNWidgets(2));
    await tester.scrollUntilVisible(find.text('Unidos'), 200);
    expect(find.text('Amigos FC'), findsOneWidget);
    expect(find.text('Nº 10'), findsOneWidget);
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
