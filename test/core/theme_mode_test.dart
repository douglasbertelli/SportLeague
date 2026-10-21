import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sport_league/core/storage/preferences_provider.dart';
import 'package:sport_league/core/theme/theme_mode_provider.dart';
import 'package:sport_league/core/widgets/theme_mode_button.dart';

Future<ProviderContainer> _container([
  Map<String, Object> saved = const {},
]) async {
  SharedPreferences.setMockInitialValues(saved);
  final preferences = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('sem preferência salva o tema é escuro', () async {
    final container = await _container();
    expect(container.read(themeModeProvider), ThemeMode.dark);
  });

  test('usa o tema salvo e ignora valores inválidos', () async {
    var container = await _container({'theme_mode': 'light'});
    expect(container.read(themeModeProvider), ThemeMode.light);

    container = await _container({'theme_mode': 'roxo'});
    expect(container.read(themeModeProvider), ThemeMode.dark);
  });

  test('salva o tema escolhido', () async {
    final container = await _container();
    await container.read(themeModeProvider.notifier).setMode(ThemeMode.light);

    expect(container.read(themeModeProvider), ThemeMode.light);
    final preferences = container.read(sharedPreferencesProvider);
    expect(preferences.getString('theme_mode'), 'light');
  });

  testWidgets('o botão troca o tema do app', (tester) async {
    final container = await _container();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (context, ref, _) => MaterialApp(
            theme: ThemeData(brightness: Brightness.light),
            darkTheme: ThemeData(brightness: Brightness.dark),
            themeMode: ref.watch(themeModeProvider),
            home: Scaffold(appBar: AppBar(actions: const [ThemeModeButton()])),
          ),
        ),
      ),
    );

    BuildContext appContext() => tester.element(find.byType(AppBar));
    expect(Theme.of(appContext()).brightness, Brightness.dark);

    await tester.tap(find.byTooltip('Tema'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Claro'));
    await tester.pumpAndSettle();

    expect(find.text('Claro'), findsNothing);
    expect(Theme.of(appContext()).brightness, Brightness.light);
    expect(container.read(themeModeProvider), ThemeMode.light);
  });
}
