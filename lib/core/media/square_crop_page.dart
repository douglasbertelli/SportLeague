import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'picked_image.dart';

typedef CropSquare = Future<PickedImage?> Function(
  BuildContext context,
  PickedImage image,
);

/// Abre a tela de recorte quadrado e devolve a imagem recortada; nulo se o
/// usuário voltar. Substituível nos testes.
final cropSquareProvider = Provider<CropSquare>(
  (ref) =>
      (context, image) => Navigator.of(context).push<PickedImage>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => SquareCropPage(image: image),
        ),
      ),
);

/// Recorte em quadrado (logo do time): arraste e redimensione a área, ou
/// aproxime a imagem com dois dedos.
class SquareCropPage extends StatefulWidget {
  const SquareCropPage({super.key, required this.image});

  final PickedImage image;

  @override
  State<SquareCropPage> createState() => _SquareCropPageState();
}

class _SquareCropPageState extends State<SquareCropPage> {
  final _controller = CropController();
  var _ready = false;
  var _cropping = false;

  void _onCropped(CropResult result) {
    if (!mounted) return;
    switch (result) {
      case CropSuccess(:final croppedImage):
        Navigator.of(context).pop(
          PickedImage(
            bytes: croppedImage,
            // O recorte mantém JPEG e PNG; os outros formatos viram PNG.
            contentType:
                croppedImage.length > 2 &&
                    croppedImage[0] == 0xFF &&
                    croppedImage[1] == 0xD8
                ? 'image/jpeg'
                : 'image/png',
          ),
        );
      case CropFailure():
        setState(() => _cropping = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível recortar a imagem.')),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ajustar imagem'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.icon(
              // O tema deixa os botões na largura toda; na barra, não.
              style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
              onPressed: _ready && !_cropping
                  ? () {
                      setState(() => _cropping = true);
                      _controller.crop();
                    }
                  : null,
              icon: _cropping
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: const Text('Usar'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Crop(
                image: widget.image.bytes,
                controller: _controller,
                aspectRatio: 1,
                interactive: true,
                baseColor: colors.surface,
                maskColor: colors.scrim.withValues(alpha: 0.6),
                progressIndicator: const Center(
                  child: CircularProgressIndicator(),
                ),
                onStatusChanged: (status) {
                  if (mounted && status == CropStatus.ready && !_ready) {
                    setState(() => _ready = true);
                  }
                },
                onCropped: _onCropped,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Arraste o quadrado e use dois dedos para aproximar.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
