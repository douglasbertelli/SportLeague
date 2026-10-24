import 'package:flutter/material.dart';

/// Imagem redonda (foto) ou inteira (logo, [whole]). Enquanto carrega, sem
/// imagem ou se ela falhar, mostra o círculo colorido com [placeholder];
/// carregada, fica só a imagem, sem o fundo (logos com transparência ficam
/// limpos).
class CircleImage extends StatelessWidget {
  const CircleImage({
    super.key,
    required this.image,
    required this.radius,
    required this.placeholder,
    this.whole = false,
  });

  final ImageProvider? image;
  final double radius;
  final Widget placeholder;

  /// Mostra a imagem inteira no quadrado, sem cortar no círculo (escudos).
  final bool whole;

  @override
  Widget build(BuildContext context) {
    final fallback = CircleAvatar(radius: radius, child: placeholder);
    final image = this.image;
    if (image == null) return fallback;
    final picture = Image(
      image: image,
      width: radius * 2,
      height: radius * 2,
      fit: whole ? BoxFit.contain : BoxFit.cover,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) =>
          frame == null && !wasSynchronouslyLoaded ? fallback : child,
      errorBuilder: (context, error, stackTrace) => fallback,
    );
    return whole ? picture : ClipOval(child: picture);
  }
}
