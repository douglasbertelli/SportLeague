import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../games/presentation/game_card.dart';
import '../data/availability_repository.dart';

/// Escolha do dia e horário de um amistoso entre os horários livres do time
/// [teamId] (o adversário da plataforma, ou o próprio time contra um time
/// fictício). Fecha devolvendo a data e hora escolhidas.
class SlotPickerPage extends ConsumerStatefulWidget {
  const SlotPickerPage({
    super.key,
    required this.teamId,
    required this.calendarOwner,
    this.today,
  });

  final String teamId;

  /// "do Real Madrid" / "do seu time", para os textos.
  final String calendarOwner;

  /// Dia de hoje (testes).
  final DateTime? today;

  @override
  ConsumerState<SlotPickerPage> createState() => _SlotPickerPageState();
}

class _SlotPickerPageState extends ConsumerState<SlotPickerPage> {
  late final DateTime _today = DateUtils.dateOnly(
    widget.today ?? DateTime.now(),
  );
  DateTime? _selectedDay;
  DateTime? _focusedDay;

  @override
  Widget build(BuildContext context) {
    final slots = ref.watch(freeSlotsProvider(widget.teamId));
    return Scaffold(
      appBar: AppBar(title: const Text('Escolher dia e horário')),
      body: slots.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: TextButton(
            onPressed: () => ref.invalidate(freeSlotsProvider(widget.teamId)),
            child: const Text('Erro ao carregar os horários. Tentar novamente'),
          ),
        ),
        data: (slots) => slots.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    'Não há horários disponíveis ${widget.calendarOwner} nos '
                    'próximos ${freeSlotsWindow.inDays} dias.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : _content(context, slots),
      ),
    );
  }

  Widget _content(BuildContext context, List<DateTime> slots) {
    final theme = Theme.of(context);
    List<DateTime> slotsOn(DateTime day) => [
      for (final slot in slots)
        if (DateUtils.isSameDay(slot, day)) slot,
    ];
    final firstDay = DateUtils.dateOnly(slots.first);
    final selectedDay = _selectedDay ?? firstDay;
    final ofDay = slotsOn(selectedDay);

    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Text(
            'Só aparecem os dias com horário livre ${widget.calendarOwner}.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        TableCalendar<DateTime>(
          locale: 'pt_BR',
          firstDay: _today,
          lastDay: _today.add(freeSlotsWindow),
          focusedDay: _focusedDay ?? firstDay,
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
            disabledTextStyle: TextStyle(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
            ),
          ),
          // Só os dias com horário livre podem ser escolhidos.
          enabledDayPredicate: (day) => slotsOn(day).isNotEmpty,
          eventLoader: slotsOn,
          selectedDayPredicate: (day) => isSameDay(day, selectedDay),
          onDaySelected: (selected, focused) => setState(() {
            _selectedDay = DateUtils.dateOnly(selected);
            _focusedDay = focused;
          }),
          onPageChanged: (focused) => _focusedDay = focused,
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Text(
            'Horários em ${formatGameDay(selectedDay)}',
            style: theme.textTheme.titleSmall,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final slot in ofDay)
                ActionChip(
                  avatar: const Icon(Icons.schedule, size: 18),
                  label: Text(formatGameTime(slot)),
                  onPressed: () => Navigator.of(context).pop(slot),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
