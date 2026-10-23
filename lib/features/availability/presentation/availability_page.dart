import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:table_calendar/table_calendar.dart';

import '../../../core/utils/error_messages.dart';
import '../../../core/widgets/confirm_dialog.dart';
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
    final result = await showDialog<({TimeOfDay time, bool weekly})>(
      context: context,
      builder: (_) => _AddSlotDialog(day: _selectedDay),
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
  }) => showDialog<_Scope>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(
        '${everyWeekday(availability.weekday!)} às '
        '${_time(availability.startTime!)}. Amistosos já marcados continuam.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_Scope.allWeeks),
          child: const Text('Todas as semanas'),
        ),
        TextButton(
          style: destructive
              ? TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                )
              : null,
          onPressed: () => Navigator.of(context).pop(_Scope.thisDay),
          child: Text('Só em ${formatGameDay(day)}'),
        ),
      ],
    ),
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
    final time = await _showTimePicker24h(
      context,
      TimeOfDay.fromDateTime(current),
      // Curto: o modo digitado tem altura fixa e o texto não pode quebrar.
      helpText: 'Novo horário',
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
          child: TextButton(
            onPressed: () => ref.invalidate(teamAvailabilityProvider(team.id!)),
            child: const Text('Erro ao carregar os horários. Tentar novamente'),
          ),
        ),
        data: (slots) => _content(context, team, slots),
      ),
    );
  }

  Widget _content(BuildContext context, Team team, List<Availability> slots) {
    final theme = Theme.of(context);
    final ofDay = [
      for (final slot in slots)
        if (slot.occursOn(_selectedDay)) slot,
    ]..sort((a, b) => a.at(_selectedDay).compareTo(b.at(_selectedDay)));
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
        const Divider(),
        _SectionTitle(
          'Horários em ${formatGameDay(_selectedDay)} '
          '(${weekdayNames[_selectedDay.weekday]})',
        ),
        if (ofDay.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Nenhum horário neste dia. Toque em "Adicionar horário".',
            ),
          ),
        for (final slot in ofDay)
          ListTile(
            leading: const Icon(Icons.schedule),
            title: Text(formatGameTime(slot.at(_selectedDay))),
            subtitle: slot.isWeekly ? Text(everyWeekday(slot.weekday!)) : null,
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

/// Seletor de horário sempre em 24 horas, como os horários do app. Sem isso,
/// com o aparelho em 12 horas, digitar "19" seria recusado.
Future<TimeOfDay?> _showTimePicker24h(
  BuildContext context,
  TimeOfDay initialTime, {
  String? helpText,
}) => showTimePicker(
  context: context,
  initialTime: initialTime,
  helpText: helpText,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
    child: child!,
  ),
);

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
class _AddSlotDialog extends StatefulWidget {
  const _AddSlotDialog({required this.day});

  final DateTime day;

  @override
  State<_AddSlotDialog> createState() => _AddSlotDialogState();
}

class _AddSlotDialogState extends State<_AddSlotDialog> {
  TimeOfDay _time = const TimeOfDay(hour: 15, minute: 0);
  bool _weekly = false;

  Future<void> _pickTime() async {
    final time = await _showTimePicker24h(context, _time);
    if (time != null) setState(() => _time = time);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Adicionar horário · ${formatGameDay(widget.day)}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.schedule),
            title: const Text('Horário do jogo'),
            trailing: TextButton(
              onPressed: _pickTime,
              child: Text(_time.format(context)),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _weekly,
            onChanged: (value) => setState(() => _weekly = value),
            title: const Text('Repetir toda semana'),
            subtitle: Text('${everyWeekday(widget.day.weekday)} neste horário'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop((time: _time, weekly: _weekly)),
          child: const Text('Adicionar'),
        ),
      ],
    );
  }
}
