import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/error_messages.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/loading_button.dart';
import '../data/report_repository.dart';
import '../domain/content_report.dart';

/// Abre a denúncia de [target]. Ao enviar, fecha e agradece.
Future<void> showReportSheet(
  BuildContext context, {
  required ReportTarget target,
  required String targetId,
}) async {
  final sent = await showAppSheet<bool>(
    context,
    builder: (_) => ReportSheet(target: target, targetId: targetId),
  );
  if (sent == true && context.mounted) {
    showErrorSnackBar(
      context,
      'Denúncia enviada. Obrigado por avisar, vamos analisar.',
    );
  }
}

/// Botão de menu (⋮) da barra do app com a opção Denunciar.
class ReportMenuButton extends StatelessWidget {
  const ReportMenuButton({
    super.key,
    required this.target,
    required this.targetId,
  });

  final ReportTarget target;
  final String targetId;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<void>(
      tooltip: 'Mais opções',
      itemBuilder: (_) => [
        PopupMenuItem(
          onTap: () =>
              showReportSheet(context, target: target, targetId: targetId),
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.flag_outlined),
            title: Text('Denunciar ${target.label}'),
          ),
        ),
      ],
    );
  }
}

/// Motivo, detalhes opcionais e envio da denúncia.
class ReportSheet extends ConsumerStatefulWidget {
  const ReportSheet({super.key, required this.target, required this.targetId});

  final ReportTarget target;
  final String targetId;

  @override
  ConsumerState<ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<ReportSheet> {
  final _details = TextEditingController();
  ReportReason? _reason;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final reason = _reason;
    if (reason == null) {
      setState(() => _error = 'Escolha o motivo da denúncia.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref
          .read(reportRepositoryProvider)
          .report(
            target: widget.target,
            targetId: widget.targetId,
            reason: reason,
            details: _details.text,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = friendlyErrorMessage(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppSheet(
      title: 'Denunciar ${widget.target.label}',
      message:
          'A denúncia é anônima: quem criou o conteúdo não fica sabendo '
          'quem denunciou. Conteúdo que viola os Termos de Uso é removido.',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RadioGroup<ReportReason>(
            groupValue: _reason,
            onChanged: _sending
                ? (_) {}
                : (value) => setState(() {
                    _reason = value;
                    _error = null;
                  }),
            child: Column(
              children: [
                for (final reason in ReportReason.values)
                  RadioListTile<ReportReason>(
                    contentPadding: EdgeInsets.zero,
                    value: reason,
                    title: Text(reason.label),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _details,
            enabled: !_sending,
            maxLength: 1000,
            minLines: 2,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Detalhes (opcional)',
              hintText: 'Conte o que está errado',
            ),
          ),
          if (_error case final error?) ...[
            const SizedBox(height: 8),
            Text(
              error,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ],
      ),
      actions: [
        LoadingButton(
          label: 'Enviar denúncia',
          loading: _sending,
          onPressed: _send,
        ),
        const SheetBackButton(),
      ],
    );
  }
}
