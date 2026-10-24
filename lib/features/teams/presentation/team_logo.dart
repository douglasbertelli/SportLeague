import 'package:flutter/material.dart';

import '../../../core/widgets/circle_image.dart';
import '../domain/team.dart';

/// Logo do time inteiro, sem fundo; sem logo (ou se a imagem falhar),
/// mostra um escudo.
class TeamLogo extends StatelessWidget {
  TeamLogo({super.key, required Team team, this.radius = 20})
    : logoUrl = team.logoUrl;

  /// Para times carregados só com o logo (ex.: o outro time de um jogo).
  const TeamLogo.url({super.key, required this.logoUrl, this.radius = 20});

  final String? logoUrl;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final logoUrl = this.logoUrl;
    return CircleImage(
      image: logoUrl == null ? null : NetworkImage(logoUrl),
      radius: radius,
      placeholder: Icon(Icons.shield_outlined, size: radius),
      whole: true,
    );
  }
}
