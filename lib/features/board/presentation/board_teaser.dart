import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../data/board_repository.dart';

/// Atalho do mural no Início: quantos avisos novos e o último publicado.
/// Sem mural (erro ou carregando), não aparece.
class BoardTeaser extends ConsumerWidget {
  const BoardTeaser({super.key, required this.teamId});

  final String teamId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final board = ref.watch(teamBoardProvider(teamId)).value;
    if (board == null) return const SizedBox.shrink();
    final latest = board.posts.firstOrNull;
    final unread = board.unread;
    return Card(
      child: ListTile(
        leading: Badge(
          label: Text('$unread'),
          isLabelVisible: unread > 0,
          child: const Icon(Icons.campaign_outlined),
        ),
        title: Text(
          unread == 0
              ? 'Mural'
              : 'Mural · $unread ${unread == 1 ? 'novo' : 'novos'}',
        ),
        subtitle: Text(
          switch (latest) {
            final post? => '${post.isPoll ? 'Enquete: ' : ''}${post.body}',
            null =>
              board.canManage
                  ? 'Publique avisos e enquetes para o time'
                  : 'Nenhum aviso ainda',
          },
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          await context.push(Routes.board);
          ref.invalidate(teamBoardProvider(teamId));
        },
      ),
    );
  }
}
