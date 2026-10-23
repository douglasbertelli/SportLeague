import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Abre um bottom sheet no padrão do app (alça para arrastar, acima do
/// teclado e dentro da área segura). Use no lugar de janelas suspensas.
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) => showModalBottomSheet<T>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (context) => Padding(
    // Sobe junto com o teclado.
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: builder(context),
  ),
);

/// Conteúdo padrão de um bottom sheet: título, texto, corpo e ações
/// empilhadas (a principal em cima, ocupando a largura toda).
class AppSheet extends StatelessWidget {
  const AppSheet({
    super.key,
    required this.title,
    this.message,
    this.body,
    this.actions = const [],
  });

  final String title;
  final String? message;
  final Widget? body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final message = this.message;
    final body = this.body;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: theme.textTheme.titleLarge),
          if (message != null) ...[
            const SizedBox(height: 8),
            Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (body != null) ...[const SizedBox(height: 16), body],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 24),
            for (final (index, action) in actions.indexed) ...[
              if (index > 0) const SizedBox(height: 8),
              action,
            ],
          ],
        ],
      ),
    );
  }
}

/// Botão de "Voltar" dos bottom sheets: fecha sem escolher nada.
class SheetBackButton extends StatelessWidget {
  const SheetBackButton({super.key, this.label = 'Cancelar'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () => Navigator.of(context).pop(),
      icon: const Icon(Icons.close),
      label: Text(label),
    );
  }
}

/// Escolha de um horário num bottom sheet (rolagem, sempre 24 horas). Nulo
/// se o usuário desistir.
Future<TimeOfDay?> pickTimeSheet(
  BuildContext context, {
  required TimeOfDay initialTime,
  String title = 'Horário',
}) {
  var selected = initialTime;
  return showAppSheet<TimeOfDay>(
    context,
    builder: (context) => AppSheet(
      title: title,
      body: SizedBox(
        height: 180,
        child: CupertinoTheme(
          data: CupertinoThemeData(
            brightness: Theme.of(context).brightness,
            textTheme: CupertinoTextThemeData(
              dateTimePickerTextStyle: Theme.of(context)
                  .textTheme
                  .headlineSmall,
            ),
          ),
          child: CupertinoDatePicker(
            mode: CupertinoDatePickerMode.time,
            use24hFormat: true,
            initialDateTime: DateTime(
              2000,
              1,
              1,
              initialTime.hour,
              initialTime.minute,
            ),
            onDateTimeChanged: (value) =>
                selected = TimeOfDay.fromDateTime(value),
          ),
        ),
      ),
      actions: [
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(selected),
          icon: const Icon(Icons.check),
          label: const Text('Confirmar'),
        ),
        const SheetBackButton(),
      ],
    ),
  );
}

/// Escolha de uma data num bottom sheet (calendário). Nulo se o usuário
/// desistir.
Future<DateTime?> pickDateSheet(
  BuildContext context, {
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  required String title,
}) {
  var selected = initialDate;
  return showAppSheet<DateTime>(
    context,
    builder: (context) => AppSheet(
      title: title,
      body: CalendarDatePicker(
        initialDate: initialDate,
        firstDate: firstDate,
        lastDate: lastDate,
        onDateChanged: (value) => selected = value,
      ),
      actions: [
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(selected),
          icon: const Icon(Icons.check),
          label: const Text('Confirmar'),
        ),
        const SheetBackButton(),
      ],
    ),
  );
}
