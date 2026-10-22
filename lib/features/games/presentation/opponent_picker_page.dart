import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../teams/domain/team.dart';
import '../../teams/presentation/team_logo.dart';
import '../data/opponent_repository.dart';
import '../domain/opponent.dart';

/// Escolha do adversário de um amistoso na [modality]: pesquisa os times da
/// plataforma e os times fictícios do administrador; se o adversário não
/// existir, cria um time fictício. Fecha devolvendo o [Opponent] escolhido.
class OpponentPickerPage extends ConsumerStatefulWidget {
  const OpponentPickerPage({
    super.key,
    required this.teamId,
    required this.modality,
  });

  final String teamId;
  final Modality modality;

  @override
  ConsumerState<OpponentPickerPage> createState() => _OpponentPickerPageState();
}

class _OpponentPickerPageState extends ConsumerState<OpponentPickerPage> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  late Future<({List<Team> registered, List<GuestTeam> guests})> _results =
      _search('');
  bool _creating = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<({List<Team> registered, List<GuestTeam> guests})> _search(
    String query,
  ) => ref
      .read(opponentRepositoryProvider)
      .search(
        teamId: widget.teamId,
        ownerId: ref.read(currentUserIdProvider)!,
        modality: widget.modality,
        query: query,
      );

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) _refresh(query);
    });
  }

  void _refresh(String query) {
    final results = _search(query);
    setState(() {
      _results = results;
    });
  }

  Future<void> _createGuest() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _GuestTeamDialog(
        initialName: _searchController.text.trim(),
        modality: widget.modality,
      ),
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
      if (mounted) context.pop<Opponent>(GuestOpponent(guest));
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
      appBar: AppBar(
        title: const Text('Escolher adversário'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(72),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Pesquisar time pelo nome',
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
          final results = snapshot.data;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Text(
                'Só aparecem times que jogam ${widget.modality.label}.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              if (snapshot.hasError)
                Center(
                  child: TextButton(
                    onPressed: () => _refresh(_searchController.text),
                    child: const Text('Erro ao pesquisar. Tentar novamente'),
                  ),
                )
              else if (results == null)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                if (results.registered.isEmpty && results.guests.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('Nenhum time encontrado.'),
                  ),
                if (results.registered.isNotEmpty) ...[
                  const _SectionTitle('Times da plataforma'),
                  for (final team in results.registered)
                    Card(
                      child: ListTile(
                        leading: TeamLogo(team: team),
                        title: Text(team.name),
                        subtitle: Text(
                          [team.summary, ?team.location].join('\n'),
                        ),
                        isThreeLine: team.location != null,
                        onTap: () =>
                            context.pop<Opponent>(RegisteredOpponent(team)),
                      ),
                    ),
                ],
                if (results.guests.isNotEmpty) ...[
                  const _SectionTitle('Seus times fictícios'),
                  for (final guest in results.guests)
                    Card(
                      child: ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.shield_outlined, size: 20),
                        ),
                        title: Text(guest.name),
                        subtitle: Text(
                          'Time fictício · ${guest.modality.label}',
                        ),
                        onTap: () =>
                            context.pop<Opponent>(GuestOpponent(guest)),
                      ),
                    ),
                ],
              ],
              const SizedBox(height: 16),
              Text(
                'Não encontrou o adversário?',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _creating ? null : _createGuest,
                icon: _creating
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add),
                label: const Text('Criar time fictício'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}

/// Pede o nome do time fictício. Devolve o nome ou nulo se cancelar.
class _GuestTeamDialog extends StatefulWidget {
  const _GuestTeamDialog({required this.initialName, required this.modality});

  final String initialName;
  final Modality modality;

  @override
  State<_GuestTeamDialog> createState() => _GuestTeamDialogState();
}

class _GuestTeamDialogState extends State<_GuestTeamDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.initialName);

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.of(context).pop(_nameController.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Criar time fictício'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Para adversários que não estão no SportLeague. Ele fica salvo '
              'para os próximos jogos de ${widget.modality.label} e só você vê.',
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Nome do time'),
              textCapitalization: TextCapitalization.words,
              maxLength: 80,
              onFieldSubmitted: (_) => _submit(),
              validator: (value) =>
                  Validators.name(value, message: 'Informe o nome do time'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        TextButton(onPressed: _submit, child: const Text('Criar')),
      ],
    );
  }
}
