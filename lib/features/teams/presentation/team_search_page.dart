import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../data/team_repository.dart';
import '../domain/team.dart';
import 'team_logo.dart';

/// Botão de pesquisa da barra superior: abre a pesquisa de times.
class TeamSearchButton extends StatelessWidget {
  const TeamSearchButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Pesquisar times',
      icon: const Icon(Icons.search),
      onPressed: () => context.push(Routes.teamSearch),
    );
  }
}

/// Pesquisa de times da plataforma pelo nome; tocar num time abre o perfil.
class TeamSearchPage extends ConsumerStatefulWidget {
  const TeamSearchPage({super.key});

  @override
  ConsumerState<TeamSearchPage> createState() => _TeamSearchPageState();
}

class _TeamSearchPageState extends ConsumerState<TeamSearchPage> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  late Future<List<Team>> _results = _search('');

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<List<Team>> _search(String query) =>
      ref.read(teamRepositoryProvider).search(query);

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pesquisar times'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(72),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Nome do time',
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
          final teams = snapshot.data;
          if (snapshot.hasError) {
            return Center(
              child: TextButton.icon(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Erro ao pesquisar. Tentar novamente'),
              ),
            );
          }
          if (teams == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (teams.isEmpty) {
            return const Center(child: Text('Nenhum time encontrado.'));
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              for (final team in teams)
                Card(
                  child: ListTile(
                    leading: TeamLogo(team: team),
                    title: Text(team.name),
                    subtitle: Text([team.summary, ?team.location].join('\n')),
                    isThreeLine: team.location != null,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () =>
                        context.push(Routes.teamProfile, extra: team.id),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
