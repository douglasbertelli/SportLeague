import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/error_messages.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../data/dispute_repository.dart';
import '../domain/game.dart';
import '../domain/score_dispute.dart';

/// O adversário ([viewerTeamId]) contesta o placar de [game]: diz o placar
/// na visão dele e o motivo, que vai para quem marcou responder. Retorna se
/// a contestação foi enviada.
Future<bool> contestScore(
  BuildContext context,
  WidgetRef ref, {
  required Game game,
  required String viewerTeamId,
  required String myTeamName,
}) async {
  final opponentName = game.opponentNameFor(viewerTeamId);
  final result = await showAppSheet<(int, int, String)>(
    context,
    builder: (_) => _ContestSheet(
      myTeam: myTeamName,
      opponent: opponentName,
      current: game.scoreFor(viewerTeamId) ?? (0, 0),
    ),
  );
  if (result == null || !context.mounted) return false;
  final (mine, theirs, message) = result;
  try {
    await ref
        .read(disputeRepositoryProvider)
        .create(
          ScoreDispute(
            gameId: game.id!,
            teamId: viewerTeamId,
            // Do ponto de vista de quem marcou.
            teamScore: theirs,
            opponentScore: mine,
            message: message,
          ),
        );
    ref.invalidate(teamDisputesProvider(viewerTeamId));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Contestação enviada para $opponentName.')),
      );
    }
    return true;
  } catch (error) {
    if (context.mounted) {
      showErrorSnackBar(context, friendlyErrorMessage(error));
    }
    return false;
  }
}

/// Contestar o placar: o placar na visão do adversário (o time ativo) e o
/// motivo, que vai para quem marcou o jogo.
class _ContestSheet extends StatefulWidget {
  const _ContestSheet({
    required this.myTeam,
    required this.opponent,
    required this.current,
  });

  final String myTeam;
  final String opponent;

  /// Placar lançado, do ponto de vista do time ativo.
  final (int, int) current;

  @override
  State<_ContestSheet> createState() => _ContestSheetState();
}

class _ContestSheetState extends State<_ContestSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _mine = TextEditingController(text: widget.current.$1.toString());
  late final _theirs = TextEditingController(
    text: widget.current.$2.toString(),
  );
  final _message = TextEditingController();

  @override
  void dispose() {
    _mine.dispose();
    _theirs.dispose();
    _message.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context)
        .pop((int.parse(_mine.text), int.parse(_theirs.text), _message.text));
  }

  @override
  Widget build(BuildContext context) {
    Widget field(TextEditingController controller, String team) => Expanded(
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(labelText: team, counterText: ''),
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineMedium,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        maxLength: 2,
        validator: (value) =>
            int.tryParse(value ?? '') == null ? 'Informe os gols' : null,
      ),
    );

    return AppSheet(
      title: 'Contestar placar',
      message:
          'Lançado: ${widget.myTeam} ${widget.current.$1} × '
          '${widget.current.$2} ${widget.opponent}. Diga o placar certo e o '
          'motivo; ${widget.opponent} aceita ou mantém o dele.',
      body: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                field(_mine, widget.myTeam),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 16,
                  ),
                  child: Text(
                    '×',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
                field(_theirs, widget.opponent),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _message,
              decoration: const InputDecoration(
                labelText: 'Motivo',
                hintText: 'Ex.: o gol do 2º tempo foi anulado',
              ),
              minLines: 2,
              maxLines: 4,
              maxLength: 500,
              textCapitalization: TextCapitalization.sentences,
              validator: (value) => (value ?? '').trim().isEmpty
                  ? 'Explique o motivo da contestação'
                  : null,
            ),
          ],
        ),
      ),
      actions: [
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.send_outlined),
          label: const Text('Enviar contestação'),
        ),
        const SheetBackButton(),
      ],
    );
  }
}

/// Destaque de "Contestação enviada · aguardando [hostName]", para quem
/// contestou (no card do jogo e no Início).
class DisputeSentBadge extends StatelessWidget {
  const DisputeSentBadge({super.key, required this.hostName});

  final String hostName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.tertiaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.hourglass_top,
            size: 18,
            color: colors.onTertiaryContainer,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'Contestação enviada · aguardando $hostName',
              style: theme.textTheme.labelLarge?.copyWith(
                color: colors.onTertiaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
