import 'dart:math';
import 'dart:ui';

import 'package:flutter/painting.dart';

/// Fundos com tema de futebol, desenhados na cor de destaque ([accent]) por
/// cima do fundo já pintado. Tudo proporcional ao tamanho do banner, para
/// sair igual no quadrado, no feed e no story.

/// Uma bola grande no canto de baixo, cortada pela borda.
void paintBall(Canvas canvas, Size size, Color accent) {
  final radius = size.width * 0.62;
  final center = Offset(size.width * 0.8, size.height - radius * 0.45);
  final ball = Rect.fromCircle(center: center, radius: radius);

  // Volume: mais claro no alto, à esquerda.
  canvas.drawCircle(
    center,
    radius,
    Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.4, -0.5),
        radius: 0.9,
        colors: [accent.withValues(alpha: 0.2), accent.withValues(alpha: 0.06)],
      ).createShader(ball),
  );

  canvas
    ..save()
    ..clipPath(Path()..addOval(ball));
  final seam = Paint()
    ..color = accent.withValues(alpha: 0.35)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.2
    ..strokeJoin = StrokeJoin.round;
  final patch = Paint()..color = accent.withValues(alpha: 0.28);

  // Gomo do meio (pentágono) e os cinco em volta, ligados pelas costuras.
  final inner = _polygon(center, radius * 0.27, 5, -pi / 2);
  canvas
    ..drawPath(_closed(inner), patch)
    ..drawPath(_closed(inner), seam);
  for (var i = 0; i < 5; i++) {
    final angle = -pi / 2 + i * 2 * pi / 5;
    final elbow = center + Offset.fromDirection(angle, radius * 0.52);
    canvas.drawLine(inner[i], elbow, seam);
    // Os gomos de fora ficam entre as costuras.
    for (final side in const [-1, 1]) {
      final outerAngle = angle + side * pi / 5;
      final outerCenter =
          center + Offset.fromDirection(outerAngle, radius * 0.86);
      final outer = _polygon(outerCenter, radius * 0.25, 5, outerAngle + pi);
      canvas.drawLine(elbow, outer.first, seam);
      if (side == 1) {
        canvas
          ..drawPath(_closed(outer), patch)
          ..drawPath(_closed(outer), seam);
      }
    }
  }
  canvas.restore();
  canvas.drawCircle(
    center,
    radius,
    Paint()
      ..color = accent.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3,
  );
}

/// A rede do gol em losangos, mais forte embaixo.
void paintNet(Canvas canvas, Size size, Color accent) {
  final rect = Offset.zero & size;
  canvas.saveLayer(rect, Paint());
  final line = Paint()
    ..color = accent.withValues(alpha: 0.35)
    ..strokeWidth = 1.4;
  const gap = 22.0;
  for (var x = -size.height; x < size.width + size.height; x += gap) {
    canvas
      ..drawLine(Offset(x, 0), Offset(x + size.height, size.height), line)
      ..drawLine(Offset(x, size.height), Offset(x + size.height, 0), line);
  }
  // Os nós da rede.
  final knot = Paint()..color = accent.withValues(alpha: 0.45);
  for (var y = 0.0; y <= size.height; y += gap / 2) {
    final shift = (y / (gap / 2)).round().isEven ? 0.0 : gap / 2;
    for (var x = shift; x <= size.width; x += gap) {
      canvas.drawCircle(Offset(x, y), 1.4, knot);
    }
  }
  // Some no alto, onde ficam os títulos.
  canvas
    ..drawRect(
      rect,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFFFFFFFF).withValues(alpha: 0.15),
            const Color(0xFFFFFFFF),
          ],
        ).createShader(rect),
    )
    ..restore();
}

/// O gol de frente, no alto: traves, travessão e a rede em perspectiva.
void paintGoal(Canvas canvas, Size size, Color accent) {
  final left = size.width * 0.07;
  final right = size.width * 0.93;
  final top = size.height * 0.06;
  final bottom = size.height * 0.4;
  final depth = size.width * 0.07;
  final back = Rect.fromLTRB(
    left + depth,
    top + depth * 0.7,
    right - depth,
    bottom - depth * 0.3,
  );

  final net = Paint()
    ..color = accent.withValues(alpha: 0.16)
    ..strokeWidth = 1.2;
  // Fundo da rede em quadrados.
  const cell = 14.0;
  for (var x = back.left; x <= back.right; x += cell) {
    canvas.drawLine(Offset(x, back.top), Offset(x, back.bottom), net);
  }
  for (var y = back.top; y <= back.bottom; y += cell) {
    canvas.drawLine(Offset(back.left, y), Offset(back.right, y), net);
  }
  // Laterais e teto da rede, ligando as traves ao fundo.
  for (var i = 0.0; i <= 1; i += 0.125) {
    canvas
      ..drawLine(
        Offset(left, lerpDouble(top, bottom, i)!),
        Offset(back.left, lerpDouble(back.top, back.bottom, i)!),
        net,
      )
      ..drawLine(
        Offset(right, lerpDouble(top, bottom, i)!),
        Offset(back.right, lerpDouble(back.top, back.bottom, i)!),
        net,
      )
      ..drawLine(
        Offset(lerpDouble(left, right, i)!, top),
        Offset(lerpDouble(back.left, back.right, i)!, back.top),
        net,
      );
  }

  final post = Paint()
    ..color = accent.withValues(alpha: 0.55)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 6
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  canvas.drawPath(
    Path()
      ..moveTo(left, bottom)
      ..lineTo(left, top)
      ..lineTo(right, top)
      ..lineTo(right, bottom),
    post,
  );
  // A linha do gol no chão.
  canvas.drawLine(
    Offset(0, bottom),
    Offset(size.width, bottom),
    Paint()
      ..color = accent.withValues(alpha: 0.3)
      ..strokeWidth = 2,
  );
}

/// Estádio à noite: os refletores no alto e a torcida embaixo.
void paintStadium(Canvas canvas, Size size, Color accent) {
  // Fachos dos refletores, dos cantos para o meio.
  for (final fromLeft in const [true, false]) {
    final source = Offset(fromLeft ? 0 : size.width, size.height * 0.04);
    final target = Offset(size.width * (fromLeft ? 0.7 : 0.3), size.height);
    final spread = size.width * 0.32;
    final beam = Path()
      ..moveTo(source.dx, source.dy)
      ..lineTo(target.dx - spread, target.dy)
      ..lineTo(target.dx + spread, target.dy)
      ..close();
    canvas.drawPath(
      beam,
      Paint()
        ..shader = RadialGradient(
          center: Alignment(fromLeft ? -1 : 1, -0.92),
          radius: 1.3,
          colors: [accent.withValues(alpha: 0.32), accent.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    // A torre com as lâmpadas.
    final lamp = Paint()..color = accent.withValues(alpha: 0.75);
    for (var row = 0; row < 2; row++) {
      for (var col = 0; col < 3; col++) {
        canvas.drawCircle(
          source + Offset((fromLeft ? 1 : -1) * (8 + col * 8.0), row * 8.0 + 4),
          2.6,
          lamp,
        );
      }
    }
  }

  // A torcida: fileiras de cabeças, mais densas embaixo.
  final random = Random(11);
  final top = size.height * 0.78;
  for (var y = top; y < size.height + 6; y += 7) {
    final rowStrength = (y - top) / (size.height - top);
    for (var x = random.nextDouble() * 6; x < size.width; x += 7) {
      final alpha = 0.08 + 0.22 * rowStrength * random.nextDouble();
      canvas.drawCircle(
        Offset(x, y + random.nextDouble() * 2),
        2.4 + rowStrength,
        Paint()..color = accent.withValues(alpha: alpha),
      );
    }
  }
  // A beira do campo, separando a torcida.
  canvas.drawLine(
    Offset(0, top - 6),
    Offset(size.width, top - 6),
    Paint()
      ..color = accent.withValues(alpha: 0.35)
      ..strokeWidth = 2,
  );
}

/// Gramado: faixas de corte e a grama alta na beira de baixo.
void paintGrass(Canvas canvas, Size size, Color accent) {
  // Faixas verticais, como o gramado visto do gol.
  const bands = 7;
  final width = size.width / bands;
  final mow = Paint()..color = accent.withValues(alpha: 0.07);
  for (var i = 0; i < bands; i += 2) {
    canvas.drawRect(Rect.fromLTWH(i * width, 0, width, size.height), mow);
  }
  // Folhas de grama, de alturas diferentes.
  final random = Random(5);
  final blade = Paint()..color = accent.withValues(alpha: 0.3);
  final base = size.height + 2;
  for (var x = -4.0; x < size.width + 4; x += 3.2) {
    final height = size.height * (0.05 + 0.08 * random.nextDouble());
    final lean = (random.nextDouble() - 0.5) * 10;
    canvas.drawPath(
      Path()
        ..moveTo(x - 2.2, base)
        ..quadraticBezierTo(
          x + lean * 0.3,
          base - height * 0.6,
          x + lean,
          base - height,
        )
        ..quadraticBezierTo(
          x + lean * 0.2 + 1,
          base - height * 0.5,
          x + 2.2,
          base,
        )
        ..close(),
      blade,
    );
  }
}

/// Prancheta do técnico: jogadores em X e O e as jogadas tracejadas.
void paintTactics(Canvas canvas, Size size, Color accent) {
  final w = size.width;
  final h = size.height;
  final chalk = Paint()
    ..color = accent.withValues(alpha: 0.32)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.6
    ..strokeCap = StrokeCap.round;

  void circle(Offset at) => canvas.drawCircle(at, 9, chalk);
  void cross(Offset at) {
    canvas
      ..drawLine(at + const Offset(-8, -8), at + const Offset(8, 8), chalk)
      ..drawLine(at + const Offset(8, -8), at + const Offset(-8, 8), chalk);
  }

  void arrow(List<Offset> points) {
    final path = Path()..moveTo(points[0].dx, points[0].dy);
    path.quadraticBezierTo(
      points[1].dx,
      points[1].dy,
      points[2].dx,
      points[2].dy,
    );
    _drawDashed(canvas, path, chalk, dash: 9, gap: 7);
    // A ponta da seta, na direção do último trecho.
    final end = points[2];
    final angle = (points[2] - points[1]).direction;
    canvas
      ..drawLine(end, end - Offset.fromDirection(angle - 0.5, 12), chalk)
      ..drawLine(end, end - Offset.fromDirection(angle + 0.5, 12), chalk);
  }

  // Nossos jogadores (O) e os adversários (X), nas bordas, longe do texto.
  for (final at in [
    Offset(w * 0.12, h * 0.14),
    Offset(w * 0.88, h * 0.2),
    Offset(w * 0.1, h * 0.72),
    Offset(w * 0.5, h * 0.9),
    Offset(w * 0.85, h * 0.8),
  ]) {
    circle(at);
  }
  for (final at in [
    Offset(w * 0.3, h * 0.08),
    Offset(w * 0.93, h * 0.5),
    Offset(w * 0.07, h * 0.42),
    Offset(w * 0.68, h * 0.94),
  ]) {
    cross(at);
  }
  arrow([
    Offset(w * 0.12, h * 0.75),
    Offset(w * 0.2, h * 0.95),
    Offset(w * 0.42, h * 0.9),
  ]);
  arrow([
    Offset(w * 0.85, h * 0.77),
    Offset(w * 0.97, h * 0.6),
    Offset(w * 0.88, h * 0.25),
  ]);
  arrow([
    Offset(w * 0.15, h * 0.13),
    Offset(w * 0.5, h * 0.02),
    Offset(w * 0.8, h * 0.17),
  ]);
}

/// O escanteio: o canto do campo visto de cima, embaixo à esquerda, com a
/// meia-lua e a bola, a linha de fundo com a área, a pequena área e o gol,
/// e a bandeirinha de pé no canto.
void paintCorner(Canvas canvas, Size size, Color accent) {
  final w = size.width;
  // Faixas do gramado, para ler como campo.
  const bands = 8;
  final band = size.height / bands;
  final mow = Paint()..color = accent.withValues(alpha: 0.05);
  for (var i = 0; i < bands; i += 2) {
    canvas.drawRect(Rect.fromLTWH(0, i * band, w, band), mow);
  }

  final line = Paint()
    ..color = accent.withValues(alpha: 0.4)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3;
  const inset = 22.0;
  final corner = Offset(inset, size.height - inset);

  // Linha lateral (subindo) e linha de fundo (para a direita).
  canvas
    ..drawLine(Offset(inset, 0), corner, line)
    ..drawLine(corner, Offset(w, corner.dy), line);

  // A meia-lua do escanteio e a bola em cima dela.
  final arc = w * 0.12;
  canvas.drawArc(
    Rect.fromCircle(center: corner, radius: arc),
    -pi / 2,
    pi / 2,
    false,
    line,
  );
  final ball = corner + Offset.fromDirection(-pi / 4, arc);
  canvas
    ..drawCircle(ball, 7, Paint()..color = accent.withValues(alpha: 0.85))
    ..drawPath(
      _closed(_polygon(ball, 3, 5, -pi / 2)),
      Paint()..color = accent.withValues(alpha: 0.3),
    );

  // A grande área, a pequena área e o gol, na linha de fundo à direita.
  final penaltyDepth = w * 0.36;
  final goalAreaDepth = w * 0.13;
  canvas
    ..drawRect(
      Rect.fromLTRB(w * 0.46, corner.dy - penaltyDepth, w + 4, corner.dy),
      line,
    )
    ..drawRect(
      Rect.fromLTRB(w * 0.76, corner.dy - goalAreaDepth, w + 4, corner.dy),
      line,
    )
    ..drawRect(
      Rect.fromLTRB(w * 0.88, corner.dy, w + 4, corner.dy + 12),
      line..strokeWidth = 2,
    );
  line.strokeWidth = 3;
  // A marca do pênalti e a meia-lua da área.
  final spot = Offset(w * 1.02, corner.dy - w * 0.24);
  canvas
    ..drawCircle(
      Offset(w * 0.98, spot.dy),
      3.5,
      Paint()..color = accent.withValues(alpha: 0.5),
    )
    ..drawArc(
      Rect.fromCircle(center: spot, radius: w * 0.2),
      pi * 1.12,
      pi * 0.38,
      false,
      line,
    );

  // A bandeirinha: o mastro inclinado para fora do campo e a bandeira
  // tremulando.
  final poleTop = corner + Offset(-w * 0.05, -w * 0.34);
  canvas.drawLine(
    corner,
    poleTop,
    Paint()
      ..color = accent.withValues(alpha: 0.9)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round,
  );
  final flagWidth = w * 0.2;
  final flagHeight = w * 0.13;
  canvas.drawPath(
    Path()
      ..moveTo(poleTop.dx, poleTop.dy)
      ..cubicTo(
        poleTop.dx + flagWidth * 0.35,
        poleTop.dy - flagHeight * 0.2,
        poleTop.dx + flagWidth * 0.65,
        poleTop.dy + flagHeight * 0.2,
        poleTop.dx + flagWidth,
        poleTop.dy + flagHeight * 0.05,
      )
      ..lineTo(poleTop.dx + flagWidth * 0.94, poleTop.dy + flagHeight)
      ..cubicTo(
        poleTop.dx + flagWidth * 0.6,
        poleTop.dy + flagHeight * 1.15,
        poleTop.dx + flagWidth * 0.3,
        poleTop.dy + flagHeight * 0.75,
        poleTop.dx + flagWidth * 0.03,
        poleTop.dy + flagHeight * 0.95,
      )
      ..close(),
    Paint()..color = accent.withValues(alpha: 0.75),
  );
}

/// O meio-campo de perto: o grande círculo central, a linha do meio e as
/// faixas do gramado.
void paintCenterCircle(Canvas canvas, Size size, Color accent) {
  const bands = 6;
  final height = size.height / bands;
  final mow = Paint()..color = accent.withValues(alpha: 0.06);
  for (var i = 0; i < bands; i += 2) {
    canvas.drawRect(Rect.fromLTWH(0, i * height, size.width, height), mow);
  }
  final line = Paint()
    ..color = accent.withValues(alpha: 0.3)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3.5;
  final center = Offset(size.width / 2, size.height / 2);
  canvas
    ..drawLine(Offset(0, center.dy), Offset(size.width, center.dy), line)
    ..drawCircle(center, size.width * 0.44, line)
    ..drawCircle(center, 5, Paint()..color = accent.withValues(alpha: 0.45));
}

/// Os [count] vértices de um polígono regular.
List<Offset> _polygon(Offset center, double radius, int count, double start) =>
    [
      for (var i = 0; i < count; i++)
        center + Offset.fromDirection(start + i * 2 * pi / count, radius),
    ];

Path _closed(List<Offset> points) => Path()..addPolygon(points, true);

/// Desenha o [path] tracejado.
void _drawDashed(
  Canvas canvas,
  Path path,
  Paint paint, {
  required double dash,
  required double gap,
}) {
  for (final metric in path.computeMetrics()) {
    for (var d = 0.0; d < metric.length; d += dash + gap) {
      canvas.drawPath(
        metric.extractPath(d, min(d + dash, metric.length)),
        paint,
      );
    }
  }
}
