import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/error_messages.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../notifications/domain/app_notification.dart' show timeAgo;
import '../data/cash_repository.dart';
import '../domain/team_cash.dart';

const _months = [
  'janeiro',
  'fevereiro',
  'março',
  'abril',
  'maio',
  'junho',
  'julho',
  'agosto',
  'setembro',
  'outubro',
  'novembro',
  'dezembro',
];

/// "mensalidade de março" ou "vaquinha · Bola".
String receiptLabel(PaymentReceipt receipt) => receipt.isDues
    ? 'mensalidade de ${_months[(receipt.month?.month ?? 1) - 1]}'
    : 'vaquinha · ${receipt.fundraiserTitle ?? ''}';

/// Comprovantes da mensalidade ([fundraiserId] nulo) ou de uma vaquinha.
/// O dono confere os que chegaram; quem pagou vê como está o seu.
class ReceiptsSection extends ConsumerWidget {
  const ReceiptsSection({
    super.key,
    required this.teamId,
    required this.isOwner,
    this.fundraiserId,
    this.onAnswered,
    this.allKinds = false,
  });

  /// Todos os comprovantes (mensalidade e vaquinhas), no caixa.
  final bool allKinds;

  final String teamId;
  final bool isOwner;
  final String? fundraiserId;

  /// Depois de confirmar ou recusar (para recarregar os pagamentos).
  final VoidCallback? onAnswered;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(paymentReceiptsProvider(teamId)).value ?? const [];
    final receipts = [
      for (final receipt in all)
        if (allKinds ||
            (fundraiserId == null
                ? receipt.isDues
                : receipt.fundraiserId == fundraiserId))
          receipt,
    ];
    final pending = [
      for (final receipt in receipts)
        if (receipt.status == ReceiptStatus.pending) receipt,
    ];
    // Quem pagou: o último comprovante seu (pendente ou recusado).
    final mine = [
      for (final receipt in receipts)
        if (receipt.mine && receipt.status != ReceiptStatus.approved) receipt,
    ];
    if (isOwner && pending.isEmpty) return const SizedBox.shrink();
    if (!isOwner && mine.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              isOwner
                  ? '${pending.length} '
                        '${pending.length == 1 ? 'comprovante' : 'comprovantes'} '
                        'para conferir'
                  : 'Seu comprovante',
              style: theme.textTheme.titleSmall,
            ),
            for (final receipt in isOwner ? pending : mine.take(1))
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  switch (receipt.status) {
                    ReceiptStatus.pending => Icons.hourglass_top,
                    ReceiptStatus.approved => Icons.check_circle_outline,
                    ReceiptStatus.rejected => Icons.cancel_outlined,
                  },
                  color: receipt.status == ReceiptStatus.rejected
                      ? theme.colorScheme.error
                      : null,
                ),
                title: Text(
                  isOwner
                      ? '${receipt.payer} · ${receiptLabel(receipt)}'
                      : switch (receipt.status) {
                          ReceiptStatus.pending =>
                            'Enviado · aguardando o dono conferir',
                          ReceiptStatus.rejected => 'Recusado',
                          ReceiptStatus.approved => 'Confirmado',
                        },
                ),
                subtitle: Text(
                  [timeAgo(receipt.createdAt), ?receipt.note].join(' · '),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showAppSheet<void>(
                  context,
                  builder: (_) => _ReceiptSheet(
                    teamId: teamId,
                    receipt: receipt,
                    canAnswer: isOwner,
                    onAnswered: onAnswered,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A foto do comprovante e, para o dono, confirmar ou recusar.
class _ReceiptSheet extends ConsumerStatefulWidget {
  const _ReceiptSheet({
    required this.teamId,
    required this.receipt,
    required this.canAnswer,
    this.onAnswered,
  });

  final String teamId;
  final PaymentReceipt receipt;
  final bool canAnswer;
  final VoidCallback? onAnswered;

  @override
  ConsumerState<_ReceiptSheet> createState() => _ReceiptSheetState();
}

class _ReceiptSheetState extends ConsumerState<_ReceiptSheet> {
  final _note = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _answer(bool approve) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(cashRepositoryProvider)
          .answerReceipt(
            widget.receipt.id,
            approve: approve,
            note: approve ? null : _note.text,
          );
      ref
        ..invalidate(paymentReceiptsProvider(widget.teamId))
        ..invalidate(teamCashProvider(widget.teamId));
      widget.onAnswered?.call();
      if (!mounted) return;
      Navigator.of(context).pop();
      showErrorSnackBar(
        context,
        approve ? 'Pagamento confirmado.' : 'Comprovante recusado.',
      );
    } catch (error) {
      if (mounted) showErrorSnackBar(context, friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final receipt = widget.receipt;
    final url = ref.watch(receiptUrlProvider(receipt.imagePath));
    final pending = receipt.status == ReceiptStatus.pending;
    return AppSheet(
      title: 'Comprovante',
      message: '${receipt.payer} · ${receiptLabel(receipt)}',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 380),
            child: url.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => const Text('Não foi possível abrir a foto.'),
              data: (url) => InteractiveViewer(
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  semanticLabel: 'Foto do comprovante',
                ),
              ),
            ),
          ),
          if (widget.canAnswer && pending) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: 'Motivo, se for recusar (opcional)',
              ),
            ),
          ],
        ],
      ),
      actions: [
        if (widget.canAnswer && pending) ...[
          FilledButton.icon(
            onPressed: _busy ? null : () => _answer(true),
            icon: const Icon(Icons.check),
            label: const Text('Confirmar pagamento'),
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _answer(false),
            icon: const Icon(Icons.close),
            label: const Text('Recusar'),
          ),
        ],
        const SheetBackButton(label: 'Fechar'),
      ],
    );
  }
}
