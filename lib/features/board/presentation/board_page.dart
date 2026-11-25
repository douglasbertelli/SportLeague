import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/empty_state.dart';
import '../../fundraisers/presentation/fundraisers_page.dart'
    show fundraiserTeamsProvider;
import '../../teams/data/team_repository.dart';
import '../../teams/domain/team.dart';
import '../../teams/presentation/team_logo.dart';
import '../data/board_repository.dart';
import '../domain/board_post.dart';
import 'post_card.dart';

/// Argumentos do formulário de publicação.
typedef BoardFormArgs = ({Team team, BoardPostKind kind});

/// Argumentos da página de um aviso (comentários).
typedef BoardPostArgs = ({Team team, String postId});

/// Mural do time: avisos e enquetes. Abre no time ativo; quem está em mais de
/// um time troca pelos chips do topo. O dono e os técnicos publicam.
class BoardPage extends ConsumerStatefulWidget {
  const BoardPage({super.key});

  @override
  ConsumerState<BoardPage> createState() => _BoardPageState();
}

class _BoardPageState extends ConsumerState<BoardPage> {
  String? _teamId;

  @override
  Widget build(BuildContext context) {
    final teams = ref.watch(fundraiserTeamsProvider);
    final selectedId = ref.watch(selectedTeamProvider).value?.id;

    return Scaffold(
      appBar: AppBar(title: const Text('Mural')),
      body: teams.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: TextButton.icon(
            onPressed: () => ref.invalidate(fundraiserTeamsProvider),
            icon: const Icon(Icons.refresh),
            label: const Text('Erro ao carregar os times. Tentar novamente'),
          ),
        ),
        data: (teams) {
          if (teams.isEmpty) {
            return const EmptyState(
              icon: Icons.campaign_outlined,
              title: 'Nenhum time',
              message: 'O mural fica no time. Entre num time para ver.',
            );
          }
          final team =
              teams.where((team) => team.id == _teamId).firstOrNull ??
              teams.where((team) => team.id == selectedId).firstOrNull ??
              teams.first;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (teams.length > 1)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(
                    children: [
                      for (final option in teams)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            avatar: TeamLogo(team: option, radius: 12),
                            label: Text(option.name),
                            selected: option.id == team.id,
                            onSelected: (_) =>
                                setState(() => _teamId = option.id),
                          ),
                        ),
                    ],
                  ),
                ),
              Expanded(child: _TeamBoard(team: team)),
            ],
          );
        },
      ),
    );
  }
}

class _TeamBoard extends ConsumerStatefulWidget {
  const _TeamBoard({required this.team});

  final Team team;

  @override
  ConsumerState<_TeamBoard> createState() => _TeamBoardState();
}

class _TeamBoardState extends ConsumerState<_TeamBoard> {
  /// Avisos já marcados como lidos nesta tela (não marca de novo).
  final _marked = <String>{};

  /// Marca como lidos os avisos que apareceram (o "Novo" continua até sair
  /// da tela).
  void _markRead(TeamBoard board) {
    final unread = [
      for (final post in board.posts)
        if (!post.readByMe && _marked.add(post.id)) post.id,
    ];
    if (unread.isEmpty) return;
    ref.read(boardRepositoryProvider).markRead(unread).ignore();
  }

  Future<void> _publish(BuildContext context) async {
    final kind = await showAppSheet<BoardPostKind>(
      context,
      builder: (context) => AppSheet(
        title: 'Publicar no mural',
        body: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.campaign_outlined),
              title: const Text('Aviso'),
              subtitle: const Text('Recado para o time, pode ficar fixado'),
              onTap: () => Navigator.of(context).pop(BoardPostKind.notice),
            ),
            ListTile(
              leading: const Icon(Icons.poll_outlined),
              title: const Text('Enquete'),
              subtitle: const Text('Opções para o time votar'),
              onTap: () => Navigator.of(context).pop(BoardPostKind.poll),
            ),
          ],
        ),
        actions: const [SheetBackButton()],
      ),
    );
    if (kind == null || !context.mounted) return;
    await context.push(
      Routes.boardForm,
      extra: (team: widget.team, kind: kind),
    );
    ref.invalidate(teamBoardProvider(widget.team.id!));
  }

  @override
  Widget build(BuildContext context) {
    final team = widget.team;
    final board = ref.watch(teamBoardProvider(team.id!));
    final canManage = board.value?.canManage ?? false;

    return Scaffold(
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              heroTag: null,
              onPressed: () => _publish(context),
              icon: const Icon(Icons.add),
              label: const Text('Publicar'),
            )
          : null,
      body: board.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: TextButton.icon(
            onPressed: () => ref.invalidate(teamBoardProvider(team.id!)),
            icon: const Icon(Icons.refresh),
            label: const Text('Erro ao carregar o mural. Tentar novamente'),
          ),
        ),
        data: (board) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _markRead(board);
          });
          if (board.posts.isEmpty) {
            return EmptyState(
              icon: Icons.campaign_outlined,
              title: 'Mural vazio',
              message: board.canManage
                  ? 'Publique avisos e enquetes para o time.'
                  : 'Os avisos e enquetes do time aparecem aqui.',
            );
          }
          return RefreshIndicator(
            onRefresh: () => ref.refresh(teamBoardProvider(team.id!).future),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              itemCount: board.posts.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) => PostCard(
                team: team,
                post: board.posts[index],
                canManage: board.canManage,
                onOpen: () => context.push(
                  Routes.boardPost,
                  extra: (team: team, postId: board.posts[index].id),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
