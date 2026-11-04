import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/confirm_dialog.dart';

/// Abre um link fora do app (no app de mapas, se instalado). Trocado nos
/// testes.
final launchExternalUrlProvider = Provider<Future<bool> Function(Uri)>(
  (ref) =>
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

/// Link do Google Maps que pesquisa o [address].
Uri googleMapsUrl(String address) => Uri.https(
  'www.google.com',
  '/maps/search/',
  {'api': '1', 'query': address},
);

/// Link do Waze que traça a rota até o [address].
Uri wazeUrl(String address) =>
    Uri.https('waze.com', '/ul', {'q': address, 'navigate': 'yes'});

/// Pergunta em qual app abrir o [address] (Google Maps ou Waze) e abre.
Future<void> openInMaps(
  BuildContext context,
  WidgetRef ref, {
  required String title,
  required String address,
}) async {
  final url = await showModalBottomSheet<Uri>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  address,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.map_outlined),
            title: const Text('Abrir no Google Maps'),
            onTap: () => Navigator.of(context).pop(googleMapsUrl(address)),
          ),
          ListTile(
            leading: const Icon(Icons.navigation_outlined),
            title: const Text('Abrir no Waze'),
            onTap: () => Navigator.of(context).pop(wazeUrl(address)),
          ),
        ],
      ),
    ),
  );
  if (url == null) return;
  final opened = await ref
      .read(launchExternalUrlProvider)(url)
      .catchError((_) => false);
  if (!opened && context.mounted) {
    showErrorSnackBar(context, 'Não foi possível abrir o mapa.');
  }
}
