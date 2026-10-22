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
    final weekdayName = weekdayNames[_selectedDay.weekday]!;
    final result = await showDialog<({TimeOfDay time, bool weekly})>(
      context: context,
      builder: (_) =>
          _AddSlotDialog(day: _selectedDay, weekdayName: weekdayName),
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
          ? 'O horário de toda ${weekdayNames[availability.weekday]} às '
                '${_time(availability.startTime!)} será removido de todas as '
                'semanas. Amistosos já marcados continuam.'
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
            subtitle: slot.isWeekly
                ? Text('Toda ${weekdayNames[slot.weekday]}')
                : null,
            trailing: IconButton(
              tooltip: 'Remover horário',
              icon: const Icon(Icons.delete_outline),
              onPressed: _saving ? null : () => _delete(team, slot),
            ),
          ),
        if (weekly.isNotEmpty) ...[
          const Divider(),
          const _SectionTitle('Recorrentes'),
          for (final slot in weekly)
            ListTile(
              leading: const Icon(Icons.repeat),
              title: Text(
                'Toda ${weekdayNames[slot.weekday]} às '
                '${_time(slot.startTime!)}',
              ),
              subtitle: slot.startsOn == null
                  ? null
                  : Text('A partir de ${formatGameDay(slot.startsOn!)}'),
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
  const _AddSlotDialog({required this.day, required this.weekdayName});

  final DateTime day;
  final String weekdayName;

  @override
  State<_AddSlotDialog> createState() => _AddSlotDialogState();
}

class _AddSlotDialogState extends State<_AddSlotDialog> {
  TimeOfDay _time = const TimeOfDay(hour: 15, minute: 0);
  bool _weekly = false;

  Future<void> _pickTime() async {
    final time = await showTimePicker(context: context, initialTime: _time);
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
            subtitle: Text('Toda ${widget.weekdayName} neste horário'),
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
