import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/env.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../invites/data/invite_repository.dart' show shareTextProvider;
import '../../teams/presentation/team_logo.dart';
import '../data/championship_repository.dart';
import '../domain/championship.dart';
import '../domain/championship_stats.dart';

/// Inscrição por link (o organizador, com o campeonato em montagem): liga o
/// link, compartilha e responde os pedidos que chegaram.
class ChampionshipSignupCard extends ConsumerStatefulWidget {
  const ChampionshipSignupCard({super.key, required this.championship});

  final Championship championship;

  @override
  ConsumerState<ChampionshipSignupCard> createState() =>
      _ChampionshipSignupCardState();
}

class _ChampionshipSignupCardState
    extends ConsumerState<ChampionshipSignupCard> {
  bool _busy = false;

  Championship get _c => widget.championship;

  String _url(String code) => '${Env.siteUrl}/inscricao/$code';

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      ref
        ..invalidate(championshipProvider(_c.id!))
        ..invalidate(championshipRequestsProvider(_c.id!))
        ..invalidate(championshipTeamsProvider(_c.id!));
    } catch (error) {
      if (mounted) showErrorSnackBar(context, friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggle(bool enabled) => _run(
    () => ref
        .read(championshipRepositoryProvider)
        .setSignup(_c.id!, enabled: enabled),
  );

  Future<void> _share() async {
    final code = _c.signupCode;
    if (code == null) return;
    await ref.read(shareTextProvider)(
      'Inscreva seu time no ${_c.name} pelo SportLeague: ${_url(code)}',
    );
  }

  Future<void> _answer(ChampionshipRequest request, bool accept) async {
    if (!accept) {
      final confirmed = await confirmAction(
        context,
        title: 'Recusar o ${request.name}?',
        message: 'Quem pediu recebe o aviso de que foi recusado.',
        confirmLabel: 'Recusar',
        confirmIcon: Icons.close,
      );
      if (!confirmed) return;
    }
    await _run(
      () => ref
          .read(championshipRepositoryProvider)
          .answerRequest(request.id, accept: accept),
    );
  }

  Future<void> _showRoster(ChampionshipRequest request) => showAppSheet<void>(
    context,
    builder: (_) => AppSheet(
      title: request.name,
      message: [
        if (request.contactName case final contact?) 'Responsável: $contact',
        '${request.players.length} '
            '${request.players.length == 1 ? 'atleta' : 'atletas'}',
      ].join('\n'),
      body: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 360),
        child: ListView(
          shrinkWrap: true,
          children: [for (final player in request.players) Text(player)],
        ),
      ),
      actions: const [SheetBackButton(label: 'Fechar')],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final code = _c.signupCode;
    final requests =
        ref.watch(championshipRequestsProvider(_c.id!)).value ?? const [];
    final pending = [
      for (final request in requests)
        if (request.status == RequestStatus.pending) request,
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.how_to_reg_outlined),
              title: const Text('Inscrição por link'),
              subtitle: const Text(
                'Times com ou sem conta pedem para entrar; você aprova.',
              ),
              value: _c.signupEnabled,
              onChanged: _busy ? null : _toggle,
            ),
            if (_c.signupEnabled && code != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _url(code),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Copiar link',
                      icon: const Icon(Icons.copy, size: 20),
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: _url(code)),
                        );
                        if (context.mounted) {
                          showErrorSnackBar(context, 'Link copiado.');
                        }
                      },
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _share,
                      icon: const Icon(Icons.share_outlined),
                      label: const Text('Compartilhar'),
                    ),
                  ],
                ),
              ),
            if (pending.isNotEmpty) ...[
              const Divider(height: 24),
              Text(
                '${pending.length} '
                '${pending.length == 1 ? 'pedido' : 'pedidos'} para responder',
                style: theme.textTheme.titleSmall,
              ),
              for (final request in pending)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: TeamLogo.url(logoUrl: request.logoUrl, radius: 18),
                  title: Text(request.name),
                  subtitle: Text(
                    request.hasAccount
                        ? 'Time no SportLeague · ${request.contactName ?? ''}'
                        : 'Sem conta · ${request.contactName ?? ''} · '
                              '${request.players.length} atletas',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: request.hasAccount ? null : () => _showRoster(request),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Recusar ${request.name}',
                        onPressed: _busy ? null : () => _answer(request, false),
                        icon: Icon(Icons.close, color: colors.error),
                      ),
                      IconButton.filledTonal(
                        tooltip: 'Aceitar ${request.name}',
                        onPressed: _busy ? null : () => _answer(request, true),
                        icon: const Icon(Icons.check),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
