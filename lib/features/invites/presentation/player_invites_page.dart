import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../games/presentation/game_card.dart';
import '../../teams/data/team_repository.dart';
import '../../teams/domain/team.dart';
import '../../teams/presentation/team_logo.dart';
import '../data/invite_repository.dart';
import '../domain/team_invite.dart';

/// Convites do jogador: entrar num time com o código, os times dele e os
/// pedidos e convites.
class PlayerInvitesPage extends ConsumerStatefulWidget {
  const PlayerInvitesPage({super.key});

  @override
  ConsumerState<PlayerInvitesPage> createState() => _PlayerInvitesPageState();
}

class _PlayerInvitesPageState extends ConsumerState<PlayerInvitesPage> {
  final _codeController = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _refresh() => ref
    ..invalidate(myInvitesProvider)
    ..invalidate(myPlayerTeamsProvider);

  /// Mostra o time do código e entra nele, se o jogador confirmar.
  Future<void> _useCode() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.length != 8) {
      showErrorSnackBar(context, 'O código tem 8 letras e números.');
      return;
    }
    setState(() => _loading = true);
    try {
      final repository = ref.read(inviteRepositoryProvider);
      final teamId = await repository.teamIdByCode(code);
      final team = teamId == null
          ? null
          : await ref.read(teamRepositoryProvider).fetchById(teamId);
      if (!mounted) return;
      if (team == null) {
        showErrorSnackBar(
          context,
          'Código não encontrado. Confira com o time.',
        );
        return;
      }
      setState(() => _loading = false);
      final join = await showAppSheet<bool>(
        context,
        builder: (context) => AppSheet(
          title: 'Entrar no time?',
          message: 'Você vai entrar como atleta do ${team.name}.',
          body: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: TeamLogo(team: team, radius: 24),
            title: Text(team.name),
            subtitle: Text([team.summary, ?team.location].join('\n')),
          ),
          actions: [
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(true),
              icon: const Icon(Icons.group_add_outlined),
              label: const Text('Entrar no time'),
            ),
            const SheetBackButton(),
          ],
        ),
      );
      if (join != true || !mounted) return;
      setState(() => _loading = true);
      await repository.joinWithCode(code);
      _codeController.clear();
      _refresh();
      if (mounted) showErrorSnackBar(context, 'Você entrou no ${team.name}!');
    } catch (error) {
      if (mounted) {
        showErrorSnackBar(context, switch ('$error') {
          final message when message.contains('already in the team') =>
            'Você já é atleta desse time.',
          final message when message.contains('invalid invite code') =>
            'Código não encontrado. Confira com o time.',
          _ => friendlyErrorMessage(error),
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Aceitar (vira atleta do time) ou recusar um convite recebido.
  Future<void> _answer(TeamInvite invite, {required bool accept}) async {
    if (!accept) {
      final confirmed = await confirmAction(
        context,
        title: 'Recusar convite?',
        message: 'Você não vai entrar no ${invite.teamName ?? 'time'}.',
        confirmLabel: 'Recusar',
        confirmIcon: Icons.close,
        cancelLabel: 'Voltar',
      );
      if (!confirmed) return;
    }
    setState(() => _loading = true);
    try {
      await ref
          .read(inviteRepositoryProvider)
          .respond(invite.id, accept: accept);
      _refresh();
      if (accept && mounted) {
        showErrorSnackBar(context, 'Você entrou no ${invite.teamName}!');
      }
    } catch (error) {
      if (mounted) showErrorSnackBar(context, friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _cancel(TeamInvite invite) async {
    final confirmed = await confirmAction(
      context,
      title: 'Cancelar pedido?',
      message: 'O pedido para entrar no ${invite.teamName ?? 'time'} sai.',
      confirmLabel: 'Cancelar pedido',
      confirmIcon: Icons.close,
      cancelLabel: 'Voltar',
    );
    if (!confirmed) return;
    try {
      await ref.read(inviteRepositoryProvider).cancel(invite.id);
      _refresh();
    } catch (error) {
      if (mounted) showErrorSnackBar(context, friendlyErrorMessage(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final teams = ref.watch(myPlayerTeamsProvider).value ?? const <Team>[];
    final invites = ref.watch(myInvitesProvider).value ?? const <TeamInvite>[];

    return Scaffold(
      appBar: AppBar(title: const Text('Meus convites')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Entrar com código', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    'Peça o código ao administrador do time.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _codeController,
                    decoration: const InputDecoration(
                      labelText: 'Código do time',
                      prefixIcon: Icon(Icons.key_outlined),
                      counterText: '',
                    ),
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 8,
                    onSubmitted: (_) => _useCode(),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _loading ? null : _useCode,
                    icon: const Icon(Icons.login),
                    label: const Text('Continuar'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => context.push(Routes.teamSearch),
            icon: const Icon(Icons.search),
            label: const Text('Buscar times e pedir para entrar'),
          ),
          const SizedBox(height: 24),
          Text('Meus times', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (teams.isEmpty) const Text('Você ainda não está em nenhum time.'),
          for (final team in teams)
            Card(
              child: ListTile(
                leading: TeamLogo(team: team),
                title: Text(team.name),
                subtitle: Text(team.summary),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(Routes.teamProfile, extra: team.id),
              ),
            ),
          const SizedBox(height: 24),
          Text('Pedidos e convites', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (invites.isEmpty) const Text('Nenhum pedido ainda.'),
          for (final invite in invites)
            if (invite.isPending && !invite.isRequest)
              // Convite recebido: Aceitar ou Recusar à vista.
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 4, 0, 12),
                  child: Column(
                    children: [
                      ListTile(
                        leading: TeamLogo.url(logoUrl: invite.teamLogoUrl),
                        title: Text(invite.teamName ?? 'Time'),
                        subtitle: Text(
                          'Convidou você em ${formatGameDay(invite.createdAt)}',
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
                                onPressed: _loading
                                    ? null
                                    : () => _answer(invite, accept: false),
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
                                onPressed: _loading
                                    ? null
                                    : () => _answer(invite, accept: true),
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
              )
            else
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: TeamLogo.url(logoUrl: invite.teamLogoUrl),
                title: Text(invite.teamName ?? 'Time'),
                subtitle: Text(
                  '${invite.isRequest ? 'Seu pedido' : 'Convite'} · '
                  '${invite.status.label} · ${formatGameDay(invite.createdAt)}',
                ),
                trailing: invite.isPending && invite.isRequest
                    ? TextButton.icon(
                        onPressed: () => _cancel(invite),
                        icon: const Icon(Icons.close),
                        label: const Text('Cancelar'),
                      )
                    : null,
              ),
        ],
      ),
    );
  }
}
