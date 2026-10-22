import 'package:flutter/material.dart';

/// Dias da semana no padrão ISO (1 = segunda ... 7 = domingo), como o
/// `DateTime.weekday` do Dart e o banco.
const weekdayNames = {
  1: 'segunda',
  2: 'terça',
  3: 'quarta',
  4: 'quinta',
  5: 'sexta',
  6: 'sábado',
  7: 'domingo',
};

/// "Toda segunda", "Todo sábado".
String everyWeekday(int weekday) =>
    '${weekday >= DateTime.saturday ? 'Todo' : 'Toda'} ${weekdayNames[weekday]}';

/// Horário em que o time está disponível para jogar: avulso ([startsAt]) ou
/// recorrente toda semana ([weekday] + [startTime], opcionalmente a partir de
/// [startsOn]), menos os dias pulados ([skippedDates]).
class Availability {
  const Availability.single({
    this.id,
    required this.teamId,
    required DateTime this.startsAt,
  }) : weekday = null,
       startTime = null,
       startsOn = null,
       skippedDates = const {};

  const Availability.weekly({
    this.id,
    required this.teamId,
    required int this.weekday,
    required TimeOfDay this.startTime,
    this.startsOn,
    this.skippedDates = const {},
  }) : startsAt = null;

  factory Availability.fromMap(Map<String, dynamic> map) {
    final id = map['id'] as String;
    final teamId = map['team_id'] as String;
    if (map['starts_at'] case final String startsAt) {
      return Availability.single(
        id: id,
        teamId: teamId,
        startsAt: DateTime.parse(startsAt).toLocal(),
      );
    }
    // "15:00:00" -> 15:00
    final [hour, minute, ...] = (map['start_time'] as String).split(':');
    return Availability.weekly(
      id: id,
      teamId: teamId,
      weekday: map['weekday'] as int,
      startTime: TimeOfDay(hour: int.parse(hour), minute: int.parse(minute)),
      startsOn: switch (map['starts_on']) {
        final String date => DateTime.parse(date),
        _ => null,
      },
      skippedDates: {
        for (final skip in map['team_availability_skips'] as List? ?? const [])
          DateTime.parse((skip as Map)['on_date'] as String),
      },
    );
  }

  final String? id;
  final String teamId;

  /// Data e hora de um horário avulso, no fuso do aparelho.
  final DateTime? startsAt;
  final int? weekday;
  final TimeOfDay? startTime;
  final DateTime? startsOn;

  /// Dias em que o horário recorrente não vale (imprevistos), sem hora.
  final Set<DateTime> skippedDates;

  bool get isWeekly => weekday != null;

  /// Se o horário vale no dia [day] (só a data importa).
  bool occursOn(DateTime day) {
    final date = DateUtils.dateOnly(day);
    if (startsAt case final startsAt?) {
      return DateUtils.isSameDay(startsAt, date);
    }
    final startsOn = this.startsOn;
    return date.weekday == weekday &&
        (startsOn == null || !date.isBefore(DateUtils.dateOnly(startsOn))) &&
        !skippedDates.contains(date);
  }

  /// Data e hora do horário no dia [day] (para recorrentes).
  DateTime at(DateTime day) =>
      startsAt ??
      DateTime(
        day.year,
        day.month,
        day.day,
        startTime!.hour,
        startTime!.minute,
      );

  Map<String, dynamic> toMap() => {
    'team_id': teamId,
    if (startsAt case final startsAt?)
      'starts_at': startsAt.toUtc().toIso8601String()
    else ...{
      'weekday': weekday,
      'start_time': '${_two(startTime!.hour)}:${_two(startTime!.minute)}:00',
      if (startsOn case final startsOn?) 'starts_on': dateToDb(startsOn),
    },
  };
}

/// Data no formato do banco ("2026-10-24").
String dateToDb(DateTime date) =>
    '${date.year}-${_two(date.month)}-${_two(date.day)}';

String _two(int value) => value.toString().padLeft(2, '0');
