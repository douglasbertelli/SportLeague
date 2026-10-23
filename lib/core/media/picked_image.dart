import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

/// Imagem escolhida pelo usuário, pronta para enviar ao Storage.
class PickedImage {
  const PickedImage({required this.bytes, required this.contentType});

  final Uint8List bytes;
  final String contentType;
}

/// Lado maior das imagens pequenas (logo, foto do atleta).
const smallImageSize = 512.0;

/// Lado maior das imagens em destaque (capa, uniforme, local).
const largeImageSize = 1280.0;

typedef PickImage = Future<PickedImage?> Function(
  ImageSource source, {
  double maxSize,
});

/// Abre a galeria ou a câmera e devolve a imagem reduzida a no máximo
/// `maxSize` px. Nulo se o usuário cancelar. Substituível nos testes.
final pickImageProvider = Provider<PickImage>((ref) {
  final picker = ImagePicker();
  return (source, {maxSize = smallImageSize}) async {
    final file = await picker.pickImage(
      source: source,
      maxWidth: maxSize,
      maxHeight: maxSize,
      imageQuality: 85,
    );
    if (file == null) return null;
    final name = file.name.toLowerCase();
    return PickedImage(
      bytes: await file.readAsBytes(),
      contentType:
          file.mimeType ??
          switch (name) {
            _ when name.endsWith('.png') => 'image/png',
            _ when name.endsWith('.webp') => 'image/webp',
            _ => 'image/jpeg',
          },
    );
  };
});
