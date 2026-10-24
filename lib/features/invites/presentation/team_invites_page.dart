import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../athletes/data/athlete_repository.dart';
import '../../games/presentation/game_card.dart';
import '../../teams/data/team_repository.dart';
import '../../teams/domain/team.dart';
import '../data/invite_repository.dart';
import '../domain/team_invite.dart';

/// Texto que vai no WhatsApp com o código do time.
String inviteMessage(Team team, String code) =>
    'Entre no time ${team.name} no SportLeague! No app, vá em '
    'Meus convites › Entrar com código e digite: $code';

/// Convites do time ativo (administrador): o código para mandar aos
/// jogadores e os pedidos para entrar no time.
class TeamInvitesPage extends ConsumerWidget {
  const TeamInvitesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final team = ref.watch(selectedTeamProvider).value;
    return Scaffold(
      appBar: AppBar(
        title: Text(team == null ? 'Convites' : 'Convites · ${team.name}'),
      ),
      body: team == null
          ? const Center(child: Text('Crie um time para convidar jogadores.'))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                _InviteCodeCard(team: team),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => context.push(Routes.invitePlayer),
                  icon: const Icon(Icons.person_search_outlined),
                  label: const Text('Convidar jogador do app'),
                ),
                const SizedBox(height: 24),
                _Requests(team: team),
                const SizedBox(height: 24),
                _SentInvites(team: team),
              ],
            ),
    );
  }
}

/// Código do time com Compartilhar, Copiar e Gerar outro.
class _InviteCodeCard extends ConsumerStatefulWidget {
  const _InviteCodeCard({required this.team});

  final Team team;

  @override
  ConsumerState<_InviteCodeCard> createState() => _InviteCodeCardState();
}

class _InviteCodeCardState extends ConsumerState<_InviteCodeCard> {
  bool _saving = false;

  Future<void> _regenerate() async {
    final confirmed = await confirmAction(
      context,
      title: 'Gerar outro código?',
      message:
          'O código atual deixa de valer: quem ainda não entrou vai precisar '
          'do novo. Quem já está no time continua.',
      confirmLabel: 'Gerar outro',
      confirmIcon: Icons.autorenew,
    );
    if (!confirmed) return;
    setState(() => _saving = true);
    try {
      await ref.read(inviteRepositoryProvider).regenerateCode(widget.team.id!);
      ref.invalidate(inviteCodeProvider(widget.team.id!));
    } catch (error) {
      if (mounted) showErrorSnackBar(context, friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final code = ref.watch(inviteCodeProvider(widget.team.id!)).value;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Convite para jogadores', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Mande o código para os jogadores. No app, eles entram em Meus '
              'convites › Entrar com código e já viram atletas do time.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: SelectableText(
                code ?? '········',
                semanticsLabel: code == null
                    ? 'Carregando o código'
                    : 'Código ${code.split('').join(' ')}',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 4,
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: code == null
                  ? null
                  : () => ref.read(shareTextProvider)(
                      inviteMessage(widget.team, code),
                    ),
              icon: const Icon(Icons.share_outlined),
              label: const Text('Compartilhar'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(88, 48),
                    ),
                    onPressed: code == null
                        ? null
                        : () async {
                            await Clipboard.setData(ClipboardData(text: code));
                            if (context.mounted) {
                              showErrorSnackBar(context, 'Código copiado.');
                            }
                          },
                    icon: const Icon(Icons.copy),
                    label: const Text('Copiar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(88, 48),
                    ),
                    onPressed: _saving || code == null ? null : _regenerate,
                    icon: const Icon(Icons.autorenew),
                    label: const Text('Gerar outro'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Pedidos para entrar: os pendentes com Aceitar/Recusar e os já respondidos.
class _Requests extends ConsumerWidget {
  const _Requests({required this.team});

  final Team team;

  Future<void> _respond(
    BuildContext context,
    WidgetRef ref,
    TeamInvite request, {
    required bool accept,
  }) async {
    if (!accept) {
      final confirmed = await confirmAction(
        context,
        title: 'Recusar pedido?',
        message: '${request.playerName ?? 'O jogador'} não vai entrar no time.',
        confirmLabel: 'Recusar',
        confirmIcon: Icons.close,
      );
      if (!confirmed) return;
    }
    try {
      await ref
          .read(inviteRepositoryProvider)
          .respond(request.id, accept: accept);
      ref
        ..invalidate(teamRequestsProvider(team.id!))
        ..invalidate(teamAthletesProvider(team.id!));
    } catch (error) {
      if (context.mounted) {
        showErrorSnackBar(context, friendlyErrorMessage(error));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return ref
        .watch(teamRequestsProvider(team.id!))
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => TextButton.icon(
            onPressed: () => ref.invalidate(teamRequestsProvider(team.id!)),
            icon: const Icon(Icons.refresh),
            label: const Text('Erro ao carregar os pedidos. Tentar novamente'),
          ),
          data: (requests) {
            final pending = [
              for (final request in requests)
                if (request.isPending) request,
            ];
            final answered = [
              for (final request in requests)
                if (!request.isPending) request,
            ];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Pedidos para entrar (${pending.length})',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (pending.isEmpty)
                  const Text('Nenhum pedido aguardando resposta.'),
                for (final request in pending)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(0, 4, 0, 12),
                      child: Column(
                        children: [
                          ListTile(
                            leading: _PlayerAvatar(request: request),
                            title: Text(request.playerName ?? 'Jogador'),
                            subtitle: Text(
                              'Pediu em ${formatGameDay(request.createdAt)}',
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      minimumSize: const Size(88, 48),
                                    ),
                                    onPressed: () => _respond(
                                      context,
                                      ref,
                                      request,
                                      accept: false,
                                    ),
                                    icon: const Icon(Icons.close),
                                    label: const Text('Recusar'),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                      minimumSize: const Size(88, 48),
                                    ),
                                    onPressed: () => _respond(
                                      context,
                                      ref,
                                      request,
                                      accept: true,
                                    ),
                                    icon: const Icon(Icons.check),
                                    label: const Text('Aceitar'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (answered.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Text('Histórico', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  for (final request in answered)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: _PlayerAvatar(request: request),
                      title: Text(request.playerName ?? 'Jogador'),
                      subtitle: Text(
                        '${request.status.label} · '
                        '${formatGameDay(request.respondedAt ?? request.createdAt)}',
                      ),
                    ),
                ],
              ],
            );
          },
        );
  }
}

/// Convites enviados a jogadores do app: os pendentes podem ser cancelados.
class _SentInvites extends ConsumerWidget {
  const _SentInvites({required this.team});

  final Team team;

  Future<void> _cancel(
    BuildContext context,
    WidgetRef ref,
    TeamInvite invite,
  ) async {
    final confirmed = await confirmAction(
      context,
      title: 'Cancelar convite?',
      message: 'O convite para ${invite.playerName ?? 'o jogador'} sai.',
      confirmLabel: 'Cancelar convite',
      confirmIcon: Icons.close,
      cancelLabel: 'Voltar',
    );
    if (!confirmed) return;
    try {
      await ref.read(inviteRepositoryProvider).cancel(invite.id);
      ref.invalidate(teamSentInvitesProvider(team.id!));
    } catch (error) {
      if (context.mounted) {
        showErrorSnackBar(context, friendlyErrorMessage(error));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final invites =
        ref.watch(teamSentInvitesProvider(team.id!)).value ??
        const <TeamInvite>[];
    if (invites.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Convites enviados', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final invite in invites)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: _PlayerAvatar(request: invite),
            title: Text(invite.playerName ?? 'Jogador'),
            subtitle: Text(
              '${invite.status.label} · '
              '${formatGameDay(invite.respondedAt ?? invite.createdAt)}',
            ),
            trailing: invite.isPending
                ? TextButton.icon(
                    onPressed: () => _cancel(context, ref, invite),
                    icon: const Icon(Icons.close),
                    label: const Text('Cancelar'),
                  )
                : null,
          ),
      ],
    );
  }
}

class _PlayerAvatar extends StatelessWidget {
  const _PlayerAvatar({required this.request});

  final TeamInvite request;

  @override
  Widget build(BuildContext context) {
    final avatarUrl = request.playerAvatarUrl;
    final name = request.playerName ?? '?';
    return CircleAvatar(
      foregroundImage: avatarUrl == null ? null : NetworkImage(avatarUrl),
      onForegroundImageError: avatarUrl == null ? null : (_, _) {},
      child: Text(name.isEmpty ? '?' : name[0].toUpperCase()),
    );
  }
}
