import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sport_league/core/theme/app_theme.dart';
import 'package:sport_league/core/widgets/app_logo.dart';

void main() {
  for (final (name, theme) in [
    ('escuro', AppTheme.dark()),
    ('claro', AppTheme.light()),
  ]) {
    testWidgets('logo no tema $name usa a cor do texto', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Scaffold(body: Center(child: AppLogo())),
        ),
      );
      final logo = tester.widget<SvgPicture>(find.byType(SvgPicture));
      expect(logo.width, 150);
      expect(find.bySemanticsLabel('SportLeague'), findsOneWidget);
      // "Sport" e o símbolo seguem o texto do tema (brancos no escuro).
      final svgTheme = (logo.bytesLoader as SvgAssetLoader).theme!;
      expect(svgTheme.currentColor, theme.colorScheme.onSurface);
    });
  }
}
