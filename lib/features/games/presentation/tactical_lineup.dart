import 'dart:math';

import 'package:flutter/material.dart';

import '../../athletes/domain/athlete.dart';
import '../domain/formation.dart';
import 'game_sheet_page.dart' show AthleteAvatar;

/// Escalação no campo: as formações (rolagem lateral), o campo da
/// modalidade com as posições e os jogadores embaixo. Segurar e arrastar o
/// jogador leva até a posição; soltar em cima de quem já está troca os dois.
/// Arrastar do campo de volta para a lista tira do time titular.
class TacticalLineup extends StatelessWidget {
  const TacticalLineup({
    super.key,
    required this.pitch,
    required this.formations,
    required this.formation,
    required this.athletes,
    required this.placed,
    required this.reserves,
    required this.onFormation,
    required this.onPlace,
    required this.onRemove,
    required this.onToggleReserve,
  });

  final PitchKind pitch;
  final List<Formation> formations;
  final Formation formation;
  final List<Athlete> athletes;

  /// Posição -> atleta.
  final Map<int, String> placed;

  /// Atletas na reserva (fora do campo).
  final Set<String> reserves;

  final ValueChanged<Formation> onFormation;

  /// Leva o atleta para a posição.
  final void Function(String athleteId, int slot) onPlace;

  /// Tira o atleta do campo.
  final ValueChanged<String> onRemove;
  final ValueChanged<String> onToggleReserve;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: colors.onSurfaceVariant,
    );
    final byId = {for (final a in athletes) a.id!: a};
    final onField = placed.values.toSet();

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text('Formações', style: theme.textTheme.titleMedium),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
          child: Text(
            'Selecione a formação mais adequada para o seu time.',
            style: muted,
          ),
        ),
        _FormationStrip(
          formations: formations,
          selected: formation,
          onSelected: onFormation,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: AspectRatio(
            aspectRatio: 1 / PitchKind.field.heightRatio,
            child: LayoutBuilder(
              builder: (context, box) {
                const slotWidth = 76.0;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: PitchPainter(
                          kind: pitch,
                          line: colors.outlineVariant,
                          fill: colors.surfaceContainerLow,
                        ),
                      ),
                    ),
                    for (final (index, spot) in formation.spots.indexed)
                      Positioned(
                        left: spot.x * box.maxWidth - slotWidth / 2,
                        top: spot.y * box.maxHeight - 22,
                        width: slotWidth,
                        child: _Slot(
                          label: spot.label,
                          athlete: byId[placed[index]],
                          onDrop: (athleteId) => onPlace(athleteId, index),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
          child: Text('Jogadores', style: theme.textTheme.titleMedium),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
          child: Text(
            'Segure e arraste o jogador até a posição. Toque para marcar '
            'como reserva.',
            style: muted,
          ),
        ),
        // Soltar aqui tira do campo.
        DragTarget<String>(
          onWillAcceptWithDetails: (details) => onField.contains(details.data),
          onAcceptWithDetails: (details) => onRemove(details.data),
          builder: (context, candidates, _) => Container(
            color: candidates.isEmpty
                ? null
                : colors.primaryContainer.withValues(alpha: 0.3),
            height: 168,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: athletes.length,
              separatorBuilder: (_, _) => VerticalDivider(
                width: 16,
                indent: 12,
                endIndent: 40,
                color: colors.outlineVariant,
              ),
              itemBuilder: (context, index) {
                final athlete = athletes[index];
                final starter = onField.contains(athlete.id);
                return _PlayerCard(
                  athlete: athlete,
                  starter: starter,
                  reserve: reserves.contains(athlete.id),
                  onTap: starter ? null : () => onToggleReserve(athlete.id!),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// "9 · Ronaldo".
String _shirtName(Athlete athlete) => [
  if (athlete.jerseyNumber case final number?) '$number',
  athlete.displayName,
].join(' · ');

/// Uma posição do campo: vazia (círculo tracejado) ou com o jogador, que
/// pode ser arrastado para outra posição.
class _Slot extends StatelessWidget {
  const _Slot({
    required this.label,
    required this.athlete,
    required this.onDrop,
  });

  final String label;
  final Athlete? athlete;
  final ValueChanged<String> onDrop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final athlete = this.athlete;
    final caption = theme.textTheme.labelSmall?.copyWith(
      color: colors.onSurfaceVariant,
    );

    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => details.data != athlete?.id,
      onAcceptWithDetails: (details) => onDrop(details.data),
      builder: (context, candidates, _) {
        final hovering = candidates.isNotEmpty;
        final circle = athlete == null
            ? SizedBox.square(
                dimension: 40,
                child: CustomPaint(
                  painter: _DashedCircle(
                    hovering ? colors.primary : colors.outline,
                    // O fundo do campo esconde as linhas que passam por
                    // baixo da posição.
                    background: colors.surfaceContainerLow,
                    filled: hovering
                        ? colors.primary.withValues(alpha: 0.15)
                        : null,
                  ),
                ),
              )
            : DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: hovering ? colors.primary : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: AthleteAvatar(
                  name: athlete.displayName,
                  photoUrl: athlete.photoUrl,
                  radius: 20,
                ),
              );
        final content = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            circle,
            if (athlete != null)
              Container(
                margin: const EdgeInsets.only(top: 2),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _shirtName(athlete),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall,
                ),
              ),
            const SizedBox(height: 2),
            Text(label, style: caption),
          ],
        );
        if (athlete == null) {
          return Semantics(
            label: 'Posição $label vazia',
            container: true,
            excludeSemantics: true,
            child: content,
          );
        }
        return LongPressDraggable<String>(
          data: athlete.id,
          delay: const Duration(milliseconds: 150),
          feedback: _DragAvatar(athlete: athlete),
          childWhenDragging: Opacity(opacity: 0.3, child: content),
          child: Semantics(
            label: '$label: ${athlete.displayName}',
            container: true,
            excludeSemantics: true,
            child: content,
          ),
        );
      },
    );
  }
}

/// Jogador na lista de baixo. No campo, fica apagado.
class _PlayerCard extends StatelessWidget {
  const _PlayerCard({
    required this.athlete,
    required this.starter,
    required this.reserve,
    required this.onTap,
  });

  final Athlete athlete;
  final bool starter;
  final bool reserve;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final card = SizedBox(
      width: 112,
      child: Column(
        children: [
          const SizedBox(height: 8),
          AthleteAvatar(
            name: athlete.displayName,
            photoUrl: athlete.photoUrl,
            radius: 32,
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _shirtName(athlete),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            athlete.position ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 2),
          Text(
            starter
                ? 'Titular'
                : reserve
                ? 'Reserva'
                : 'Fora',
            style: theme.textTheme.labelSmall?.copyWith(
              color: starter || reserve ? colors.primary : colors.outline,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
    final faded = Opacity(opacity: starter ? 0.35 : 1, child: card);
    return LongPressDraggable<String>(
      data: athlete.id,
      delay: const Duration(milliseconds: 150),
      feedback: _DragAvatar(athlete: athlete),
      childWhenDragging: Opacity(opacity: 0.2, child: card),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Semantics(
          button: onTap != null,
          label: _shirtName(athlete),
          child: faded,
        ),
      ),
    );
  }
}

/// O que acompanha o dedo ao arrastar.
class _DragAvatar extends StatelessWidget {
  const _DragAvatar({required this.athlete});

  final Athlete athlete;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    elevation: 6,
    shape: const CircleBorder(),
    child: AthleteAvatar(
      name: athlete.displayName,
      photoUrl: athlete.photoUrl,
      radius: 26,
    ),
  );
}

/// Círculo tracejado das posições vazias.
class _DashedCircle extends CustomPainter {
  _DashedCircle(this.color, {required this.background, this.filled});

  final Color color;
  final Color background;
  final Color? filled;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 1;
    canvas.drawCircle(center, radius, Paint()..color = background);
    if (filled case final fill?) {
      canvas.drawCircle(center, radius, Paint()..color = fill);
    }
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    const dashes = 18;
    const sweep = 2 * pi / dashes;
    for (var i = 0; i < dashes; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        i * sweep,
        sweep * 0.55,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashedCircle old) =>
      old.color != color ||
      old.background != background ||
      old.filled != filled;
}

/// As linhas do campo da modalidade (o gol adversário no alto).
class PitchPainter extends CustomPainter {
  PitchPainter({required this.kind, required this.line, required this.fill});

  final PitchKind kind;
  final Color line;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    // Medidas em metros. Todos os campos têm a mesma altura (a do campo
    // de 11): o comprimento estica e a largura acompanha a tela.
    final (width, height) = switch (kind) {
      PitchKind.field => (68.0, 105.0),
      PitchKind.society => (30.0, 50.0),
      PitchKind.court => (20.0, 40.0),
    };
    final s = size.width / width;
    final sy = size.height / height;
    final h = size.height;
    final paint = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    canvas.drawRect(Offset.zero & Size(size.width, h), Paint()..color = fill);
    canvas.drawRect(Offset.zero & Size(size.width, h), paint);
    canvas.drawLine(Offset(0, h / 2), Offset(size.width, h / 2), paint);
    canvas.drawCircle(Offset(size.width / 2, h / 2), 2, Paint()..color = line);

    void box(double boxWidth, double depth, {required bool top}) {
      final left = (size.width - boxWidth * s) / 2;
      canvas.drawRect(
        Rect.fromLTWH(left, top ? 0 : h - depth * sy, boxWidth * s, depth * sy),
        paint,
      );
    }

    switch (kind) {
      case PitchKind.field:
        canvas.drawCircle(Offset(size.width / 2, h / 2), 9.15 * s, paint);
        for (final top in [true, false]) {
          box(40.3, 16.5, top: top);
          box(18.3, 5.5, top: top);
        }
      case PitchKind.society:
        canvas.drawCircle(Offset(size.width / 2, h / 2), 4 * s, paint);
        for (final top in [true, false]) {
          box(16, 7, top: top);
          box(7, 2.5, top: top);
        }
      case PitchKind.court:
        canvas.drawCircle(Offset(size.width / 2, h / 2), 3 * s, paint);
        // Área em "D": duas curvas de 6 m a partir das traves (3 m).
        for (final top in [true, false]) {
          final r = 6 * s;
          final ry = 6 * sy;
          final goal = 3 * s;
          final y = top ? 0.0 : h;
          final dir = top ? 1.0 : -1.0;
          final cx = size.width / 2;
          final path = Path()
            ..moveTo(cx - goal / 2 - r, y)
            ..arcToPoint(
              Offset(cx - goal / 2, y + dir * ry),
              radius: Radius.elliptical(r, ry),
              clockwise: !top,
            )
            ..lineTo(cx + goal / 2, y + dir * ry)
            ..arcToPoint(
              Offset(cx + goal / 2 + r, y),
              radius: Radius.elliptical(r, ry),
              clockwise: !top,
            );
          canvas.drawPath(path, paint);
        }
    }
  }

  @override
  bool shouldRepaint(PitchPainter old) =>
      old.kind != kind || old.line != line || old.fill != fill;
}

/// As formações em rolagem lateral. Ao abrir, rola até a escolhida (ela pode
/// estar fora da tela, no fim da lista).
class _FormationStrip extends StatefulWidget {
  const _FormationStrip({
    required this.formations,
    required this.selected,
    required this.onSelected,
  });

  final List<Formation> formations;
  final Formation selected;
  final ValueChanged<Formation> onSelected;

  @override
  State<_FormationStrip> createState() => _FormationStripState();
}

class _FormationStripState extends State<_FormationStrip> {
  final _selectedKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chip = _selectedKey.currentContext;
      if (chip == null || !chip.mounted) return;
      // Só a rolagem lateral (não mexe na rolagem da tela).
      Scrollable.of(
        chip,
        axis: Axis.horizontal,
      ).position.ensureVisible(chip.findRenderObject()!, alignment: 0.5);
    });
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Row(
      children: [
        for (final option in widget.formations)
          Padding(
            key: option.name == widget.selected.name ? _selectedKey : null,
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(option.name.split('').join(' ')),
              selected: option.name == widget.selected.name,
              showCheckmark: false,
              onSelected: (_) => widget.onSelected(option),
            ),
          ),
      ],
    ),
  );
}
