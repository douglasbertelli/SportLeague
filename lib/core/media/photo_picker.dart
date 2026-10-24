import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../widgets/circle_image.dart';
import '../widgets/confirm_dialog.dart';
import 'picked_image.dart';
import 'square_crop_page.dart';

/// Resposta de [chooseImage].
sealed class ImageChoice {
  const ImageChoice();
}

class ImagePicked extends ImageChoice {
  const ImagePicked(this.image);

  final PickedImage image;
}

class ImageRemoved extends ImageChoice {
  const ImageRemoved();
}

/// Pergunta de onde vem a imagem (galeria, câmera ou, com [canRemove],
/// remover a atual) e a abre; com [cropSquare], abre o recorte em quadrado
/// em seguida. Nulo se o usuário desistir ou a imagem não abrir (nesse caso
/// avisa).
Future<ImageChoice?> chooseImage(
  BuildContext context,
  WidgetRef ref, {
  required String noun,
  required bool canRemove,
  double maxSize = smallImageSize,
  bool cropSquare = false,
}) async {
  final choice = await showModalBottomSheet<Object>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Escolher da galeria'),
            onTap: () => Navigator.of(context).pop(ImageSource.gallery),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Tirar foto'),
            onTap: () => Navigator.of(context).pop(ImageSource.camera),
          ),
          if (canRemove)
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text('Remover $noun'),
              onTap: () => Navigator.of(context).pop(const ImageRemoved()),
            ),
        ],
      ),
    ),
  );
  switch (choice) {
    case final ImageRemoved removed:
      return removed;
    case final ImageSource source:
      final PickedImage? picked;
      try {
        picked = await ref.read(pickImageProvider)(source, maxSize: maxSize);
      } catch (_) {
        if (context.mounted) {
          showErrorSnackBar(context, 'Não foi possível abrir a imagem.');
        }
        return null;
      }
      if (picked == null) return null;
      if (!cropSquare) return ImagePicked(picked);
      if (!context.mounted) return null;
      final cropped = await ref.read(cropSquareProvider)(context, picked);
      return cropped == null ? null : ImagePicked(cropped);
    default:
      return null;
  }
}

/// Foto em destaque no topo de um formulário (logo do time, foto do atleta).
/// Ao tocar, escolhe da galeria, tira uma foto ou remove a atual.
class PhotoPicker extends ConsumerWidget {
  const PhotoPicker({
    super.key,
    required this.noun,
    required this.image,
    required this.url,
    required this.placeholderIcon,
    required this.onPicked,
    required this.onRemoved,
    this.enabled = true,
    this.errorText,
    this.maxSize = smallImageSize,
    this.cropSquare = false,
  });

  /// "logo", "foto": usado nos textos ("Adicionar logo", "Remover foto").
  final String noun;

  /// Imagem escolhida e ainda não enviada; tem prioridade sobre [url].
  final PickedImage? image;
  final String? url;
  final IconData placeholderIcon;
  final ValueChanged<PickedImage> onPicked;
  final VoidCallback onRemoved;
  final bool enabled;
  final String? errorText;

  /// Lado maior da imagem enviada.
  final double maxSize;

  /// Recorta em quadrado depois de escolher (logo).
  final bool cropSquare;

  Future<void> _choose(BuildContext context, WidgetRef ref) async {
    switch (await chooseImage(
      context,
      ref,
      noun: noun,
      canRemove: image != null || url != null,
      maxSize: maxSize,
      cropSquare: cropSquare,
    )) {
      case ImagePicked(:final image):
        onPicked(image);
      case ImageRemoved():
        onRemoved();
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final ImageProvider? provider = switch ((image, url)) {
      (final image?, _) => MemoryImage(image.bytes),
      (null, final url?) => NetworkImage(url),
      _ => null,
    };
    final errorText = this.errorText;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          label: provider == null ? 'Adicionar $noun' : 'Trocar $noun',
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: enabled ? () => _choose(context, ref) : null,
            child: Stack(
              children: [
                CircleImage(
                  image: provider,
                  radius: 48,
                  placeholder: Icon(placeholderIcon, size: 40),
                  whole: cropSquare,
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: colorScheme.primary,
                    child: Icon(
                      Icons.photo_camera,
                      size: 16,
                      color: colorScheme.onPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 8),
          Text(
            errorText,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }
}
