import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sport_league/features/board/data/board_repository.dart';
import 'package:sport_league/features/board/domain/board_post.dart';
import 'package:sport_league/features/board/presentation/post_card.dart';
import 'package:sport_league/features/teams/domain/team.dart';

/// Mural em memória: guarda os votos e as reações pedidos.
class FakeBoardRepository implements BoardRepository {
  final votes = <(String, List<String>)>[];
  final reactions = <(String, String)>[];

  @override
  Future<void> vote(String postId, List<String> optionIds) async =>
      votes.add((postId, optionIds));

  @override
  Future<void> toggleReaction(String postId, String emoji) async =>
      reactions.add((postId, emoji));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, dynamic> _poll({bool multiple = false, bool mine = false}) => {
  'id': 'p1',
  'kind': 'poll',
  'body': 'Churrasco sábado ou domingo?',
  'pinned': true,
  'multiple': multiple,
  'anonymous': false,
  'closes_at': null,
  'closed': false,
  'created_at': '2026-11-25T12:00:00Z',
  'author': {'id': 'u1', 'name': 'Douglas'},
  'read_by_me': false,
  'read_count': 3,
  'comments_count': 2,
  'voters_count': 3,
  'options': [
    {
      'id': 'o1',
      'label': 'Sábado',
      'votes': 2,
      'mine': mine,
      'voters': ['Zé', 'Tico'],
    },
    {'id': 'o2', 'label': 'Domingo', 'votes': 1, 'mine': false, 'voters': []},
  ],
  'reactions': [
    {'emoji': '👍', 'count': 2, 'mine': true},
  ],
};

void main() {
  test('lê o mural do banco', () {
    final board = TeamBoard.fromMap({
      'can_manage': true,
      'posts': [_poll()],
    });
    expect(board.canManage, isTrue);
    expect(board.unread, 1);
    final post = board.posts.single;
    expect(post.isPoll, isTrue);
    expect(post.pinned, isTrue);
    expect(post.totalVotes, 3);
    expect(post.votedByMe, isFalse);
    expect(post.reaction('👍'), (2, true));
    expect(post.reaction('⚽'), (0, false));
    expect(post.options.first.voters, ['Zé', 'Tico']);
  });

  Future<FakeBoardRepository> pumpCard(
    WidgetTester tester,
    BoardPost post,
  ) async {
    final repository = FakeBoardRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [boardRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PostCard(
                team: const Team(id: 't1', name: 'Unidos FC', ownerId: 'u1'),
                post: post,
                canManage: true,
              ),
            ),
          ),
        ),
      ),
    );
    return repository;
  }

  testWidgets('enquete de uma resposta: tocar vota e tocar de novo tira', (
    tester,
  ) async {
    final repository = await pumpCard(tester, BoardPost.fromMap(_poll()));
    expect(find.text('67%'), findsOneWidget);
    expect(find.text('Zé, Tico'), findsOneWidget);
    expect(find.text('Novo'), findsOneWidget);
    expect(find.text('Lido por 3 pessoas'), findsOneWidget);

    await tester.tap(find.text('Domingo'));
    await tester.pumpAndSettle();
    expect(repository.votes.single.$2, ['o2']);

    final voted = await pumpCard(tester, BoardPost.fromMap(_poll(mine: true)));
    await tester.tap(find.text('Sábado'));
    await tester.pumpAndSettle();
    expect(voted.votes.single.$2, isEmpty);
  });

  testWidgets('várias respostas: soma a opção ao voto', (tester) async {
    final repository = await pumpCard(
      tester,
      BoardPost.fromMap(_poll(multiple: true, mine: true)),
    );
    await tester.tap(find.text('Domingo'));
    await tester.pumpAndSettle();
    expect(repository.votes.single.$2, ['o1', 'o2']);
  });

  testWidgets('reação liga e desliga', (tester) async {
    final repository = await pumpCard(tester, BoardPost.fromMap(_poll()));
    await tester.tap(find.text('⚽'));
    await tester.pumpAndSettle();
    expect(repository.reactions.single, ('p1', '⚽'));
  });
}
