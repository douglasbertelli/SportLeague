import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const _seed = Color(0xFF1B8A3A);

  /// Fonte do app, nos assets (pubspec.yaml).
  static const fontFamily = 'DM Sans';

  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  /// Cinza dos textos secundários: legível no fundo (contraste AA), mas mais
  /// fraco que os títulos.
  static Color _secondaryText(Brightness brightness) =>
      brightness == Brightness.dark
      ? const Color(0xFFA8A8A8)
      : const Color(0xFF616161);

  static ThemeData _build(Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
      // Textos secundários (subtítulos, detalhes) em cinza neutro, sem o tom
      // verde do tema, para contrastar com os títulos.
    ).copyWith(onSurfaceVariant: _secondaryText(brightness));
    final textTheme = ThemeData(
      brightness: brightness,
      fontFamily: fontFamily,
    ).textTheme;
    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      fontFamily: fontFamily,
      listTileTheme: ListTileThemeData(
        subtitleTextStyle: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
      ),
    );
  }
}
