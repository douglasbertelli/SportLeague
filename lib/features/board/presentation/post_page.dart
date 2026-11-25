import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/error_messages.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../notifications/domain/app_notification.dart' show timeAgo;
import '../../teams/domain/team.dart';
import '../data/board_repository.dart';
import 'post_card.dart';

/// Um aviso com os comentários e o campo para comentar.
class PostPage extends ConsumerStatefulWidget {
  const PostPage({super.key, required this.team, required this.postId});

  final Team team;
  final String postId;

  @override
  ConsumerState<PostPage> createState() => _PostPageState();
}

class _PostPageState extends ConsumerState<PostPage> {
  final _comment = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  void _refresh() => ref
    ..invalidate(postCommentsProvider(widget.postId))
    ..invalidate(teamBoardProvider(widget.team.id!));

  Future<void> _send() async {
    final text = _comment.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await ref.read(boardRepositoryProvider).addComment(widget.postId, text);
      _comment.clear();
      _refresh();
    } catch (error) {
      if (mounted) showErrorSnackBar(context, friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final board = ref.watch(teamBoardProvider(widget.team.id!));
    final comments = ref.watch(postCommentsProvider(widget.postId));
    final post = board.value?.posts
        .where((post) => post.id == widget.postId)
        .firstOrNull;

    return Scaffold(
      appBar: AppBar(title: Text(post?.isPoll ?? false ? 'Enquete' : 'Aviso')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (post != null)
                  PostCard(
                    team: widget.team,
                    post: post,
                    canManage: board.value?.canManage ?? false,
                  )
                else if (board.isLoading)
                  const Center(child: CircularProgressIndicator())
                else
                  const Text('Este aviso não está mais no mural.'),
                const SizedBox(height: 20),
                Text('Comentários', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                comments.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (_, _) => TextButton.icon(
                    onPressed: () =>
                        ref.invalidate(postCommentsProvider(widget.postId)),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Erro ao carregar. Tentar novamente'),
                  ),
                  data: (comments) => comments.isEmpty
                      ? Text(
                          'Nenhum comentário ainda.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        )
                      : Column(
                          children: [
                            for (final comment in comments)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: CircleAvatar(
                                  radius: 16,
                                  child: Text(
                                    comment.authorName.characters.first
                                        .toUpperCase(),
                                  ),
                                ),
                                title: Text(
                                  '${comment.authorName} · '
                                  '${timeAgo(comment.createdAt)}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                subtitle: Text(
                                  comment.body,
                                  style: theme.textTheme.bodyMedium,
                                ),
                                trailing: comment.canDelete
                                    ? IconButton(
                                        tooltip: 'Apagar comentário',
                                        icon: const Icon(Icons.delete_outline),
                                        onPressed: () async {
                                          final confirmed = await confirmDelete(
                                            context,
                                            title: 'Apagar o comentário?',
                                            message:
                                                'Sai da conversa do aviso.',
                                          );
                                          if (!confirmed) return;
                                          try {
                                            await ref
                                                .read(boardRepositoryProvider)
                                                .deleteComment(comment.id);
                                            _refresh();
                                          } catch (error) {
                                            if (context.mounted) {
                                              showErrorSnackBar(
                                                context,
                                                friendlyErrorMessage(error),
                                              );
                                            }
                                          }
                                        },
                                      )
                                    : null,
                              ),
                          ],
                        ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _comment,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 1000,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'Escreva um comentário',
                        counterText: '',
                      ),
                    ),
                  ),
                  IconButton.filled(
                    tooltip: 'Enviar comentário',
                    onPressed: _sending ? null : _send,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
