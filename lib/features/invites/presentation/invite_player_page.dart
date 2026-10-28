import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../../core/supabase/supabase_providers.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../athletes/data/athlete_repository.dart';
import '../../teams/data/team_repository.dart';
import '../data/invite_repository.dart';
import '../domain/team_invite.dart';

/// Pesquisa os jogadores do app pelo nome (ou o jogador e o técnico pelo
/// código pessoal, JG ou TC) e convida para o time ativo. Quem já está no
/// time ou já tem convite pendente aparece marcado.
class InvitePlayerPage extends ConsumerStatefulWidget {
  const InvitePlayerPage({super.key});

  @override
  ConsumerState<InvitePlayerPage> createState() => _InvitePlayerPageState();
}

class _InvitePlayerPageState extends ConsumerState<InvitePlayerPage> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  late Future<List<PlayerSummary>> _results = _search('');
  final _sending = <String>{};

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<List<PlayerSummary>> _search(String query) =>
      ref.read(inviteRepositoryProvider).searchPlayers(query);

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) _refresh();
    });
  }

  void _refresh() {
    final results = _search(_searchController.text);
    setState(() {
      _results = results;
    });
  }

  Future<void> _invite(String teamId, PlayerSummary player) async {
    final ownerId = ref.read(currentUserIdProvider);
    if (ownerId == null) return;
    setState(() => _sending.add(player.id));
    try {
      await ref
          .read(inviteRepositoryProvider)
          .invitePlayer(teamId: teamId, profileId: player.id, ownerId: ownerId);
      ref.invalidate(teamSentInvitesProvider(teamId));
      if (mounted) {
        showErrorSnackBar(context, 'Convite enviado a ${player.name}.');
      }
    } catch (error) {
      if (mounted) {
        showErrorSnackBar(
          context,
          error is PostgrestException && error.code == '23505'
              ? '${player.name} já tem um convite ou pedido pendente com o '
                    'time.'
              : friendlyErrorMessage(error),
        );
      }
    } finally {
      if (mounted) setState(() => _sending.remove(player.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final team = ref.watch(selectedTeamProvider).value;
    final teamId = team?.id;
    final athletes = teamId == null
        ? const <String>{}
        : {
            for (final athlete
                in ref.watch(teamAthletesProvider(teamId)).value ?? const [])
              ?athlete.profileId,
          };
    final coaches = teamId == null
        ? const <String>{}
        : {
            for (final coach
                in ref.watch(teamCoachesProvider(teamId)).value ?? const [])
              coach.id,
          };
    final invited = teamId == null
        ? const <String>{}
        : {
            for (final invite
                in ref.watch(teamSentInvitesProvider(teamId)).value ??
                    const <TeamInvite>[])
              if (invite.isPending) invite.profileId,
          };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Convidar jogador'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(72),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Nome do jogador ou código (JG ou TC)',
                prefixIcon: Icon(Icons.search),
              ),
              textInputAction: TextInputAction.search,
              onChanged: _onQueryChanged,
            ),
          ),
        ),
      ),
      body: FutureBuilder(
        future: _results,
        builder: (context, snapshot) {
          final players = snapshot.data;
          if (snapshot.hasError) {
            return Center(
              child: TextButton.icon(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Erro ao pesquisar. Tentar novamente'),
              ),
            );
          }
          if (players == null || teamId == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (players.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Nenhum jogador encontrado. Peça o código dele (Perfil › '
                  'Meu código); quem ainda não tem o app pode entrar com o '
                  'código do time.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              for (final player in players)
                Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      foregroundImage: switch (player.avatarUrl) {
                        final url? => NetworkImage(url),
                        null => null,
                      },
                      onForegroundImageError: player.avatarUrl == null
                          ? null
                          : (_, _) {},
                      child: Text(player.name[0].toUpperCase()),
                    ),
                    title: Text(player.name),
                    subtitle: player.isCoach ? const Text('Técnico') : null,
                    trailing: switch ((
                      athletes.contains(player.id) ||
                          coaches.contains(player.id),
                      invited.contains(player.id),
                    )) {
                      (true, _) => const Chip(
                        avatar: Icon(Icons.verified_outlined, size: 18),
                        label: Text('No time'),
                      ),
                      (false, true) => const Chip(
                        avatar: Icon(Icons.hourglass_top, size: 18),
                        label: Text('Convidado'),
                      ),
                      _ => FilledButton.icon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(88, 40),
                        ),
                        onPressed: _sending.contains(player.id)
                            ? null
                            : () => _invite(teamId, player),
                        icon: const Icon(Icons.person_add_alt_1_outlined),
                        label: const Text('Convidar'),
                      ),
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
