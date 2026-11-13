import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sport_league/features/profile/data/profile_repository.dart';
import 'package:sport_league/features/profile/domain/profile.dart';
import 'package:sport_league/features/profile/presentation/public_profile_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Guarda o perfil como o banco: ligar, trocar o código e o nome de usuário
/// mudam o que o app lê de novo.
class _FakeProfileRepository implements ProfileRepository {
  _FakeProfileRepository(this.profile);

  Profile profile;
  final enabledCalls = <({bool enabled, bool newLink})>[];
  final handles = <String>[];

  /// Nomes de outras pessoas.
  final taken = {'ana'};

  Profile _copy({bool? enabled, String? slug, String? handle}) => Profile(
    id: profile.id,
    fullName: profile.fullName,
    role: profile.role,
    plan: profile.plan,
    publicEnabled: enabled ?? profile.publicEnabled,
    publicSlug: slug ?? profile.publicSlug,
    publicHandle: handle,
  );

  @override
  Future<String> setPublicProfile({
    required bool enabled,
    bool newLink = false,
  }) async {
    enabledCalls.add((enabled: enabled, newLink: newLink));
    final slug = newLink || profile.publicSlug == null
        ? 'novo${enabledCalls.length}abcd'
        : profile.publicSlug!;
    profile = _copy(enabled: enabled, slug: slug, handle: profile.publicHandle);
    return slug;
  }

  @override
  Future<String?> setPublicHandle(String handle) async {
    handles.add(handle);
    if (taken.contains(handle)) {
      throw const PostgrestException(
        message: 'Esse nome de usuário já está em uso.',
        code: 'P0001',
      );
    }
    final saved = handle.isEmpty ? null : handle;
    profile = _copy(handle: saved);
    return saved;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Profile _profile({bool enabled = false, String? slug, String? handle}) =>
    Profile(
      id: 'u1',
      fullName: 'Bruno Silva',
      role: UserRole.player,
      plan: SubscriptionPlan.free,
      publicEnabled: enabled,
      publicSlug: slug,
      publicHandle: handle,
    );

Future<_FakeProfileRepository> _pump(
  WidgetTester tester,
  Profile profile,
) async {
  final profiles = _FakeProfileRepository(profile);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentProfileProvider.overrideWith((ref) async => profiles.profile),
        profileRepositoryProvider.overrideWithValue(profiles),
      ],
      child: const MaterialApp(home: PublicProfilePage()),
    ),
  );
  await tester.pumpAndSettle();
  return profiles;
}

void main() {
  testWidgets('desligado, não mostra links; ligar chama o banco', (
    tester,
  ) async {
    final profiles = await _pump(tester, _profile());
    expect(find.text('Perfil público'), findsWidgets);
    expect(find.text('Seu link'), findsNothing);
    expect(find.text('Nome de usuário'), findsNothing);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(profiles.enabledCalls, [(enabled: true, newLink: false)]);
    expect(find.text('Seu link'), findsOneWidget);
    expect(find.textContaining('/p/novo1abcd'), findsOneWidget);
  });

  testWidgets('salva o nome de usuário em minúsculas e mostra os dois links', (
    tester,
  ) async {
    final profiles = await _pump(
      tester,
      _profile(enabled: true, slug: 'k7m2xq9a1b'),
    );
    expect(find.textContaining('/p/k7m2xq9a1b'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Bruno.Silva');
    await tester.pump();
    await tester.tap(find.text('Salvar nome'));
    await tester.pumpAndSettle();

    expect(profiles.handles, ['bruno.silva']);
    expect(find.text('Seu link'), findsOneWidget);
    expect(find.text('Link com código'), findsOneWidget);
    expect(find.textContaining('/@bruno.silva'), findsOneWidget);
    expect(find.textContaining('/p/k7m2xq9a1b'), findsOneWidget);
  });

  testWidgets('nome já em uso mostra o aviso do banco', (tester) async {
    final profiles = await _pump(
      tester,
      _profile(enabled: true, slug: 'k7m2xq9a1b'),
    );
    await tester.enterText(find.byType(TextField), 'ana');
    await tester.pump();
    await tester.tap(find.text('Salvar nome'));
    await tester.pumpAndSettle();

    expect(profiles.handles, ['ana']);
    expect(find.text('Esse nome de usuário já está em uso.'), findsOneWidget);
    expect(find.textContaining('/@ana'), findsNothing);
  });

  testWidgets('trocar o código pede confirmação e mantém o nome', (
    tester,
  ) async {
    final profiles = await _pump(
      tester,
      _profile(enabled: true, slug: 'k7m2xq9a1b', handle: 'bruno'),
    );
    expect(find.textContaining('/@bruno'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Trocar código'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Trocar código'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trocar').last);
    await tester.pumpAndSettle();

    expect(profiles.enabledCalls, [(enabled: true, newLink: true)]);
    expect(find.textContaining('/p/k7m2xq9a1b'), findsNothing);
    expect(find.textContaining('/@bruno'), findsOneWidget);
  });
}
