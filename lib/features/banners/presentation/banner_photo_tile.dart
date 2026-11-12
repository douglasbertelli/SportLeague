import 'package:flutter/material.dart';

/// Uma foto do banner: a miniatura (ou o ícone), o nome e o que tocar faz.
class BannerPhotoTile extends StatelessWidget {
  const BannerPhotoTile({
    super.key,
    required this.photo,
    required this.icon,
    required this.title,
    required this.emptySubtitle,
    required this.onTap,
  });

  final ImageProvider? photo;
  final IconData icon;
  final String title;

  /// O que aparece embaixo do nome sem foto.
  final String emptySubtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox.square(
          dimension: 44,
          child: switch (photo) {
            final photo? => Image(image: photo, fit: BoxFit.cover),
            null => ColoredBox(
              color: scheme.surfaceContainerHighest,
              child: Icon(icon, color: scheme.primary),
            ),
          },
        ),
      ),
      title: Text(title),
      subtitle: Text(
        photo == null ? emptySubtitle : 'Toque para trocar ou remover',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
