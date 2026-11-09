import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Mostra um texto em Markdown simples, o usado nos documentos do app
/// (Política de Privacidade e Termos de Uso): títulos (#, ##, ###),
/// parágrafos, listas (- e 1.), tabelas (|), separadores (---), **negrito**
/// e [links](destino). Tocar num link chama [onLink] com o destino.
class SimpleMarkdown extends StatelessWidget {
  const SimpleMarkdown(this.source, {super.key, this.onLink});

  final String source;
  final ValueChanged<String>? onLink;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final blocks = <Widget>[];
    final lines = source.replaceAll('\r', '').split('\n');
    final paragraph = <String>[];

    void flushParagraph() {
      if (paragraph.isEmpty) return;
      blocks.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _rich(
            context,
            paragraph.join(' '),
            theme.textTheme.bodyMedium,
          ),
        ),
      );
      paragraph.clear();
    }

    var i = 0;
    while (i < lines.length) {
      final line = lines[i].trimRight();
      final trimmed = line.trim();

      if (trimmed.isEmpty) {
        flushParagraph();
        i++;
        continue;
      }
      if (trimmed == '---') {
        flushParagraph();
        blocks.add(const Divider(height: 32));
        i++;
        continue;
      }
      final heading = RegExp(r'^(#{1,3})\s+(.*)$').firstMatch(trimmed);
      if (heading != null) {
        flushParagraph();
        final level = heading.group(1)!.length;
        final style = switch (level) {
          1 => theme.textTheme.headlineSmall,
          2 => theme.textTheme.titleLarge,
          _ => theme.textTheme.titleMedium,
        };
        blocks.add(
          Padding(
            padding: EdgeInsets.only(top: level == 1 ? 0 : 8, bottom: 8),
            child: _rich(context, heading.group(2)!, style),
          ),
        );
        i++;
        continue;
      }
      if (trimmed.startsWith('|')) {
        flushParagraph();
        final rows = <List<String>>[];
        while (i < lines.length && lines[i].trim().startsWith('|')) {
          final cells = lines[i]
              .trim()
              .replaceAll(RegExp(r'^\||\|$'), '')
              .split('|')
              .map((cell) => cell.trim())
              .toList();
          // Linha de separação (|---|---|).
          if (!cells.every((cell) => RegExp(r'^:?-+:?$').hasMatch(cell))) {
            rows.add(cells);
          }
          i++;
        }
        blocks.add(_table(context, rows));
        continue;
      }
      final bullet = RegExp(r'^(\s*)(-|\d+\.)\s+(.*)$').firstMatch(line);
      if (bullet != null) {
        flushParagraph();
        final indent = bullet.group(1)!.length >= 2 ? 16.0 : 0.0;
        final marker = bullet.group(2) == '-' ? '•' : bullet.group(2)!;
        blocks.add(
          Padding(
            padding: EdgeInsets.only(left: indent, bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 24,
                  child: Text(marker, style: theme.textTheme.bodyMedium),
                ),
                Expanded(
                  child: _rich(
                    context,
                    bullet.group(3)!,
                    theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        );
        i++;
        continue;
      }
      paragraph.add(trimmed);
      i++;
    }
    flushParagraph();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: blocks,
    );
  }

  Widget _table(BuildContext context, List<List<String>> rows) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final columns = rows.first.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Table(
        border: TableBorder.all(color: colors.outlineVariant),
        defaultVerticalAlignment: TableCellVerticalAlignment.top,
        children: [
          for (final (index, row) in rows.indexed)
            TableRow(
              decoration: index == 0
                  ? BoxDecoration(color: colors.surfaceContainerHighest)
                  : null,
              children: [
                for (var c = 0; c < columns; c++)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: _rich(
                      context,
                      c < row.length ? row[c] : '',
                      index == 0
                          ? theme.textTheme.labelLarge
                          : theme.textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  /// Texto com **negrito** e [links](destino).
  Widget _rich(BuildContext context, String text, TextStyle? style) {
    final colors = Theme.of(context).colorScheme;
    final spans = <InlineSpan>[];
    final pattern = RegExp(r'\*\*(.+?)\*\*|\[(.+?)\]\((.+?)\)');
    var last = 0;
    for (final match in pattern.allMatches(text)) {
      if (match.start > last) {
        spans.add(TextSpan(text: text.substring(last, match.start)));
      }
      if (match.group(1) case final bold?) {
        spans.add(
          TextSpan(
            text: bold,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        );
      } else {
        final target = match.group(3)!;
        spans.add(
          TextSpan(
            text: match.group(2),
            style: TextStyle(
              color: colors.primary,
              decoration: TextDecoration.underline,
            ),
            recognizer: onLink == null
                ? null
                : (TapGestureRecognizer()..onTap = () => onLink!(target)),
          ),
        );
      }
      last = match.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return Text.rich(TextSpan(style: style, children: spans));
  }
}
