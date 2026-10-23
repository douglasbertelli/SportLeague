import 'package:flutter/material.dart';

import 'app_sheet.dart';

/// Pede confirmação antes de uma exclusão. Retorna `true` se confirmada.
Future<bool> confirmDelete(
  BuildContext context, {
  required String title,
  required String message,
}) => confirmAction(
  context,
  title: title,
  message: message,
  confirmLabel: 'Excluir',
  confirmIcon: Icons.delete_outline,
);

/// Pede confirmação (num bottom sheet) antes de uma ação que não dá para
/// desfazer. Retorna `true` se confirmada.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  IconData confirmIcon = Icons.check,
  String cancelLabel = 'Cancelar',
}) async {
  final confirmed = await showAppSheet<bool>(
    context,
    builder: (context) {
      final colors = Theme.of(context).colorScheme;
      return AppSheet(
        title: title,
        message: message,
        actions: [
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: colors.error,
              foregroundColor: colors.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            icon: Icon(confirmIcon),
            label: Text(confirmLabel),
          ),
          TextButton.icon(
            onPressed: () => Navigator.of(context).pop(false),
            icon: const Icon(Icons.arrow_back),
            label: Text(cancelLabel),
          ),
        ],
      );
    },
  );
  return confirmed ?? false;
}

void showErrorSnackBar(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
