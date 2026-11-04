import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../games/data/opponent_repository.dart';
import '../../games/domain/opponent.dart';
import '../../teams/domain/team.dart';
import '../../teams/presentation/team_logo.dart';

/// Time escolhido para o campeonato: da plataforma ou fictício.
typedef PickedChampionshipTeam = ({String? teamId, String? guestTeamId});

/// O que a rota recebe em `extra`: a modalidade e os times já inscritos.
typedef ChampionshipTeamPickerArgs = ({
  Modality modality,
  Set<String> teamIds,
  Set<String> guestIds,
});

/// Pesquisa os times da plataforma e os fictícios do organizador que jogam a
/// modalidade (os já inscritos ficam de fora) e cria um fictício se precisar.
class ChampionshipTeamPickerPage extends ConsumerStatefulWidget {
  const ChampionshipTeamPickerPage({
    super.key,
    required this.modality,
    this.teamIds = const {},
    this.guestIds = const {},
  });

  final Modality modality;
  final Set<String> teamIds;
  final Set<String> guestIds;

  @override
  ConsumerState<ChampionshipTeamPickerPage> createState() =>
      _ChampionshipTeamPickerPageState();
}

class _ChampionshipTeamPickerPageState
    extends ConsumerState<ChampionshipTeamPickerPage> {
  /// Id que não é de nenhum time: a busca de adversários tira "o próprio
  /// time", e aqui todos os times valem.
  static const _noTeam = '00000000-0000-0000-0000-000000000000';

  final _search = TextEditingController();
  Timer? _debounce;
  late var _results = _find('');
  var _creating = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<({List<Team> registered, List<GuestTeam> guests})> _find(
    String query,
  ) => ref
      .read(opponentRepositoryProvider)
      .search(
        teamId: _noTeam,
        ownerId: ref.read(currentUserIdProvider)!,
        modality: widget.modality,
        query: query,
      );

  void _onChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _results = _find(query));
    });
  }

  Future<void> _createGuest() async {
    final name = await showAppSheet<String>(
      context,
      builder: (_) => _GuestNameSheet(initialName: _search.text.trim()),
    );
    if (name == null || !mounted) return;
    setState(() => _creating = true);
    try {
      final guest = await ref
          .read(opponentRepositoryProvider)
          .createGuest(
            GuestTeam(
              ownerId: ref.read(currentUserIdProvider)!,
              name: name,
              modality: widget.modality,
            ),
          );
      if (mounted) {
        context.pop<PickedChampionshipTeam>((
          teamId: null,
          guestTeamId: guest.id,
        ));
      }
    } catch (error) {
      if (mounted) showErrorSnackBar(context, friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Adicionar time')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: _creating ? null : _createGuest,
        icon: const Icon(Icons.add),
        label: const Text('Time fictício'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: 'Pesquisar times de ${widget.modality.label}',
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: _onChanged,
            ),
          ),
          Expanded(
            child: FutureBuilder(
              future: _results,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text(friendlyErrorMessage(snapshot.error!)),
                  );
                }
                final data = snapshot.data;
                if (data == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                final registered = data.registered
                    .where((t) => !widget.teamIds.contains(t.id))
                    .toList();
                final guests = data.guests
                    .where((g) => !widget.guestIds.contains(g.id))
                    .toList();
                if (registered.isEmpty && guests.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Nenhum time encontrado. Crie um time fictício.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  );
                }
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                  children: [
                    if (registered.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
                        child: Text(
                          'Times da plataforma (recebem o convite)',
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                    for (final team in registered)
                      Card(
                        child: ListTile(
                          leading: TeamLogo(team: team),
                          title: Text(team.name),
                          subtitle: team.location == null
                              ? null
                              : Text(team.location!),
                          onTap: () => context.pop<PickedChampionshipTeam>((
                            teamId: team.id,
                            guestTeamId: null,
                          )),
                        ),
                      ),
                    if (guests.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(0, 16, 0, 4),
                        child: Text(
                          'Seus times fictícios',
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                    for (final guest in guests)
                      Card(
                        child: ListTile(
                          leading: const CircleAvatar(
                            child: Icon(Icons.shield_outlined),
                          ),
                          title: Text(guest.name),
                          subtitle: const Text('Fictício'),
                          onTap: () => context.pop<PickedChampionshipTeam>((
                            teamId: null,
                            guestTeamId: guest.id,
                          )),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _GuestNameSheet extends StatefulWidget {
  const _GuestNameSheet({required this.initialName});

  final String initialName;

  @override
  State<_GuestNameSheet> createState() => _GuestNameSheetState();
}

class _GuestNameSheetState extends State<_GuestNameSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initialName);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.of(context).pop(_name.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppSheet(
      title: 'Criar time fictício',
      message:
          'Para times que não estão no SportLeague. Entra no campeonato já '
          'confirmado.',
      body: Form(
        key: _formKey,
        child: TextFormField(
          controller: _name,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nome do time',
            prefixIcon: Icon(Icons.shield_outlined),
          ),
          textCapitalization: TextCapitalization.words,
          maxLength: 80,
          onFieldSubmitted: (_) => _submit(),
          validator: (value) =>
              Validators.name(value, message: 'Informe o nome do time'),
        ),
      ),
      actions: [
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.check),
          label: const Text('Criar e adicionar'),
        ),
        const SheetBackButton(),
      ],
    );
  }
}
