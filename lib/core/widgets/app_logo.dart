import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Logo do SportLeague (login e abertura). As letras "Sport" e o símbolo
/// usam a cor do texto do tema (brancas no escuro, escuras no claro); "League"
/// fica no verde da marca.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.width = 150});

  final double width;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/images/logo.svg',
      width: width,
      semanticsLabel: 'SportLeague',
      theme: SvgTheme(currentColor: Theme.of(context).colorScheme.onSurface),
    );
  }
}
