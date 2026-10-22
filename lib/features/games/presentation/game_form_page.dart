import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../availability/presentation/slot_picker_page.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/form_page.dart';
import '../../../core/widgets/loading_button.dart';
import '../../teams/data/team_repository.dart';
import '../../teams/domain/team.dart';
import '../data/game_repository.dart';
import '../domain/game.dart';
import '../domain/opponent.dart';
import '../../venues/domain/venue.dart';
import 'games_tab.dart';
import 'opponent_picker_page.dart';

/// Marca um amistoso para o time ativo ou edita/exclui um existente. O
/// adversário precisa jogar a mesma modalidade; o placar é lançado em outra
/// tela.
class GameFormPage extends ConsumerStatefulWidget {
  const GameFormPage({super.key, this.game});

  final Game? game;

  @override
  ConsumerState<GameFormPage> createState() => _GameFormPageState();
}

class _GameFormPageState extends ConsumerState<GameFormPage> {
  final _formKey = GlobalKey<FormState>();
  late Venue? _venue = widget.game?.venue;
  late DateTime? _scheduledAt = widget.game?.scheduledAt;
  late Modality? _modality = widget.game?.modality;

  /// Mando do time que marca; mandante por padrão.
  late bool _hostIsHome = widget.game?.hostIsHome ?? true;
  late Opponent? _opponent = switch (widget.game) {
    Game(:final opponent, :final opponentTeamId, :final opponentGuestId)
        when opponentTeamId != null || opponentGuestId != null =>
      SavedOpponent(
        name: opponent,
        teamId: opponentTeamId,
        guestId: opponentGuestId,
      ),
    _ => null,
  };
  bool _showErrors = false;
  bool _loading = false;

  bool get _isEditing => widget.game != null;

  Future<void> _pickVenue() async {
    final venue = await context.push<Venue>(Routes.pickVenue);
    if (venue != null) setState(() => _venue = venue);
  }

  /// Time do jogo: o do jogo em edição ou o time ativo.
  Team? _team() {
    final teamId =
        widget.game?.teamId ?? ref.watch(selectedTeamProvider).value?.id;
    final teams = ref.watch(myTeamsProvider).value ?? const <Team>[];
    for (final team in teams) {
      if (team.id == teamId) return team;
    }
    return null;
  }

  /// Com uma só modalidade no time, ela já vem escolhida; com mais de uma, é
  /// escolhida junto com o adversário.
  Modality? _effectiveModality(Team team) =>
      _modality ??
      (team.modalities.length == 1 ? team.modalities.single : null);

  Future<void> _pickOpponent(Team team) async {
    final picked = await context.push<PickedOpponent>(
      Routes.pickOpponent,
      extra: (
        teamId: team.id!,
        modalities: team.modalities,
        modality: _effectiveModality(team),
      ),
    );
    if (picked != null) {
      final previousCalendar = _calendarFor(team)?.teamId;
      setState(() {
        _modality = picked.modality;
        _opponent = picked.opponent;
        // O horário escolhido era do calendário de outro time.
        if (_calendarFor(team)?.teamId != previousCalendar) _scheduledAt = null;
      });
    }
  }

  /// Calendário que vale para o jogo: o do adversário da plataforma ou, contra
  /// time fictício, o do próprio time. Nulo enquanto não há adversário.
  ({String teamId, String owner})? _calendarFor(Team team) =>
      switch (_opponent) {
        null => null,
        RegisteredOpponent(team: final rival) => (
          teamId: rival.id!,
          owner: 'do ${rival.name}',
        ),
        SavedOpponent(teamId: final rivalId?, :final name) => (
          teamId: rivalId,
          owner: 'do $name',
        ),
        _ => (teamId: team.id!, owner: 'do seu time'),
      };

  /// Só dá para escolher entre os horários livres do calendário que vale.
  Future<void> _pickDateTime(Team team) async {
    final calendar = _calendarFor(team);
    if (calendar == null) {
      setState(() => _showErrors = true);
      return;
    }
    final slot = await Navigator.of(context).push<DateTime>(
      MaterialPageRoute(
        builder: (_) => SlotPickerPage(
          teamId: calendar.teamId,
          calendarOwner: calendar.owner,
        ),
      ),
    );
    if (slot != null) setState(() => _scheduledAt = slot);
  }

  Future<void> _save(Team team) async {
    final valid = _formKey.currentState!.validate();
    setState(() => _showErrors = true);
    final modality = _effectiveModality(team);
    final opponent = _opponent;
    final scheduledAt = _scheduledAt;
    final venue = _venue;
    if (_loading ||
        !valid ||
        modality == null ||
        opponent == null ||
        scheduledAt == null ||
        venue == null) {
      return;
    }

    final game = Game(
      id: widget.game?.id,
      teamId: team.id!,
      opponent: opponent.name,
      opponentTeamId: switch (opponent) {
        RegisteredOpponent(:final team) => team.id,
        SavedOpponent(:final teamId) => teamId,
        GuestOpponent() => null,
      },
      opponentGuestId: switch (opponent) {
        GuestOpponent(:final guest) => guest.id,
        SavedOpponent(:final guestId) => guestId,
        RegisteredOpponent() => null,
      },
      modality: modality,
      hostIsHome: _hostIsHome,
      scheduledAt: scheduledAt,
      venueId: venue.id,
      // O texto antigo do local dá lugar ao local cadastrado.
      location: null,
    );
    final repository = ref.read(gameRepositoryProvider);
    await _run(
      team.id!,
      () => _isEditing ? repository.update(game) : repository.create(game),
    );
  }

  Future<void> _delete() async {
    final game = widget.game!;
    final confirmed = await confirmDelete(
      context,
      title: 'Excluir jogo?',
      message: 'O jogo contra ${game.opponent} será excluído.',
    );
    if (!confirmed) return;
    await _run(
      game.teamId,
      () => ref.read(gameRepositoryProvider).delete(game.id!),
    );
  }

  Future<void> _cancelGame() async {
    final game = widget.game!;
    final confirmed = await confirmAction(
      context,
      title: 'Cancelar amistoso?',
      message:
          'O amistoso contra ${game.opponent} irá para Cancelados'
          '${game.opponentTeamId != null ? ' para os dois times' : ''}.',
      confirmLabel: 'Cancelar amistoso',
      cancelLabel: 'Voltar',
    );
    if (!confirmed) return;
    await _run(
      game.teamId,
      () => ref.read(gameRepositoryProvider).cancel(game.id!),
    );
  }

  Future<void> _run(String teamId, Future<void> Function() action) async {
    setState(() => _loading = true);
    try {
      await action();
      ref.invalidate(teamGamesProvider(teamId));
      if (mounted) context.pop();
    } catch (error) {
      if (mounted) showErrorSnackBar(context, friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final errorStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.error,
    );
    final team = _team();

    return FormPage(
      appBar: AppBar(
        title: Text(_isEditing ? 'Editar amistoso' : 'Novo amistoso'),
        actions: [
          if (_isEditing)
            IconButton(
              tooltip: 'Excluir jogo',
              icon: const Icon(Icons.delete_outline),
              onPressed: _loading ? null : _delete,
            ),
        ],
      ),
      children: switch (team) {
        null => const [Center(child: CircularProgressIndicator())],
        Team(modalities: final modalities) when modalities.isEmpty => [
          Text(
            'Cadastre a modalidade do time ${team.name} para marcar '
            'amistosos.',
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => context.push(Routes.editTeam, extra: team),
            child: const Text('Editar time'),
          ),
        ],
        _ => _formChildren(context, team, errorStyle),
      },
    );
  }

  List<Widget> _formChildren(
    BuildContext context,
    Team team,
    TextStyle? errorStyle,
  ) {
    final theme = Theme.of(context);
    final modality = _effectiveModality(team);
    final opponent = _opponent;
    final scheduledAt = _scheduledAt;
    final venue = _venue;

    return [
      Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Jogar como', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: true,
                  label: Text('Mandante'),
                  icon: Icon(Icons.stadium_outlined),
                ),
                ButtonSegment(
                  value: false,
                  label: Text('Visitante'),
                  icon: Icon(Icons.directions_bus_outlined),
                ),
              ],
              selected: {_hostIsHome},
              onSelectionChanged: (selection) =>
                  setState(() => _hostIsHome = selection.first),
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: _loading ? null : () => _pickOpponent(team),
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Adversário',
                  helperText: switch (opponent) {
                    RegisteredOpponent() || SavedOpponent(teamId: _?) =>
                      'O time adversário precisa aceitar o amistoso',
                    _ => 'Time da plataforma ou time fictício',
                  },
                  // Jogo antigo sem modalidade num time com várias: o
                  // adversário é escolhido de novo, já com a modalidade.
                  errorText:
                      _showErrors && (opponent == null || modality == null)
                      ? 'Escolha o adversário'
                      : null,
                  suffixIcon: const Icon(Icons.search),
                ),
                isEmpty: opponent == null,
                child: Text(switch (opponent) {
                  null => '',
                  GuestOpponent(:final name) => '$name (fictício)',
                  final opponent => opponent.name,
                }),
              ),
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: _loading ? null : () => _pickDateTime(team),
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Data e hora',
                  helperText: switch (_calendarFor(team)) {
                    null => 'Escolha o adversário primeiro',
                    final calendar =>
                      'Horários livres no calendário ${calendar.owner}',
                  },
                  suffixIcon: const Icon(Icons.event),
                  errorText: _showErrors && scheduledAt == null
                      ? 'Escolha a data e a hora'
                      : null,
                ),
                isEmpty: scheduledAt == null,
                child: Text(
                  scheduledAt == null
                      ? ''
                      : formatGameDate(context, scheduledAt),
                ),
              ),
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: _loading ? null : _pickVenue,
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Local',
                  helperText: switch ((venue, widget.game?.location)) {
                    (final venue?, _) => venue.address,
                    // Jogo antigo: mostra o texto digitado antes.
                    (null, final old?) => 'Antes: $old',
                    _ => 'Escolha um local cadastrado ou cadastre um novo',
                  },
                  helperMaxLines: 2,
                  suffixIcon: const Icon(Icons.place_outlined),
                  errorText: _showErrors && venue == null
                      ? 'Escolha o local'
                      : null,
                ),
                isEmpty: venue == null,
                child: Text(venue?.name ?? ''),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      LoadingButton(
        label: _isEditing ? 'Salvar' : 'Marcar amistoso',
        loading: _loading,
        onPressed: () => _save(team),
      ),
      if (widget.game case final game?
          when game.status != GameStatus.canceled) ...[
        const SizedBox(height: 8),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
          onPressed: _loading ? null : _cancelGame,
          child: const Text('Cancelar amistoso'),
        ),
      ],
    ];
  }
}
