import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:table_calendar/table_calendar.dart';

import '../../../core/utils/error_messages.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../games/data/game_repository.dart';
import '../../games/domain/game.dart';
import '../../games/presentation/game_card.dart';
import '../../teams/data/team_repository.dart';
import '../../teams/domain/team.dart';
import '../data/availability_repository.dart';
import '../domain/availability.dart';

/// Calendário de disponibilidade do time ativo: os dias e horários em que ele
/// aceita jogar. Amistosos só podem ser marcados nesses horários.
class AvailabilityPage extends ConsumerStatefulWidget {
  const AvailabilityPage({super.key, this.today});

  /// Dia de hoje (testes).
  final DateTime? today;

  @override
  ConsumerState<AvailabilityPage> createState() => _AvailabilityPageState();
}

class _AvailabilityPageState extends ConsumerState<AvailabilityPage> {
  late final DateTime _today = DateUtils.dateOnly(
    widget.today ?? DateTime.now(),
  );
  late DateTime _focusedDay = _today;
  late DateTime _selectedDay = _today;
  bool _saving = false;

  Future<void> _add(Team team) async {
    final result = await showAppSheet<({TimeOfDay time, bool weekly})>(
      context,
      builder: (_) => _AddSlotSheet(day: _selectedDay),
    );
    if (result == null) return;

    final availability = result.weekly
        ? Availability.weekly(
            teamId: team.id!,
            weekday: _selectedDay.weekday,
            startTime: result.time,
            startsOn: _selectedDay,
          )
        : Availability.single(
            teamId: team.id!,
            startsAt: DateTime(
              _selectedDay.year,
              _selectedDay.month,
              _selectedDay.day,
              result.time.hour,
              result.time.minute,
            ),
          );
    await _run(
      team,
      () => ref.read(availabilityRepositoryProvider).add(availability),
    );
  }

  Future<void> _delete(Team team, Availability availability) async {
    final confirmed = await confirmDelete(
      context,
      title: 'Remover horário?',
      message: availability.isWeekly
          ? 'O horário de ${everyWeekday(availability.weekday!).toLowerCase()} '
                'às ${_time(availability.startTime!)} será removido de todas '
                'as semanas. Amistosos já marcados continuam.'
          : 'O horário de ${formatGameDay(availability.startsAt!)} às '
                '${formatGameTime(availability.startsAt!)} será removido. '
                'Amistosos já marcados continuam.',
    );
    if (!confirmed) return;
    await _run(
      team,
      () => ref.read(availabilityRepositoryProvider).delete(availability.id!),
    );
  }

  /// Pergunta se a mudança num horário recorrente vale só para o dia [day] ou
  /// para todas as semanas.
  Future<_Scope?> _askScope(
    Availability availability,
    DateTime day, {
    required String title,
    bool destructive = false,
  }) => showAppSheet<_Scope>(
    context,
    builder: (context) {
      final colors = Theme.of(context).colorScheme;
      return AppSheet(
        title: title,
        message:
            '${everyWeekday(availability.weekday!)} às '
            '${_time(availability.startTime!)}. Amistosos já marcados '
            'continuam.',
        actions: [
          FilledButton.icon(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: colors.error,
                    foregroundColor: colors.onError,
                  )
                : null,
            onPressed: () => Navigator.of(context).pop(_Scope.thisDay),
            icon: const Icon(Icons.today),
            label: Text('Só em ${formatGameDay(day)}'),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).pop(_Scope.allWeeks),
            icon: const Icon(Icons.repeat),
            label: const Text('Todas as semanas'),
          ),
          const SheetBackButton(),
        ],
      );
    },
  );

  /// Remover um horário no dia selecionado: o avulso sai de vez; o recorrente
  /// pode sair só deste dia (imprevisto) ou de todas as semanas.
  Future<void> _deleteOnDay(Team team, Availability availability) async {
    if (!availability.isWeekly) return _delete(team, availability);
    final day = _selectedDay;
    final repository = ref.read(availabilityRepositoryProvider);
    switch (await _askScope(
      availability,
      day,
      title: 'Remover horário?',
      destructive: true,
    )) {
      case null:
        return;
      case _Scope.allWeeks:
        await _run(team, () => repository.delete(availability.id!));
      case _Scope.thisDay:
        await _run(team, () => repository.skipDate(availability.id!, day));
    }
  }

  /// Mudar o horário no dia selecionado. No recorrente, "só neste dia" vira um
  /// horário avulso no novo horário e o dia sai do recorrente.
  Future<void> _editOnDay(Team team, Availability availability) async {
    final day = _selectedDay;
    final current = availability.at(day);
    final time = await pickTimeSheet(
      context,
      initialTime: TimeOfDay.fromDateTime(current),
      title: 'Novo horário em ${formatGameDay(day)}',
    );
    if (time == null || !mounted) return;
    final moved = DateTime(
      day.year,
      day.month,
      day.day,
      time.hour,
      time.minute,
    );
    if (moved == current) return;
    final repository = ref.read(availabilityRepositoryProvider);

    if (!availability.isWeekly) {
      await _run(
        team,
        () => repository.update(
          Availability.single(
            id: availability.id,
            teamId: availability.teamId,
            startsAt: moved,
          ),
        ),
      );
      return;
    }
    switch (await _askScope(
      availability,
      day,
      title: 'Mudar para ${_time(time)}?',
    )) {
      case null:
        return;
      case _Scope.allWeeks:
        await _run(
          team,
          () => repository.update(
            Availability.weekly(
              id: availability.id,
              teamId: availability.teamId,
              weekday: availability.weekday!,
              startTime: time,
              startsOn: availability.startsOn,
            ),
          ),
        );
      case _Scope.thisDay:
        // Primeiro o avulso: se ele já existir, o recorrente fica como estava.
        await _run(team, () async {
          await repository.add(
            Availability.single(teamId: availability.teamId, startsAt: moved),
          );
          await repository.skipDate(availability.id!, day);
        });
    }
  }

  Future<void> _run(Team team, Future<void> Function() action) async {
    setState(() => _saving = true);
    try {
      await action();
      ref
        ..invalidate(teamAvailabilityProvider(team.id!))
        ..invalidate(freeSlotsProvider(team.id!));
    } catch (error) {
      if (mounted) {
        showErrorSnackBar(
          context,
          error is PostgrestException && error.code == '23505'
              ? 'Esse horário já está cadastrado.'
              : friendlyErrorMessage(error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final team = ref.watch(selectedTeamProvider).value;
    if (team == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Disponibilidade')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final availability = ref.watch(teamAvailabilityProvider(team.id!));

    return Scaffold(
      appBar: AppBar(title: Text('Disponibilidade · ${team.name}')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saving ? null : () => _add(team),
        icon: const Icon(Icons.add),
        label: const Text('Adicionar horário'),
      ),
      body: availability.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: TextButton.icon(
            onPressed: () => ref.invalidate(teamAvailabilityProvider(team.id!)),
            icon: const Icon(Icons.refresh),
            label: const Text('Erro ao carregar os horários. Tentar novamente'),
          ),
        ),
        data: (slots) => _content(context, team, slots),
      ),
    );
  }

  Widget _content(BuildContext context, Team team, List<Availability> slots) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    // Amistosos pendentes ou marcados ocupam o horário: ficam em vermelho.
    final booked = [
      for (final game
          in ref.watch(teamGamesProvider(team.id!)).value ?? const <Game>[])
        if (game.status != GameStatus.canceled) game,
    ];
    List<Game> gamesOn(DateTime day) => [
      for (final game in booked)
        if (DateUtils.isSameDay(game.scheduledAt, day)) game,
    ];
    Game? gameAt(DateTime at) =>
        booked.where((game) => game.scheduledAt == at).firstOrNull;

    final ofDay = [
      for (final slot in slots)
        if (slot.occursOn(_selectedDay)) slot,
    ]..sort((a, b) => a.at(_selectedDay).compareTo(b.at(_selectedDay)));
    // Jogos do dia fora dos horários cadastrados (horário removido depois).
    final otherGames = [
      for (final game in gamesOn(_selectedDay))
        if (!ofDay.any((slot) => slot.at(_selectedDay) == game.scheduledAt))
          game,
    ];

    /// Dia com jogo: círculo vermelho (com borda quando selecionado).
    Widget? bookedDay(DateTime day, {bool selected = false}) {
      if (gamesOn(day).isEmpty) return null;
      return Center(
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.error,
            shape: BoxShape.circle,
            border: selected
                ? Border.all(color: colors.onSurface, width: 2)
                : null,
          ),
          child: Text(
            '${day.day}',
            semanticsLabel: '${day.day}, dia com jogo',
            style: TextStyle(color: colors.onError),
          ),
        ),
      );
    }

    final weekly = [
      for (final slot in slots)
        if (slot.isWeekly) slot,
    ];

    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Text(
            'Marque os dias e horários em que o time pode jogar. Os '
            'adversários só conseguem marcar amistosos nesses horários.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        TableCalendar<Availability>(
          locale: 'pt_BR',
          firstDay: _today,
          lastDay: _today.add(const Duration(days: 365)),
          focusedDay: _focusedDay,
          startingDayOfWeek: StartingDayOfWeek.monday,
          // Arrastar na vertical rola a tela, não o calendário.
          availableGestures: AvailableGestures.horizontalSwipe,
          availableCalendarFormats: const {CalendarFormat.month: 'Mês'},
          headerStyle: const HeaderStyle(
            formatButtonVisible: false,
            titleCentered: true,
          ),
          calendarStyle: CalendarStyle(
            markerDecoration: BoxDecoration(
              color: theme.colorScheme.primary,
              shape: BoxShape.circle,
            ),
            selectedDecoration: BoxDecoration(
              color: theme.colorScheme.primary,
              shape: BoxShape.circle,
            ),
            selectedTextStyle: TextStyle(color: theme.colorScheme.onPrimary),
            todayDecoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            todayTextStyle: TextStyle(
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
          calendarBuilders: CalendarBuilders(
            defaultBuilder: (_, day, _) => bookedDay(day),
            todayBuilder: (_, day, _) => bookedDay(day),
            selectedBuilder: (_, day, _) => bookedDay(day, selected: true),
          ),
          selectedDayPredicate: (day) => isSameDay(day, _selectedDay),
          eventLoader: (day) => [
            for (final slot in slots)
              if (slot.occursOn(day)) slot,
          ],
          onDaySelected: (selected, focused) => setState(() {
            _selectedDay = DateUtils.dateOnly(selected);
            _focusedDay = focused;
          }),
          onPageChanged: (focused) => _focusedDay = focused,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: colors.error,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Dia com jogo marcado ou aguardando resposta',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
        const Divider(),
        _SectionTitle(
          'Horários em ${formatGameDay(_selectedDay)} '
          '(${weekdayNames[_selectedDay.weekday]})',
        ),
        if (ofDay.isEmpty && otherGames.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Nenhum horário neste dia. Toque em "Adicionar horário".',
            ),
          ),
        for (final game in otherGames)
          ListTile(
            leading: Icon(Icons.event_busy, color: colors.error),
            title: Text(
              formatGameTime(game.scheduledAt),
              style: TextStyle(color: colors.error),
            ),
            subtitle: Text(_gameLine(game, team)),
          ),
        for (final slot in ofDay)
          ListTile(
            leading: switch (gameAt(slot.at(_selectedDay))) {
              null => const Icon(Icons.schedule),
              _ => Icon(Icons.event_busy, color: colors.error),
            },
            title: Text(
              formatGameTime(slot.at(_selectedDay)),
              style: gameAt(slot.at(_selectedDay)) == null
                  ? null
                  : TextStyle(color: colors.error),
            ),
            subtitle: switch ((gameAt(slot.at(_selectedDay)), slot.isWeekly)) {
              (final game?, _) => Text(_gameLine(game, team)),
              (null, true) => Text(everyWeekday(slot.weekday!)),
              _ => null,
            },
            onTap: _saving ? null : () => _editOnDay(team, slot),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Editar horário',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: _saving ? null : () => _editOnDay(team, slot),
                ),
                IconButton(
                  tooltip: 'Remover horário',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _saving ? null : () => _deleteOnDay(team, slot),
                ),
              ],
            ),
          ),
        if (weekly.isNotEmpty) ...[
          const Divider(),
          const _SectionTitle('Recorrentes'),
          for (final slot in weekly)
            ListTile(
              leading: const Icon(Icons.repeat),
              title: Text(
                '${everyWeekday(slot.weekday!)} às ${_time(slot.startTime!)}',
              ),
              subtitle: _weeklyDetails(slot),
              trailing: IconButton(
                tooltip: 'Remover horário recorrente',
                icon: const Icon(Icons.delete_outline),
                onPressed: _saving ? null : () => _delete(team, slot),
              ),
            ),
        ],
      ],
    );
  }
}

enum _Scope { thisDay, allWeeks }

/// "Jogo contra Real Bairro" ou "Aguardando resposta: Real Bairro".
String _gameLine(Game game, Team team) {
  final opponent = game.opponentNameFor(team.id!);
  return game.status == GameStatus.pending
      ? 'Aguardando resposta: $opponent'
      : 'Jogo contra $opponent';
}

/// "A partir de 24/10/2026 · Sem jogo em 31/10/2026", só com os dias pulados
/// que ainda vão acontecer.
Widget? _weeklyDetails(Availability slot) {
  final today = DateUtils.dateOnly(DateTime.now());
  final skipped = [
    for (final date in slot.skippedDates)
      if (!date.isBefore(today)) date,
  ]..sort();
  final details = [
    if (slot.startsOn case final startsOn?)
      'A partir de ${formatGameDay(startsOn)}',
    if (skipped.isNotEmpty)
      'Sem jogo em ${skipped.map(formatGameDay).join(', ')}',
  ];
  return details.isEmpty ? null : Text(details.join(' · '));
}

String _time(TimeOfDay time) =>
    '${time.hour.toString().padLeft(2, '0')}:'
    '${time.minute.toString().padLeft(2, '0')}';

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}

/// Escolhe o horário do dia e se ele se repete toda semana.
class _AddSlotSheet extends StatefulWidget {
  const _AddSlotSheet({required this.day});

  final DateTime day;

  @override
  State<_AddSlotSheet> createState() => _AddSlotSheetState();
}

class _AddSlotSheetState extends State<_AddSlotSheet> {
  TimeOfDay _time = const TimeOfDay(hour: 15, minute: 0);
  bool _weekly = false;

  Future<void> _pickTime() async {
    final time = await pickTimeSheet(
      context,
      initialTime: _time,
      title: 'Horário do jogo',
    );
    if (time != null) setState(() => _time = time);
  }

  @override
  Widget build(BuildContext context) {
    return AppSheet(
      title: 'Adicionar horário · ${formatGameDay(widget.day)}',
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.schedule),
            title: const Text('Horário do jogo'),
            trailing: TextButton.icon(
              onPressed: _pickTime,
              icon: const Icon(Icons.edit_outlined),
              label: Text(_time.format(context)),
            ),
            onTap: _pickTime,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.repeat),
            value: _weekly,
            onChanged: (value) => setState(() => _weekly = value),
            title: const Text('Repetir toda semana'),
            subtitle: Text('${everyWeekday(widget.day.weekday)} neste horário'),
          ),
        ],
      ),
      actions: [
        FilledButton.icon(
          onPressed: () =>
              Navigator.of(context).pop((time: _time, weekly: _weekly)),
          icon: const Icon(Icons.add),
          label: const Text('Adicionar'),
        ),
        const SheetBackButton(),
      ],
    );
  }
}
