import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sport_league/core/storage/preferences_provider.dart';
import 'package:sport_league/core/theme/app_color_picker.dart';
import 'package:sport_league/core/theme/app_color_provider.dart';
import 'package:sport_league/core/theme/app_theme.dart';

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
  test('28 cores, verde por padrão e a escolha fica salva', () async {
    expect(appColors, hasLength(28));
    expect({for (final color in appColors) color.id}, hasLength(28));

    var container = await _container();
    expect(container.read(appColorProvider).id, 'green');
    expect(container.read(appColorProvider), same(appColors.first));

    final blue = appColors.firstWhere((color) => color.id == 'blue');
    await container.read(appColorProvider.notifier).select(blue);
    expect(container.read(appColorProvider).name, 'Azul');

    // Reabrindo o app, a cor salva volta; uma inválida cai no verde.
    container = await _container({'app_color': 'blue'});
    expect(container.read(appColorProvider).id, 'blue');
    container = await _container({'app_color': 'nao-existe'});
    expect(container.read(appColorProvider).id, 'green');
  });

  test('cada time tem a sua cor', () async {
    SharedPreferences.setMockInitialValues({'app_color': 'blue'});
    final preferences = await SharedPreferences.getInstance();
    final team = StateProvider<({String id, String name})?>((ref) => null);
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        colorTeamProvider.overrideWith((ref) => ref.watch(team)),
      ],
    );
    addTearDown(container.dispose);
    AppColor byId(String id) => appColors.firstWhere((c) => c.id == id);
    String current() => container.read(appColorProvider).id;

    // Time sem cor própria usa a cor geral escolhida antes.
    container.read(team.notifier).state = (id: 'a', name: 'Time A');
    expect(current(), 'blue');
    await container.read(appColorProvider.notifier).select(byId('red'));

    container.read(team.notifier).state = (id: 'b', name: 'Time B');
    expect(current(), 'blue');
    await container.read(appColorProvider.notifier).select(byId('wine'));

    // Voltando ao A, a cor dele continua; a geral não mudou.
    container.read(team.notifier).state = (id: 'a', name: 'Time A');
    expect(current(), 'red');
    container.read(team.notifier).state = (id: 'b', name: 'Time B');
    expect(current(), 'wine');
    expect(preferences.getString('app_color'), 'blue');
    expect(preferences.getString('app_color.a'), 'red');
  });

  test('o tema claro e o escuro seguem a cor escolhida', () {
    final red = appColors.firstWhere((color) => color.id == 'red');
    expect(
      AppTheme.dark(color: red).colorScheme.primary,
      isNot(AppTheme.dark().colorScheme.primary),
    );
    expect(
      AppTheme.light(color: red).colorScheme.primary,
      isNot(AppTheme.light().colorScheme.primary),
    );
    // O cinza dos textos secundários não muda com a cor.
    expect(
      AppTheme.dark(color: red).colorScheme.onSurfaceVariant,
      AppTheme.dark().colorScheme.onSurfaceVariant,
    );
  });

  test('cinzas e preto ficam neutros e visíveis', () {
    AppColor byId(String id) => appColors.firstWhere((c) => c.id == id);
    bool isGrey(Color color) => color.r == color.g && color.g == color.b;
    final grey = byId('grey');
    final darkGrey = byId('darkgrey');
    final black = byId('black');

    for (final color in [grey, darkGrey, black]) {
      expect(color.isNeutral, isTrue);
      for (final theme in [
        AppTheme.light(color: color),
        AppTheme.dark(color: color),
      ]) {
        // Sem tom de cor nenhum (um preto puxando para o rosa, por exemplo).
        expect(isGrey(theme.colorScheme.primary), isTrue);
        // O destaque contrasta com o fundo.
        expect(
          ThemeData.estimateBrightnessForColor(theme.colorScheme.primary),
          isNot(theme.brightness),
        );
      }
    }
    // Os dois cinzas são diferentes entre si.
    expect(
      AppTheme.light(color: grey).colorScheme.primary,
      isNot(AppTheme.light(color: darkGrey).colorScheme.primary),
    );
    // Preto: no claro, destaque preto; no escuro, fundo preto e destaque
    // branco.
    expect(AppTheme.light(color: black).colorScheme.primary, Colors.black);
    expect(AppTheme.dark(color: black).colorScheme.surface, Colors.black);
    expect(AppTheme.dark(color: black).colorScheme.primary, Colors.white);
    expect(byId('red').isNeutral, isFalse);
  });

  testWidgets('Perfil: escolher a cor muda o app na hora', (tester) async {
    final container = await _container();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (context, ref, _) => MaterialApp(
            theme: AppTheme.dark(color: ref.watch(appColorProvider)),
            home: const Scaffold(body: AppColorTile()),
          ),
        ),
      ),
    );
    Color primary() =>
        Theme.of(tester.element(find.byType(AppColorTile))).colorScheme.primary;
    final greenPrimary = primary();
    expect(find.text('Verde'), findsOneWidget);

    await tester.tap(find.text('Cor do app'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Bordô'));
    await tester.pumpAndSettle();

    // Já aplicou, com a folha aberta.
    expect(find.text('Pronto · Bordô'), findsOneWidget);
    expect(primary(), isNot(greenPrimary));
    final preferences = container.read(sharedPreferencesProvider);
    expect(preferences.getString('app_color'), 'wine');

    await tester.tap(find.text('Pronto · Bordô'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Bordô'), findsOneWidget);
  });
}
