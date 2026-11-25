import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/media/photo_picker.dart';
import '../../../core/media/picked_image.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/utils/pix.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../fundraisers/domain/fundraiser.dart' show formatMoney;
import '../data/cash_repository.dart';

/// Pagar pelo Pix: QR code e copia-e-cola com a chave e o valor (o dinheiro
/// vai direto do banco de quem paga para o time) e, depois de pagar, o envio
/// do comprovante para o dono conferir.
Future<void> showPixPay(
  BuildContext context, {
  required String teamId,
  required String teamName,
  required String pixKey,
  required int amountCents,
  required String title,
  DateTime? month,
  String? fundraiserId,
}) => showAppSheet<void>(
  context,
  builder: (_) => _PixPaySheet(
    teamId: teamId,
    teamName: teamName,
    pixKey: pixKey,
    amountCents: amountCents,
    title: title,
    month: month,
    fundraiserId: fundraiserId,
  ),
);

class _PixPaySheet extends ConsumerStatefulWidget {
  const _PixPaySheet({
    required this.teamId,
    required this.teamName,
    required this.pixKey,
    required this.amountCents,
    required this.title,
    this.month,
    this.fundraiserId,
  });

  final String teamId;
  final String teamName;
  final String pixKey;
  final int amountCents;
  final String title;
  final DateTime? month;
  final String? fundraiserId;

  @override
  ConsumerState<_PixPaySheet> createState() => _PixPaySheetState();
}

class _PixPaySheetState extends ConsumerState<_PixPaySheet> {
  bool _sending = false;

  late final _code = pixPayload(
    key: widget.pixKey,
    name: widget.teamName,
    amountCents: widget.amountCents,
  );

  Future<void> _sendReceipt() async {
    final choice = await chooseImage(
      context,
      ref,
      noun: 'comprovante',
      canRemove: false,
      maxSize: largeImageSize,
    );
    if (choice is! ImagePicked || !mounted) return;
    setState(() => _sending = true);
    try {
      await ref
          .read(cashRepositoryProvider)
          .submitReceipt(
            teamId: widget.teamId,
            image: choice.image,
            month: widget.month,
            fundraiserId: widget.fundraiserId,
          );
      ref.invalidate(paymentReceiptsProvider(widget.teamId));
      if (!mounted) return;
      Navigator.of(context).pop();
      showErrorSnackBar(
        context,
        'Comprovante enviado. O dono do time vai conferir.',
      );
    } catch (error) {
      if (mounted) showErrorSnackBar(context, friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppSheet(
      title: 'Pagar com Pix',
      message:
          '${widget.title} · ${formatMoney(widget.amountCents)}\n'
          'Abra o app do seu banco, escaneie o QR code ou use o copia e '
          'cola. Depois, envie o comprovante.',
      body: Column(
        children: [
          // O QR em fundo branco (os bancos leem melhor), em qualquer tema.
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: QrImageView(
              data: _code,
              size: 220,
              backgroundColor: Colors.white,
              semanticsLabel: 'QR code do Pix',
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _code));
              if (context.mounted) {
                showErrorSnackBar(context, 'Pix copia e cola copiado.');
              }
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copiar Pix copia e cola'),
          ),
          const SizedBox(height: 8),
          Text(
            'Chave: ${widget.pixKey}',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: [
        FilledButton.icon(
          onPressed: _sending ? null : _sendReceipt,
          icon: _sending
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.receipt_long_outlined),
          label: const Text('Já paguei: enviar comprovante'),
        ),
        const SheetBackButton(label: 'Fechar'),
      ],
    );
  }
}
