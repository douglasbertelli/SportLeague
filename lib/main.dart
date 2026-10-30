import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/env.dart';
import 'core/security/secure_session_storage.dart';
import 'core/storage/preferences_provider.dart';
import 'core/supabase/supabase_providers.dart';
import 'core/theme/app_color_provider.dart';
import 'core/theme/app_theme.dart';
import 'features/profile/data/profile_repository.dart';
import 'features/teams/data/team_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Nomes de meses e dias em português no calendário de disponibilidade.
  await initializeDateFormatting('pt_BR');

  if (!Env.isConfigured) {
    runApp(const _MissingConfigApp());
    return;
  }

  await Supabase.initialize(
    url: Env.supabaseUrl,
    publishableKey: Env.supabaseAnonKey,
    // A sessão fica no cofre do aparelho, não nas preferências comuns.
    authOptions: FlutterAuthClientOptions(
      localStorage: SecureSessionStorage(supabaseUrl: Env.supabaseUrl),
    ),
  );

  final preferences = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        // Antes de entrar, o verde da marca.
        signedOutProvider.overrideWith(
          (ref) => ref.watch(currentUserIdProvider) == null,
        ),
        // O técnico usa os times em que está, não os que criou.
        isCoachProvider.overrideWith(
          (ref) => ref.watch(currentProfileProvider).value?.isCoach ?? false,
        ),
        // O jogador acompanha os times em que é atleta.
        isPlayerProvider.overrideWith(
          (ref) => ref.watch(currentProfileProvider).value?.isPlayer ?? false,
        ),
        // Cada time tem a sua cor.
        colorTeamProvider.overrideWith((ref) {
          final team = ref.watch(selectedTeamProvider).value;
          return team?.id == null ? null : (id: team!.id!, name: team.name);
        }),
      ],
      child: const SportLeagueApp(),
    ),
  );
}

class _MissingConfigApp extends StatelessWidget {
  const _MissingConfigApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      home: const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Supabase não configurado.\n\n'
              'Execute com:\nflutter run --dart-define-from-file=env.json',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
