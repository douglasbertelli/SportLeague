import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../data/venue_repository.dart';
import '../domain/venue.dart';
import 'venue_photo.dart';

/// Locais das partidas, pesquisados pelo nome, bairro ou cidade. Em
/// [picking] (marcar amistoso) tocar num local o escolhe e fecha devolvendo o
/// [Venue]; senão, tocar num local que o usuário cadastrou abre a edição.
class VenuesPage extends ConsumerStatefulWidget {
  const VenuesPage({
    super.key,
    this.picking = false,
    this.offerTeamLink = true,
  });

  final bool picking;

  /// Se o cadastro de local oferece vincular ao time ativo (não quando a
  /// escolha vem do próprio formulário do time).
  final bool offerTeamLink;

  @override
  ConsumerState<VenuesPage> createState() => _VenuesPageState();
}

class _VenuesPageState extends ConsumerState<VenuesPage> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  late Future<List<Venue>> _results = _search('');

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<List<Venue>> _search(String query) =>
      ref.read(venueRepositoryProvider).search(query);

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

  Future<void> _create() async {
    final venue = await context.push<Venue>(
      Routes.newVenue,
      extra: (
        name: _searchController.text.trim(),
        offerTeamLink: widget.offerTeamLink,
      ),
    );
    if (!mounted || venue == null) return;
    if (widget.picking) {
      context.pop(venue);
    } else {
      _refresh();
    }
  }

  Future<void> _edit(Venue venue) async {
    await context.push<Venue>(Routes.editVenue, extra: venue);
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final userId = ref.watch(currentUserIdProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.picking ? 'Escolher local' : 'Locais'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(72),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              controller: _searchController,
              autofocus: widget.picking,
              decoration: const InputDecoration(
                hintText: 'Pesquisar por nome, bairro ou cidade',
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
          final venues = snapshot.data;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              if (snapshot.hasError)
                Center(
                  child: TextButton(
                    onPressed: _refresh,
                    child: const Text('Erro ao pesquisar. Tentar novamente'),
                  ),
                )
              else if (venues == null)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                if (venues.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('Nenhum local encontrado.'),
                  ),
                for (final venue in venues)
                  Card(
                    child: ListTile(
                      leading: VenuePhoto(venue: venue),
                      title: Text(venue.name),
                      subtitle: Text(venue.address),
                      isThreeLine: true,
                      trailing: !widget.picking && venue.createdBy == userId
                          ? const Icon(Icons.edit_outlined)
                          : null,
                      onTap: switch ((widget.picking, venue.createdBy)) {
                        (true, _) => () => context.pop(venue),
                        (false, final createdBy) when createdBy == userId =>
                          () => _edit(venue),
                        _ => null,
                      },
                    ),
                  ),
              ],
              const SizedBox(height: 16),
              Text('Não encontrou o local?', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _create,
                icon: const Icon(Icons.add_location_alt_outlined),
                label: const Text('Cadastrar local'),
              ),
            ],
          );
        },
      ),
    );
  }
}
