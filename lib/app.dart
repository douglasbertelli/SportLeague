import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/security/biometric_gate.dart';
import 'core/theme/app_color_provider.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_mode_provider.dart';

class SportLeagueApp extends ConsumerWidget {
  const SportLeagueApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A cor escolhida em Perfil vale para o app inteiro.
    final color = ref.watch(appColorProvider);
    return MaterialApp.router(
      title: 'SportLeague',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(color: color),
      darkTheme: AppTheme.dark(color: color),
      themeMode: ref.watch(themeModeProvider),
      routerConfig: ref.watch(routerProvider),
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      // Com "Entrar com biometria" ligado, a digital ou o rosto desbloqueia.
      builder: (context, child) => BiometricGate(child: child!),
    );
  }
}
