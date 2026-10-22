import 'package:flutter/material.dart';

import '../domain/team.dart';

/// Logo do time em círculo; sem logo (ou se a imagem falhar), mostra um escudo.
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
    return CircleAvatar(
      radius: radius,
      foregroundImage: logoUrl == null ? null : NetworkImage(logoUrl),
      onForegroundImageError: logoUrl == null ? null : (_, _) {},
      child: Icon(Icons.shield_outlined, size: radius),
    );
  }
}
