import 'package:flutter/material.dart';

import 'app_colors.dart';

abstract final class AppTheme {
  /// Fonte do app, nos assets (pubspec.yaml).
  static const fontFamily = 'DM Sans';

  /// Tema claro na cor escolhida pelo usuário (o verde por padrão).
  static ThemeData light({AppColor? color}) =>
      _build(Brightness.light, color ?? appColors.first);

  /// Tema escuro na cor escolhida pelo usuário (o verde por padrão).
  static ThemeData dark({AppColor? color}) =>
      _build(Brightness.dark, color ?? appColors.first);

  /// Cinza dos textos secundários: legível no fundo (contraste AA), mas mais
  /// fraco que os títulos.
  static Color _secondaryText(Brightness brightness) =>
      brightness == Brightness.dark
      ? const Color(0xFFA8A8A8)
      : const Color(0xFF616161);

  static ThemeData _build(Brightness brightness, AppColor color) {
    // Textos secundários (subtítulos, detalhes) em cinza neutro, sem o tom da
    // cor do tema, para contrastar com os títulos.
    final colorScheme = color
        .scheme(brightness)
        .copyWith(onSurfaceVariant: _secondaryText(brightness));
    final textTheme = ThemeData(
      brightness: brightness,
      fontFamily: fontFamily,
    ).textTheme;
    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      fontFamily: fontFamily,
      // Cards planos: sem sombra, separados só pela cor do fundo.
      cardTheme: const CardThemeData(elevation: 0),
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
