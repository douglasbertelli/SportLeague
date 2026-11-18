import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../availability/data/availability_repository.dart';
import '../../teams/data/team_repository.dart';
import '../../teams/domain/team.dart';

/// Abre o cadastro de amistoso. Sem horário livre no calendário do time
/// ativo, antes passa pela Agenda: o horário adicionado lá já vem
/// escolhido no amistoso.
///
/// Time que só joga como visitante marca no calendário do adversário: vai
/// direto ao cadastro.
Future<void> openNewFriendly(BuildContext context) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final team = await container
      .read(selectedTeamProvider.future)
      .then<Team?>((team) => team, onError: (_) => null);
  if (!context.mounted) return;
  if (team == null || team.playsAs == PlaysAs.away) {
    await context.push(Routes.newGame);
    return;
  }

  Future<bool> hasFreeSlots() async {
    try {
      return (await container.read(freeSlotsProvider(team.id!).future))
          .isNotEmpty;
    } catch (_) {
      // Sem conseguir conferir, o cadastro mostra o erro na escolha do horário.
      return true;
    }
  }

  if (await hasFreeSlots()) {
    if (context.mounted) await context.push(Routes.newGame);
    return;
  }
  if (!context.mounted) return;

  final register = await showAppSheet<bool>(
    context,
    builder: (context) => AppSheet(
      title: 'Cadastre seus horários',
      message:
          'O ${team.name} não tem dia e horário livres para jogar. Antes de '
          'marcar o amistoso, cadastre na Agenda os dias e horários '
          'em que o time pode jogar.',
      actions: [
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(true),
          icon: const Icon(Icons.calendar_month_outlined),
          label: const Text('Cadastrar horários'),
        ),
        const SheetBackButton(),
      ],
    ),
  );
  if (register != true || !context.mounted) return;

  final slot = await context.push<DateTime>(Routes.availability, extra: true);
  if (!context.mounted) return;
  // Escolheu usar o horário adicionado, ou cadastrou e voltou: segue para o
  // amistoso. Voltou sem cadastrar nada: continua sem poder marcar.
  if (slot != null || await hasFreeSlots()) {
    if (context.mounted) await context.push(Routes.newGame, extra: slot);
  }
}
