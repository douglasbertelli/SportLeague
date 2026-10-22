import 'package:flutter/material.dart';

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
);

/// Pede confirmação antes de uma ação que não dá para desfazer. Retorna `true`
/// se confirmada.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Cancelar',
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(cancelLabel),
        ),
        TextButton(
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

void showErrorSnackBar(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
