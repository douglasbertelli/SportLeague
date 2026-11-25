import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/media/picked_image.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../domain/team_cash.dart';

/// Bucket privado das fotos dos comprovantes: `<time>/<quem enviou>/<arquivo>`.
const paymentReceiptsBucket = 'payment-receipts';

/// Caixa do time e comprovantes de pagamento.
class CashRepository {
  CashRepository(this._client);

  final SupabaseClient _client;

  StorageFileApi get _receipts => _client.storage.from(paymentReceiptsBucket);

  Future<TeamCash> fetch(String teamId) async {
    final data = await _client.rpc<Map<String, dynamic>>(
      'team_cash',
      params: {'p_team': teamId},
    );
    return TeamCash.fromMap(data);
  }

  /// Lança uma entrada ou saída (o dono).
  Future<void> addEntry({
    required String teamId,
    required bool isIn,
    required String category,
    required int amountCents,
    required DateTime day,
    String? description,
  }) => _client.from('team_cash_entries').insert({
    'team_id': teamId,
    'kind': isIn ? 'in' : 'out',
    'category': category.trim(),
    'amount_cents': amountCents,
    'happened_on':
        '${day.year}-${day.month.toString().padLeft(2, '0')}-'
        '${day.day.toString().padLeft(2, '0')}',
    'description': switch (description?.trim()) {
      final text? when text.isNotEmpty => text,
      _ => null,
    },
  });

  Future<void> deleteEntry(String entryId) =>
      _client.from('team_cash_entries').delete().eq('id', entryId);

  /// Comprovantes: o dono vê os do time; os outros, os seus.
  Future<List<PaymentReceipt>> receipts(String teamId) async {
    final rows = await _client.rpc<List<dynamic>>(
      'team_payment_receipts_list',
      params: {'p_team': teamId},
    );
    return [
      for (final row in rows)
        PaymentReceipt.fromMap(row as Map<String, dynamic>),
    ];
  }

  /// Envia a foto e o comprovante da mensalidade de [month] ou da vaquinha
  /// [fundraiserId].
  Future<void> submitReceipt({
    required String teamId,
    required PickedImage image,
    DateTime? month,
    String? fundraiserId,
  }) async {
    final userId = _client.auth.currentUser!.id;
    final extension = switch (image.contentType) {
      'image/png' => 'png',
      'image/webp' => 'webp',
      _ => 'jpg',
    };
    final path =
        '$teamId/$userId/${DateTime.now().millisecondsSinceEpoch}.$extension';
    await _receipts.uploadBinary(
      path,
      image.bytes,
      fileOptions: FileOptions(contentType: image.contentType),
    );
    await _client.rpc(
      'submit_payment_receipt',
      params: {
        'p_team': teamId,
        'p_kind': fundraiserId == null ? 'dues' : 'fundraiser',
        'p_month': month == null
            ? null
            : '${month.year}-${month.month.toString().padLeft(2, '0')}-01',
        'p_fundraiser': fundraiserId,
        'p_image_path': path,
      },
    );
  }

  /// Confirma (marca o pagamento) ou recusa, com o motivo.
  Future<void> answerReceipt(
    String receiptId, {
    required bool approve,
    String? note,
  }) => _client.rpc(
    'answer_payment_receipt',
    params: {'p_receipt': receiptId, 'p_approve': approve, 'p_note': note},
  );

  /// URL temporária da foto do comprovante.
  Future<String> receiptUrl(String path) =>
      _receipts.createSignedUrl(path, 3600);
}

final cashRepositoryProvider = Provider<CashRepository>(
  (ref) => CashRepository(ref.watch(supabaseClientProvider)),
);

final teamCashProvider = FutureProvider.autoDispose.family<TeamCash, String>(
  (ref, teamId) => ref.watch(cashRepositoryProvider).fetch(teamId),
);

final paymentReceiptsProvider = FutureProvider.autoDispose
    .family<List<PaymentReceipt>, String>(
      (ref, teamId) => ref.watch(cashRepositoryProvider).receipts(teamId),
    );

final receiptUrlProvider = FutureProvider.autoDispose.family<String, String>(
  (ref, path) => ref.watch(cashRepositoryProvider).receiptUrl(path),
);
