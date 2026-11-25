/// Mural do time (função team_board): se quem vê publica e os avisos.
class TeamBoard {
  const TeamBoard({required this.canManage, required this.posts});

  factory TeamBoard.fromMap(Map<String, dynamic> map) => TeamBoard(
    canManage: map['can_manage'] as bool? ?? false,
    posts: [
      for (final post in map['posts'] as List<dynamic>? ?? const [])
        BoardPost.fromMap(post as Map<String, dynamic>),
    ],
  );

  /// Dono ou técnico: publica, fixa, apaga e vê quem leu.
  final bool canManage;
  final List<BoardPost> posts;

  /// Avisos que quem vê ainda não leu.
  int get unread => posts.where((post) => !post.readByMe).length;
}

enum BoardPostKind { notice, poll }

/// Reações possíveis nos avisos.
const boardReactions = ['👍', '❤️', '😂', '⚽'];

/// Um aviso ou enquete do mural.
class BoardPost {
  const BoardPost({
    required this.id,
    required this.kind,
    required this.body,
    required this.createdAt,
    required this.authorName,
    this.pinned = false,
    this.multiple = false,
    this.anonymous = false,
    this.closesAt,
    this.closed = false,
    this.readByMe = false,
    this.readCount = 0,
    this.commentsCount = 0,
    this.votersCount = 0,
    this.options = const [],
    this.reactions = const [],
  });

  factory BoardPost.fromMap(Map<String, dynamic> map) => BoardPost(
    id: map['id'] as String,
    kind: map['kind'] == 'poll' ? BoardPostKind.poll : BoardPostKind.notice,
    body: map['body'] as String,
    createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
    authorName: switch (map['author']) {
      {'name': final String name} => name,
      _ => 'Alguém',
    },
    pinned: map['pinned'] as bool? ?? false,
    multiple: map['multiple'] as bool? ?? false,
    anonymous: map['anonymous'] as bool? ?? false,
    closesAt: switch (map['closes_at']) {
      final String at => DateTime.parse(at).toLocal(),
      _ => null,
    },
    closed: map['closed'] as bool? ?? false,
    readByMe: map['read_by_me'] as bool? ?? false,
    readCount: (map['read_count'] as num?)?.toInt() ?? 0,
    commentsCount: (map['comments_count'] as num?)?.toInt() ?? 0,
    votersCount: (map['voters_count'] as num?)?.toInt() ?? 0,
    options: [
      for (final option in map['options'] as List<dynamic>? ?? const [])
        PollOption.fromMap(option as Map<String, dynamic>),
    ],
    reactions: [
      for (final reaction in map['reactions'] as List<dynamic>? ?? const [])
        PostReaction.fromMap(reaction as Map<String, dynamic>),
    ],
  );

  final String id;
  final BoardPostKind kind;
  final String body;
  final DateTime createdAt;
  final String authorName;
  final bool pinned;

  /// Enquete: aceita várias respostas.
  final bool multiple;

  /// Enquete: mostra só a contagem, sem quem votou.
  final bool anonymous;

  /// Enquete: prazo para votar (nulo: sem prazo).
  final DateTime? closesAt;
  final bool closed;
  final bool readByMe;
  final int readCount;
  final int commentsCount;

  /// Enquete: quantas pessoas votaram.
  final int votersCount;
  final List<PollOption> options;
  final List<PostReaction> reactions;

  bool get isPoll => kind == BoardPostKind.poll;

  /// Se quem vê já votou.
  bool get votedByMe => options.any((option) => option.mine);

  /// Total de votos (com várias respostas, passa do número de pessoas).
  int get totalVotes =>
      options.fold(0, (total, option) => total + option.votes);

  /// Contagem de cada reação (zero se ninguém reagiu) e se quem vê reagiu.
  (int, bool) reaction(String emoji) => switch (reactions
      .where((reaction) => reaction.emoji == emoji)
      .firstOrNull) {
    final reaction? => (reaction.count, reaction.mine),
    null => (0, false),
  };
}

class PollOption {
  const PollOption({
    required this.id,
    required this.label,
    this.votes = 0,
    this.mine = false,
    this.voters = const [],
  });

  factory PollOption.fromMap(Map<String, dynamic> map) => PollOption(
    id: map['id'] as String,
    label: map['label'] as String,
    votes: (map['votes'] as num?)?.toInt() ?? 0,
    mine: map['mine'] as bool? ?? false,
    voters: [
      for (final name in map['voters'] as List<dynamic>? ?? const [])
        name as String,
    ],
  );

  final String id;
  final String label;
  final int votes;
  final bool mine;

  /// Quem votou (vazio na enquete anônima).
  final List<String> voters;
}

class PostReaction {
  const PostReaction({
    required this.emoji,
    required this.count,
    required this.mine,
  });

  factory PostReaction.fromMap(Map<String, dynamic> map) => PostReaction(
    emoji: map['emoji'] as String,
    count: (map['count'] as num?)?.toInt() ?? 0,
    mine: map['mine'] as bool? ?? false,
  );

  final String emoji;
  final int count;
  final bool mine;
}

/// Comentário de um aviso.
class PostComment {
  const PostComment({
    required this.id,
    required this.body,
    required this.createdAt,
    required this.authorName,
    this.mine = false,
    this.canDelete = false,
  });

  factory PostComment.fromMap(Map<String, dynamic> map) => PostComment(
    id: map['id'] as String,
    body: map['body'] as String,
    createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
    authorName: map['author_name'] as String? ?? 'Alguém',
    mine: map['mine'] as bool? ?? false,
    canDelete: map['can_delete'] as bool? ?? false,
  );

  final String id;
  final String body;
  final DateTime createdAt;
  final String authorName;
  final bool mine;
  final bool canDelete;
}

/// Quem leu (ou ainda não leu) um aviso.
class PostReader {
  const PostReader({required this.name, this.readAt});

  factory PostReader.fromMap(Map<String, dynamic> map) => PostReader(
    name: map['name'] as String? ?? 'Alguém',
    readAt: switch (map['read_at']) {
      final String at => DateTime.parse(at).toLocal(),
      _ => null,
    },
  );

  final String name;
  final DateTime? readAt;
}
