import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sport_league/core/storage/preferences_provider.dart';
import 'package:sport_league/core/supabase/supabase_providers.dart';
import 'package:sport_league/core/theme/app_theme.dart';
import 'package:sport_league/features/address/data/address_repository.dart';
import 'package:sport_league/features/address/domain/address.dart';
import 'package:sport_league/features/home/presentation/home_page.dart';
import 'package:sport_league/features/profile/data/profile_repository.dart';
import 'package:sport_league/features/profile/domain/profile.dart';
import 'package:sport_league/features/athletes/data/athlete_repository.dart';
import 'package:sport_league/features/games/data/game_repository.dart';
import 'package:sport_league/features/teams/data/team_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../teams/fakes.dart';

Future<void> _pumpHome(WidgetTester tester, UserRole role) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        currentUserIdProvider.overrideWithValue('u1'),
        teamRepositoryProvider.overrideWithValue(FakeTeamRepository([teamA])),
        athleteRepositoryProvider.overrideWithValue(FakeAthleteRepository({})),
        gameRepositoryProvider.overrideWithValue(FakeGameRepository({})),
        supabaseClientProvider.overrideWithValue(
          SupabaseClient(
            'http://localhost',
            'anon-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
        ),
        currentProfileProvider.overrideWithValue(
          AsyncData(
            Profile(
              id: 'u1',
              fullName: 'Ana Souza',
              role: role,
              plan: SubscriptionPlan.free,
            ),
          ),
        ),
        myAddressProvider.overrideWithValue(
          const AsyncData(
            Address(
              profileId: 'u1',
              zipCode: '01310100',
              street: 'Avenida Paulista',
              number: '1000',
              neighborhood: 'Bela Vista',
              city: 'São Paulo',
              state: 'SP',
            ),
          ),
        ),
      ],
      child: MaterialApp(theme: AppTheme.dark(), home: const HomePage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'administrador navega pelas abas Início, Jogos, Atletas e Perfil',
    (tester) async {
      await _pumpHome(tester, UserRole.admin);

      final bar = find.byType(NavigationBar);
      expect(bar, findsOneWidget);
      for (final label in ['Início', 'Jogos', 'Atletas', 'Perfil']) {
        expect(
          find.descendant(of: bar, matching: find.text(label)),
          findsOneWidget,
        );
      }
      expect(find.text('Olá, Ana!'), findsOneWidget);
      // O título mostra o time ativo.
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Amigos FC'),
        ),
        findsOneWidget,
      );
      // Painel do time no Início: próximo jogo e estatísticas.
      expect(find.text('Nenhum amistoso marcado.'), findsOneWidget);
      expect(find.text('Marcar amistoso'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('1 time'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Vitórias'), findsOneWidget);
      expect(find.text('Atalhos'), findsOneWidget);

      await tester.tap(find.descendant(of: bar, matching: find.text('Jogos')));
      await tester.pumpAndSettle();
      expect(find.text('Nenhum amistoso marcado'), findsOneWidget);

      await tester.tap(
        find.descendant(of: bar, matching: find.text('Atletas')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Nenhum atleta neste time'), findsOneWidget);

      await tester.tap(find.descendant(of: bar, matching: find.text('Perfil')));
      await tester.pumpAndSettle();
      expect(find.text('Ana Souza'), findsOneWidget);
      expect(
        find.text('Avenida Paulista, 1000 - São Paulo/SP'),
        findsOneWidget,
      );
      expect(find.text('Sair'), findsOneWidget);
    },
  );

  testWidgets('jogador continua sem a barra inferior', (tester) async {
    await _pumpHome(tester, UserRole.player);

    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Olá, Ana!'), findsOneWidget);
    expect(find.text('Buscar times'), findsOneWidget);
  });
}
