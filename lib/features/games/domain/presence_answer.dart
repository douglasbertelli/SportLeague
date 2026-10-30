import 'package:flutter/material.dart';

/// Resposta do atleta ao pedido de presença.
enum PresenceAnswer {
  yes('yes', 'Sim', Icons.check_circle_outline),
  no('no', 'Não', Icons.cancel_outlined),
  maybe('maybe', 'Talvez', Icons.help_outline);

  const PresenceAnswer(this.value, this.label, this.icon);

  /// Como fica no banco (`game_presence.answer`).
  final String value;
  final String label;
  final IconData icon;

  static PresenceAnswer? fromValue(Object? value) =>
      values.where((answer) => answer.value == value).firstOrNull;
}
