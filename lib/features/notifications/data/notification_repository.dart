import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../domain/app_notification.dart';

class NotificationRepository {
  NotificationRepository(this._client);

  final SupabaseClient _client;

  /// As últimas notificações do usuário, mais novas primeiro, ao vivo: as
  /// novas chegam sem precisar buscar de novo.
  Stream<List<AppNotification>> watchMine(String userId) => _client
      .from('notifications')
      .stream(primaryKey: ['id'])
      .eq('recipient_id', userId)
      .order('created_at', ascending: false)
      .limit(50)
      .map((rows) => rows.map(AppNotification.fromMap).toList());

  Future<void> markRead(String id) => _client
      .from('notifications')
      .update({'read_at': DateTime.now().toUtc().toIso8601String()})
      .eq('id', id);

  /// Marca todas as não lidas do usuário como lidas.
  Future<void> markAllRead(String userId) => _client
      .from('notifications')
      .update({'read_at': DateTime.now().toUtc().toIso8601String()})
      .eq('recipient_id', userId)
      .isFilter('read_at', null);

  /// Marca as [ids] como lidas (as do time que está na tela).
  Future<void> markManyRead(List<String> ids) => _client
      .from('notifications')
      .update({'read_at': DateTime.now().toUtc().toIso8601String()})
      .inFilter('id', ids);

  Future<void> delete(String id) =>
      _client.from('notifications').delete().eq('id', id);
}

final notificationRepositoryProvider = Provider<NotificationRepository>(
  (ref) => NotificationRepository(ref.watch(supabaseClientProvider)),
);

/// Notificações do usuário logado, ao vivo.
final myNotificationsProvider = StreamProvider<List<AppNotification>>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return Stream.value(const []);
  return ref.watch(notificationRepositoryProvider).watchMine(userId);
});

/// Apagadas nesta sessão. O ao vivo do Supabase não avisa quando uma
/// notificação é apagada (o filtro por destinatário não vale para o DELETE),
/// então a lista continuaria com ela; por aqui ela sai na hora.
class DeletedNotifications extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void add(String id) => state = {...state, id};

  void remove(String id) => state = {...state}..remove(id);
}

final deletedNotificationsProvider =
    NotifierProvider<DeletedNotifications, Set<String>>(
      DeletedNotifications.new,
    );

/// As notificações do usuário sem as que ele apagou (nulo enquanto carrega).
final visibleNotificationsProvider = Provider<List<AppNotification>?>((ref) {
  final deleted = ref.watch(deletedNotificationsProvider);
  return ref
      .watch(myNotificationsProvider)
      .value
      ?.where((notification) => !deleted.contains(notification.id))
      .toList();
});

/// Quantas não lidas (o número no sino).
final unreadNotificationsProvider = Provider<int>(
  (ref) => (ref.watch(visibleNotificationsProvider) ?? const [])
      .where((notification) => !notification.isRead)
      .length,
);
