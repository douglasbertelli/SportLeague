import 'package:flutter/material.dart';

/// Uma notificação da central, criada pelo banco num acontecimento (convite,
/// pedido, amistoso, placar, vaquinha).
class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.createdAt,
    this.teamId,
    this.gameId,
    this.fundraiserId,
    this.readAt,
  });

  factory AppNotification.fromMap(Map<String, dynamic> map) => AppNotification(
    id: map['id'] as String,
    kind: map['kind'] as String,
    title: map['title'] as String,
    body: map['body'] as String,
    createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
    teamId: map['team_id'] as String?,
    gameId: map['game_id'] as String?,
    fundraiserId: map['fundraiser_id'] as String?,
    readAt: switch (map['read_at']) {
      final String at => DateTime.parse(at).toLocal(),
      _ => null,
    },
  );

  final String id;

  /// invite, request, invite_answer, request_answer, game_invite,
  /// game_accepted, game_declined, game_canceled, game_rescheduled,
  /// game_score, dispute, dispute_answer, fundraiser, fundraiser_paid,
  /// presence.
  final String kind;
  final String title;
  final String body;
  final DateTime createdAt;
  final String? teamId;
  final String? gameId;
  final String? fundraiserId;
  final DateTime? readAt;

  bool get isRead => readAt != null;

  /// Ícone do tipo de acontecimento.
  IconData get icon => switch (kind) {
    'invite' || 'invite_answer' => Icons.mail_outline,
    'request' || 'request_answer' => Icons.person_add_alt_1_outlined,
    'game_invite' || 'game_accepted' => Icons.sports_soccer,
    'game_declined' || 'game_canceled' => Icons.event_busy,
    'game_rescheduled' => Icons.event_repeat,
    'game_score' => Icons.scoreboard_outlined,
    'dispute' || 'dispute_answer' => Icons.report_outlined,
    'fundraiser' || 'fundraiser_paid' => Icons.savings_outlined,
    'presence' => Icons.how_to_reg_outlined,
    _ => Icons.notifications_none,
  };
}

/// "agora", "há 5 min", "há 3 h", "ontem", "há 4 dias" ou a data.
String timeAgo(DateTime at, [DateTime? now]) {
  final diff = (now ?? DateTime.now()).difference(at);
  if (diff.inMinutes < 1) return 'agora';
  if (diff.inHours < 1) return 'há ${diff.inMinutes} min';
  if (diff.inDays < 1) return 'há ${diff.inHours} h';
  if (diff.inDays == 1) return 'ontem';
  if (diff.inDays < 7) return 'há ${diff.inDays} dias';
  final day = at.day.toString().padLeft(2, '0');
  final month = at.month.toString().padLeft(2, '0');
  return '$day/$month/${at.year}';
}
