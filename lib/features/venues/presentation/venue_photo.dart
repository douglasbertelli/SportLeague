import 'package:flutter/material.dart';

import '../domain/venue.dart';

/// Foto do local nas listas; sem foto (ou se ela não carregar), um ícone.
class VenuePhoto extends StatelessWidget {
  const VenuePhoto({super.key, required this.venue, this.size = 48});

  final Venue venue;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final placeholder = ColoredBox(
      color: colors.surfaceContainerHighest,
      child: Icon(
        Icons.place_outlined,
        size: size / 2,
        color: colors.onSurfaceVariant,
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox.square(
        dimension: size,
        child: switch (venue.photoUrl) {
          final url? => Image.network(
            url,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => placeholder,
          ),
          null => placeholder,
        },
      ),
    );
  }
}
