import 'package:flutter/material.dart';

/// Cor que o usuário escolhe para o app (a do time, por exemplo). O tema
/// inteiro, claro e escuro, é gerado a partir dela.
class AppColor {
  /// Cor com tom: a paleta vem dela.
  const AppColor(this.id, this.name, this.color, {this.darkPrimary})
    : lightAccent = null,
      darkAccent = null,
      pureBlack = false;

  /// Cinza ou preto: superfícies neutras e o destaque nos tons dados (no
  /// escuro, um tom claro, senão o destaque some no fundo).
  const AppColor.neutral(
    this.id,
    this.name,
    this.color, {
    required Color this.lightAccent,
    required Color this.darkAccent,
    this.pureBlack = false,
  }) : darkPrimary = null;

  final String id;
  final String name;

  /// A cor mostrada na escolha.
  final Color color;

  /// Destaque das cores neutras no tema claro e no escuro.
  final Color? lightAccent;
  final Color? darkAccent;

  /// No tema escuro, fundo preto puro.
  final bool pureBlack;

  /// Destaque exato no tema escuro (o verde do logo, vivo sobre o fundo
  /// escuro). No claro vale o tom gerado da cor, escuro o bastante para
  /// contrastar com o branco.
  final Color? darkPrimary;

  bool get isNeutral => lightAccent != null;

  /// Esquema de cores do tema [brightness].
  ColorScheme scheme(Brightness brightness) {
    final accent = brightness == Brightness.dark ? darkAccent : lightAccent;
    if (accent == null) {
      final scheme = ColorScheme.fromSeed(
        seedColor: color,
        brightness: brightness,
      );
      return switch (darkPrimary) {
        final primary? when brightness == Brightness.dark => scheme.copyWith(
          primary: primary,
          onPrimary: Colors.black,
        ),
        _ => scheme,
      };
    }
    // Sem tom: a variante monocromática não puxa para nenhuma cor.
    final base = ColorScheme.fromSeed(
      seedColor: color,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.monochrome,
    );
    final onAccent =
        ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
        ? Colors.white
        : Colors.black;
    final scheme = base.copyWith(primary: accent, onPrimary: onAccent);
    return pureBlack && brightness == Brightness.dark
        ? scheme.copyWith(
            surface: Colors.black,
            surfaceContainerLowest: Colors.black,
            surfaceContainerLow: const Color(0xFF0A0A0A),
            surfaceContainer: const Color(0xFF121212),
            surfaceContainerHigh: const Color(0xFF1A1A1A),
            surfaceContainerHighest: const Color(0xFF242424),
          )
        : scheme;
  }
}

/// As cores oferecidas; a primeira (o verde do logo) é a padrão e a das telas
/// antes do login.
const appColors = <AppColor>[
  AppColor(
    'green',
    'Verde SportLeague',
    Color(0xFF07F469),
    darkPrimary: Color(0xFF07F469),
  ),
  AppColor('lime', 'Verde-limão', Color(0xFF7CB342)),
  AppColor('olive', 'Oliva', Color(0xFF808000)),
  AppColor('teal', 'Verde-água', Color(0xFF00897B)),
  AppColor('cyan', 'Turquesa', Color(0xFF00ACC1)),
  AppColor('sky', 'Azul-celeste', Color(0xFF29B6F6)),
  AppColor('blue', 'Azul', Color(0xFF1E88E5)),
  AppColor('royal', 'Azul-royal', Color(0xFF2962FF)),
  AppColor('navy', 'Azul-marinho', Color(0xFF1A237E)),
  AppColor('indigo', 'Índigo', Color(0xFF3949AB)),
  AppColor('purple', 'Roxo', Color(0xFF7B1FA2)),
  AppColor('violet', 'Violeta', Color(0xFF9575CD)),
  AppColor('lilac', 'Lilás', Color(0xFFC8A2C8)),
  AppColor('pink', 'Rosa', Color(0xFFEC407A)),
  AppColor('magenta', 'Magenta', Color(0xFFC2185B)),
  AppColor('red', 'Vermelho', Color(0xFFE53935)),
  AppColor('wine', 'Bordô', Color(0xFF880E4F)),
  AppColor('salmon', 'Salmão', Color(0xFFFA8072)),
  AppColor('coral', 'Coral', Color(0xFFFF7043)),
  AppColor('orange', 'Laranja', Color(0xFFFB8C00)),
  AppColor('mustard', 'Mostarda', Color(0xFFE1AD01)),
  AppColor('yellow', 'Amarelo', Color(0xFFFDD835)),
  AppColor('gold', 'Dourado', Color(0xFFC9A227)),
  AppColor('brown', 'Marrom', Color(0xFF6D4C41)),
  AppColor('slate', 'Grafite', Color(0xFF546E7A)),
  AppColor.neutral(
    'grey',
    'Cinza',
    Color(0xFF9E9E9E),
    lightAccent: Color(0xFF6B6B6B),
    darkAccent: Color(0xFFBDBDBD),
  ),
  AppColor.neutral(
    'darkgrey',
    'Cinza-escuro',
    Color(0xFF424242),
    lightAccent: Color(0xFF3A3A3A),
    darkAccent: Color(0xFF9E9E9E),
  ),
  AppColor.neutral(
    'black',
    'Preto',
    Color(0xFF000000),
    lightAccent: Color(0xFF000000),
    darkAccent: Color(0xFFFFFFFF),
    pureBlack: true,
  ),
];
