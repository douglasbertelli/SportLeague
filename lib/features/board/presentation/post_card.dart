import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/error_messages.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../games/presentation/game_card.dart'
    show formatGameDay, formatGameTime;
import '../../notifications/domain/app_notification.dart' show timeAgo;
import '../../teams/domain/team.dart';
import '../data/board_repository.dart';
import '../domain/board_post.dart';

/// Um aviso ou enquete do mural: autor, texto, a enquete com as barras de
/// votos, as reações e os comentários. O dono e os técnicos têm o menu
/// (fixar, quem leu, lembrar quem não votou, apagar).
class PostCard extends ConsumerStatefulWidget {
  const PostCard({
    super.key,
    required this.team,
    required this.post,
    required this.canManage,
    this.onOpen,
  });

  final Team team;
  final BoardPost post;
  final bool canManage;

  /// Abre a página do aviso (comentários). Nulo dentro dela.
  final VoidCallback? onOpen;

  @override
  ConsumerState<PostCard> createState() => _PostCardState();
}

class _PostCardState extends ConsumerState<PostCard> {
  bool _busy = false;

  BoardRepository get _repository => ref.read(boardRepositoryProvider);

  void _refresh() => ref.invalidate(teamBoardProvider(widget.team.id!));

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      _refresh();
    } catch (error) {
      if (mounted) showErrorSnackBar(context, friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Voto: numa enquete de uma resposta, tocar troca o voto (ou tira, se
  /// tocar na mesma); na de várias, liga e desliga a opção.
  Future<void> _vote(PollOption option) {
    final post = widget.post;
    final mine = [
      for (final other in post.options)
        if (other.mine) other.id,
    ];
    final next = post.multiple
        ? (option.mine
              ? [
                  for (final id in mine)
                    if (id != option.id) id,
                ]
              : [...mine, option.id])
        : (option.mine ? <String>[] : [option.id]);
    return _run(() => _repository.vote(post.id, next));
  }

  Future<void> _menu(String action) async {
    final post = widget.post;
    switch (action) {
      case 'pin':
        await _run(() => _repository.setPinned(post.id, pinned: !post.pinned));
      case 'readers':
        await showAppSheet<void>(
          context,
          builder: (_) => _ReadersSheet(postId: post.id),
        );
      case 'remind':
        try {
          final count = await _repository.remind(post.id);
          if (mounted) {
            showErrorSnackBar(
              context,
              count == 0
                  ? 'Todo mundo já votou.'
                  : 'Lembrete enviado para $count '
                        '${count == 1 ? 'pessoa' : 'pessoas'}.',
            );
          }
          _refresh();
        } catch (error) {
          if (mounted) showErrorSnackBar(context, friendlyErrorMessage(error));
        }
      case 'delete':
        final confirmed = await confirmDelete(
          context,
          title: post.isPoll ? 'Apagar a enquete?' : 'Apagar o aviso?',
          message: 'Sai do mural com as reações, os comentários e os votos.',
        );
        if (confirmed && mounted) await _run(() => _repository.delete(post.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final post = widget.post;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: colors.onSurfaceVariant,
    );

    return Card(
      margin: EdgeInsets.zero,
      shape: post.pinned
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: colors.primary, width: 1.5),
            )
          : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: widget.onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: colors.primaryContainer,
                    child: Icon(
                      post.isPoll
                          ? Icons.poll_outlined
                          : Icons.campaign_outlined,
                      size: 18,
                      color: colors.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          post.authorName,
                          style: theme.textTheme.titleSmall,
                        ),
                        Text(
                          [
                            if (post.isPoll) 'Enquete' else 'Aviso',
                            timeAgo(post.createdAt),
                          ].join(' · '),
                          style: muted,
                        ),
                      ],
                    ),
                  ),
                  if (post.pinned)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(
                        Icons.push_pin,
                        size: 18,
                        color: colors.primary,
                        semanticLabel: 'Fixado',
                      ),
                    ),
                  if (!post.readByMe)
                    Container(
                      margin: const EdgeInsets.only(right: 4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: colors.primary,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'Novo',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.onPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  if (widget.canManage)
                    PopupMenuButton<String>(
                      tooltip: 'Opções',
                      onSelected: _menu,
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'pin',
                          child: ListTile(
                            leading: Icon(
                              post.pinned
                                  ? Icons.push_pin_outlined
                                  : Icons.push_pin,
                            ),
                            title: Text(
                              post.pinned ? 'Soltar do topo' : 'Fixar no topo',
                            ),
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'readers',
                          child: ListTile(
                            leading: Icon(Icons.done_all),
                            title: Text('Quem leu'),
                          ),
                        ),
                        if (post.isPoll && !post.closed)
                          const PopupMenuItem(
                            value: 'remind',
                            child: ListTile(
                              leading: Icon(
                                Icons.notifications_active_outlined,
                              ),
                              title: Text('Lembrar quem não votou'),
                            ),
                          ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: ListTile(
                            leading: Icon(Icons.delete_outline),
                            title: Text('Apagar'),
                          ),
                        ),
                      ],
                    )
                  else
                    const SizedBox(width: 8),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 12, 8, 0),
                child: Text(post.body, style: theme.textTheme.bodyLarge),
              ),
              if (post.isPoll) ...[
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _Poll(
                    post: post,
                    enabled: !_busy && !post.closed,
                    onVote: _vote,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        for (final emoji in boardReactions)
                          _ReactionChip(
                            emoji: emoji,
                            count: post.reaction(emoji).$1,
                            mine: post.reaction(emoji).$2,
                            onTap: _busy
                                ? null
                                : () => _run(
                                    () => _repository.toggleReaction(
                                      post.id,
                                      emoji,
                                    ),
                                  ),
                          ),
                      ],
                    ),
                  ),
                  if (widget.onOpen != null)
                    TextButton.icon(
                      onPressed: widget.onOpen,
                      icon: const Icon(Icons.chat_bubble_outline, size: 18),
                      label: Text('${post.commentsCount}'),
                    ),
                ],
              ),
              if (widget.canManage)
                Text(
                  'Lido por ${post.readCount} '
                  '${post.readCount == 1 ? 'pessoa' : 'pessoas'}',
                  style: muted,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opções da enquete: barra com a porcentagem, o voto de quem vê marcado e,
/// fora da anônima, quem votou.
class _Poll extends StatelessWidget {
  const _Poll({
    required this.post,
    required this.enabled,
    required this.onVote,
  });

  final BoardPost post;
  final bool enabled;
  final void Function(PollOption option) onVote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final total = post.totalVotes;
    final closesAt = post.closesAt;
    final info = [
      '${post.votersCount} ${post.votersCount == 1 ? 'voto' : 'votos'}',
      if (post.multiple) 'várias respostas',
      if (post.anonymous) 'anônima',
      if (post.closed)
        'encerrada'
      else if (closesAt != null)
        'fecha ${formatGameDay(closesAt)} às ${formatGameTime(closesAt)}',
    ].join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final option in post.options) ...[
          Semantics(
            button: enabled,
            selected: option.mine,
            label:
                '${option.label}, ${option.votes} '
                '${option.votes == 1 ? 'voto' : 'votos'}',
            excludeSemantics: true,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: enabled ? () => onVote(option) : null,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: option.mine ? colors.primary : colors.outlineVariant,
                    width: option.mine ? 1.5 : 1,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    // Barra da porcentagem, atrás do texto.
                    Positioned.fill(
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: total == 0 ? 0 : option.votes / total,
                        child: ColoredBox(
                          color: option.mine
                              ? colors.primaryContainer
                              : colors.surfaceContainerHighest,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            post.multiple
                                ? (option.mine
                                      ? Icons.check_box
                                      : Icons.check_box_outline_blank)
                                : (option.mine
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_unchecked),
                            size: 20,
                            color: option.mine
                                ? colors.primary
                                : colors.onSurfaceVariant,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  option.label,
                                  style: option.mine
                                      ? const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        )
                                      : null,
                                ),
                                if (option.voters.isNotEmpty)
                                  Text(
                                    _voters(option.voters),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Text(
                            total == 0
                                ? '0%'
                                : '${(option.votes * 100 / total).round()}%',
                            style: theme.textTheme.labelLarge,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        Text(
          info,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  /// "Zé, Tico e mais 3".
  static String _voters(List<String> names) => names.length <= 3
      ? names.join(', ')
      : '${names.take(2).join(', ')} e mais ${names.length - 2}';
}

class _ReactionChip extends StatelessWidget {
  const _ReactionChip({
    required this.emoji,
    required this.count,
    required this.mine,
    this.onTap,
  });

  final String emoji;
  final int count;
  final bool mine;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: mine,
      label: 'Reagir com $emoji, $count',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: mine ? colors.primaryContainer : null,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: mine ? colors.primary : colors.outlineVariant,
            ),
          ),
          child: Text(count == 0 ? emoji : '$emoji $count'),
        ),
      ),
    );
  }
}

/// Quem já leu e quem ainda não leu o aviso.
class _ReadersSheet extends ConsumerWidget {
  const _ReadersSheet({required this.postId});

  final String postId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final readers = ref.watch(postReadersProvider(postId));
    return AppSheet(
      title: 'Quem leu',
      body: readers.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (_, _) => const Text('Não foi possível carregar.'),
        data: (readers) {
          final read = readers.where((reader) => reader.readAt != null);
          final unread = readers.where((reader) => reader.readAt == null);
          return ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 420),
            child: ListView(
              shrinkWrap: true,
              children: [
                Text(
                  'Leram (${read.length})',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                for (final reader in read)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.done_all, size: 20),
                    title: Text(reader.name),
                    trailing: Text(timeAgo(reader.readAt!)),
                  ),
                const SizedBox(height: 12),
                Text(
                  'Ainda não leram (${unread.length})',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                for (final reader in unread)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.schedule, size: 20),
                    title: Text(reader.name),
                  ),
              ],
            ),
          );
        },
      ),
      actions: const [SheetBackButton(label: 'Fechar')],
    );
  }
}
