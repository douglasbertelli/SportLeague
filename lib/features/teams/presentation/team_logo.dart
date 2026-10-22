import 'package:flutter/material.dart';

import '../domain/team.dart';

/// Logo do time em círculo; sem logo (ou se a imagem falhar), mostra um escudo.
class TeamLogo extends StatelessWidget {
  const TeamLogo({super.key, required this.team, this.radius = 20});

  final Team team;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final logoUrl = team.logoUrl;
    return CircleAvatar(
      radius: radius,
      foregroundImage: logoUrl == null ? null : NetworkImage(logoUrl),
      onForegroundImageError: logoUrl == null ? null : (_, _) {},
      child: Icon(Icons.shield_outlined, size: radius),
    );
  }
}
