import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../domain/banner_design.dart';
import 'football_patterns.dart';

/// O banner desenhado no tamanho do [BannerStyle.format] (360 de largura).
/// O editor mostra encolhido e exporta 3× maior.
class BannerCanvas extends StatelessWidget {
  const BannerCanvas({
    super.key,
    required this.template,
    required this.style,
    required this.texts,
    required this.teamName,
    this.teamLogoUrl,
    this.opponentLogoUrl,
    this.featuredPhoto,
    this.backgroundPhoto,
  });

  final BannerTemplate template;
  final BannerStyle style;
  final BannerTexts texts;

  /// Nome do time para o cabeçalho dos modelos sem o confronto.
  final String teamName;
  final String? teamLogoUrl;
  final String? opponentLogoUrl;

  /// Foto em destaque (aniversariante, campeão).
  final ImageProvider? featuredPhoto;

  /// Foto atrás de tudo, escurecida com a cor do fundo.
  final ImageProvider? backgroundPhoto;

  @override
  Widget build(BuildContext context) {
    final size = style.format.size;
    // A imagem não muda com o tamanho de fonte do aparelho.
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: SizedBox.fromSize(
        size: size,
        child: ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(painter: BannerPatternPainter(style)),
              if (backgroundPhoto case final photo?) ...[
                Image(image: photo, fit: BoxFit.cover),
                ColoredBox(
                  color: style.background.withValues(
                    alpha: style.backgroundDim,
                  ),
                ),
              ],
              DefaultTextStyle(
                style: _BannerText(style).body,
                textAlign: TextAlign.center,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 26, 24, 18),
                  child: Column(
                    children: [
                      Expanded(
                        child: _FitColumn(
                          gap: style.format == BannerFormat.story ? 26 : 14,
                          children: _content(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      _Footer(style: style, text: _text(BannerField.footer)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _text(BannerField field) => (texts[field] ?? '').trim();

  List<Widget> _content() {
    final t = _BannerText(style);
    final title = _text(BannerField.title);
    final subtitle = _text(BannerField.subtitle);
    final message = _text(BannerField.message);

    Widget label(String text) => _Label(text: text, style: style);
    Widget titleText(String text, {double scale = 1}) =>
        Text(text, style: t.title(scale), textAlign: TextAlign.center);
    Widget header() => _TeamHeader(
      name: teamName,
      logoUrl: style.showLogo ? teamLogoUrl : null,
      style: style,
    );

    switch (template) {
      case BannerTemplate.gameDay:
        return [
          if (subtitle.isNotEmpty) label(subtitle),
          if (title.isNotEmpty) titleText(title),
          _Versus(
            style: style,
            team: _text(BannerField.team),
            opponent: _text(BannerField.opponent),
            teamLogoUrl: teamLogoUrl,
            opponentLogoUrl: opponentLogoUrl,
            center: Text('×', style: t.title(0.9, color: style.accent)),
          ),
          _WhenWhere(
            style: style,
            date: _text(BannerField.date),
            time: _text(BannerField.time),
            place: _text(BannerField.place),
          ),
          if (message.isNotEmpty) Text(message, style: t.body),
        ];
      case BannerTemplate.result:
        final mine = int.tryParse(_text(BannerField.teamScore));
        final theirs = int.tryParse(_text(BannerField.opponentScore));
        final outcome = mine == null || theirs == null
            ? null
            : switch (mine.compareTo(theirs)) {
                > 0 => 'VITÓRIA',
                < 0 => 'DERROTA',
                _ => 'EMPATE',
              };
        final highlight = _text(BannerField.highlight);
        return [
          if (subtitle.isNotEmpty) label(subtitle),
          if (title.isNotEmpty) titleText(title),
          _Versus(
            style: style,
            team: _text(BannerField.team),
            opponent: _text(BannerField.opponent),
            teamLogoUrl: teamLogoUrl,
            opponentLogoUrl: opponentLogoUrl,
            center: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: style.accent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                '${_text(BannerField.teamScore)} × '
                '${_text(BannerField.opponentScore)}',
                style: t.title(0.85, color: style.onAccent),
              ),
            ),
          ),
          if (outcome != null) _Chip(text: outcome, style: style),
          if (highlight.isNotEmpty) Text(highlight, style: t.body),
        ];
      case BannerTemplate.callUp:
        final names = [
          for (final line in _text(BannerField.names).split('\n'))
            if (line.trim().isNotEmpty) line.trim(),
        ];
        return [
          header(),
          if (title.isNotEmpty) titleText(title),
          if (subtitle.isNotEmpty) label(subtitle),
          if (names.isNotEmpty) _NameList(names: names, style: style),
          _WhenWhere(
            style: style,
            date: _text(BannerField.date),
            time: _text(BannerField.time),
            place: _text(BannerField.place),
          ),
        ];
      case BannerTemplate.birthday:
        final person = _text(BannerField.person);
        return [
          header(),
          if (title.isNotEmpty) titleText(title),
          _FeaturedPhoto(
            image: featuredPhoto,
            style: style,
            round: true,
            fallback: Icons.cake_outlined,
          ),
          if (person.isNotEmpty) titleText(person, scale: 0.6),
          if (message.isNotEmpty) Text(message, style: t.body),
        ];
      case BannerTemplate.champion:
        final team = _text(BannerField.team);
        return [
          if (subtitle.isNotEmpty) label(subtitle),
          if (featuredPhoto != null)
            _FeaturedPhoto(image: featuredPhoto, style: style, round: false)
          else if (style.showLogo && teamLogoUrl != null)
            _Crest(url: teamLogoUrl, size: 110, style: style)
          else
            Icon(Icons.emoji_events, size: 96, color: style.accent),
          if (title.isNotEmpty) titleText(title, scale: 1.15),
          if (team.isNotEmpty) titleText(team, scale: 0.55),
          if (message.isNotEmpty) Text(message, style: t.body),
        ];
      case BannerTemplate.notice:
        return [
          header(),
          if (title.isNotEmpty) titleText(title),
          if (subtitle.isNotEmpty) label(subtitle),
          if (message.isNotEmpty)
            Text(message, style: t.body.copyWith(fontSize: t.bodySize * 1.2)),
        ];
    }
  }
}

/// Os estilos de texto do banner.
class _BannerText {
  _BannerText(this.style);

  final BannerStyle style;

  double get bodySize => 15 * style.bodyScale;

  TextStyle get body => style.bodyFont.apply(
    TextStyle(
      fontSize: bodySize,
      height: 1.3,
      color: style.text,
      fontWeight: FontWeight.w500,
    ),
  );

  TextStyle title(double scale, {Color? color}) => style.titleFont.apply(
    TextStyle(
      fontSize: 54 * style.titleScale * scale,
      height: 1,
      color: color ?? style.text,
      fontWeight: FontWeight.w700,
    ),
  );

  TextStyle get name => style.bodyFont.apply(
    TextStyle(
      fontSize: 16 * style.bodyScale,
      height: 1.15,
      color: style.text,
      fontWeight: FontWeight.w700,
    ),
  );

  TextStyle get label => style.bodyFont.apply(
    TextStyle(
      fontSize: 12 * style.bodyScale,
      letterSpacing: 1.6,
      color: style.accent,
      fontWeight: FontWeight.w700,
    ),
  );
}

/// Coluna centralizada que encolhe tudo junto quando não cabe (o formato
/// quadrado com muitos textos).
class _FitColumn extends StatelessWidget {
  const _FitColumn({required this.children, required this.gap});

  final List<Widget> children;
  final double gap;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => FittedBox(
      fit: BoxFit.scaleDown,
      child: SizedBox(
        width: constraints.maxWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (index, child) in children.indexed) ...[
              if (index > 0) SizedBox(height: gap),
              child,
            ],
          ],
        ),
      ),
    ),
  );
}

class _Label extends StatelessWidget {
  const _Label({required this.text, required this.style});

  final String text;
  final BannerStyle style;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: _BannerText(style).label,
    textAlign: TextAlign.center,
  );
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, required this.style});

  final String text;
  final BannerStyle style;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
    decoration: BoxDecoration(
      border: Border.all(color: style.accent, width: 1.5),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(text, style: _BannerText(style).label),
  );
}

/// Escudo do time e o nome, no topo dos modelos sem o confronto.
class _TeamHeader extends StatelessWidget {
  const _TeamHeader({
    required this.name,
    required this.logoUrl,
    required this.style,
  });

  final String name;
  final String? logoUrl;
  final BannerStyle style;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (logoUrl != null) ...[
        _Crest(url: logoUrl, size: 34, style: style),
        const SizedBox(width: 10),
      ],
      Flexible(
        child: Text(
          name.toUpperCase(),
          style: _BannerText(style).label.copyWith(color: style.text),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
  );
}

/// Os dois times lado a lado, com o [center] no meio (× ou o placar).
class _Versus extends StatelessWidget {
  const _Versus({
    required this.style,
    required this.team,
    required this.opponent,
    required this.teamLogoUrl,
    required this.opponentLogoUrl,
    required this.center,
  });

  final BannerStyle style;
  final String team;
  final String opponent;
  final String? teamLogoUrl;
  final String? opponentLogoUrl;
  final Widget center;

  @override
  Widget build(BuildContext context) {
    Widget side(String name, String? logoUrl) => Expanded(
      child: Column(
        children: [
          if (style.showLogo) ...[
            _Crest(url: logoUrl, size: 76, style: style),
            const SizedBox(height: 10),
          ],
          Text(
            name,
            style: _BannerText(style).name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        side(team, teamLogoUrl),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          // Placar grande (título no máximo) encolhe em vez de estourar.
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 140),
            child: FittedBox(fit: BoxFit.scaleDown, child: center),
          ),
        ),
        side(opponent, opponentLogoUrl),
      ],
    );
  }
}

/// Data e horário em destaque e o local embaixo.
class _WhenWhere extends StatelessWidget {
  const _WhenWhere({
    required this.style,
    required this.date,
    required this.time,
    required this.place,
  });

  final BannerStyle style;
  final String date;
  final String time;
  final String place;

  @override
  Widget build(BuildContext context) {
    final t = _BannerText(style);
    final when = [date, time].where((text) => text.isNotEmpty).join('  ·  ');
    if (when.isEmpty && place.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        if (when.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: style.accent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              when.toUpperCase(),
              style: t.name.copyWith(color: style.onAccent, letterSpacing: 1),
            ),
          ),
        if (place.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.place, size: t.bodySize * 1.1, color: style.accent),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  place,
                  style: t.body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Os convocados, em duas colunas quando são muitos.
class _NameList extends StatelessWidget {
  const _NameList({required this.names, required this.style});

  final List<String> names;
  final BannerStyle style;

  @override
  Widget build(BuildContext context) {
    final t = _BannerText(style);
    Widget item(String name) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: style.accent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              name,
              style: t.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
    if (names.length <= 8) {
      return Column(children: [for (final name in names) item(name)]);
    }
    final half = (names.length / 2).ceil();
    Widget column(Iterable<String> part) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [for (final name in part) item(name)],
      ),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        column(names.take(half)),
        const SizedBox(width: 12),
        column(names.skip(half)),
      ],
    );
  }
}

/// Escudo redondo; sem imagem, um escudo desenhado na cor de destaque.
class _Crest extends StatelessWidget {
  const _Crest({required this.url, required this.size, required this.style});

  final String? url;
  final double size;
  final BannerStyle style;

  @override
  Widget build(BuildContext context) {
    final fallback = Icon(Icons.shield, size: size * 0.8, color: style.accent);
    return SizedBox.square(
      dimension: size,
      child: switch (url) {
        final url? => ClipOval(
          child: Image.network(
            url,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => fallback,
          ),
        ),
        null => fallback,
      },
    );
  }
}

/// A foto em destaque, com a borda na cor de destaque.
class _FeaturedPhoto extends StatelessWidget {
  const _FeaturedPhoto({
    required this.image,
    required this.style,
    required this.round,
    this.fallback = Icons.photo_outlined,
  });

  final ImageProvider? image;
  final BannerStyle style;
  final bool round;
  final IconData fallback;

  @override
  Widget build(BuildContext context) {
    final size = round ? const Size(150, 150) : const Size(300, 190);
    final radius = BorderRadius.circular(round ? size.width : 16);
    return Container(
      width: size.width,
      height: size.height,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: style.accent, borderRadius: radius),
      child: ClipRRect(
        borderRadius: radius,
        child: switch (image) {
          final image? => Image(image: image, fit: BoxFit.cover),
          null => ColoredBox(
            color: style.background,
            child: Icon(fallback, size: 64, color: style.accent),
          ),
        },
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.style, required this.text});

  final BannerStyle style;
  final String text;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty && !style.showBrand) return const SizedBox.shrink();
    final muted = style.text.withValues(alpha: 0.75);
    return Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: _BannerText(style).label.copyWith(color: muted),
            textAlign: TextAlign.start,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (style.showBrand) BannerBrandMark(style: style),
      ],
    );
  }
}

/// A marca SportLeague (o logo ou só o símbolo) nas cores escolhidas em
/// [BannerStyle.brandColor]: o verde do desenho vira a cor do desenho e as
/// letras ([SvgTheme.currentColor]) a das letras.
class BannerBrandMark extends StatelessWidget {
  const BannerBrandMark({super.key, required this.style, this.scale = 1});

  final BannerStyle style;

  /// Para a miniatura da escolha na aba Estilo.
  final double scale;

  @override
  Widget build(BuildContext context) {
    final colors = style.brandColor.resolve(style);
    final mapper = _BrandColorMapper(colors.mark);
    return switch (style.brand) {
      BannerBrand.none => const SizedBox.shrink(),
      BannerBrand.logo => SvgPicture.asset(
        'assets/images/logo.svg',
        width: 78 * scale,
        semanticsLabel: 'SportLeague',
        colorMapper: mapper,
        theme: SvgTheme(currentColor: colors.word),
      ),
      BannerBrand.symbol => SvgPicture.asset(
        'assets/images/symbol.svg',
        height: 26 * scale,
        semanticsLabel: 'SportLeague',
        colorMapper: mapper,
      ),
    };
  }
}

/// Troca o verde da marca pela cor [mark]. Igualdade pela cor, para o cache
/// do SVG desenhar de novo quando ela muda.
class _BrandColorMapper extends ColorMapper {
  const _BrandColorMapper(this.mark);

  final Color mark;

  @override
  Color substitute(
    String? id,
    String elementName,
    String attributeName,
    Color color,
  ) =>
      color.toARGB32() == BannerBrandColor.brandGreen.toARGB32() ? mark : color;

  @override
  bool operator ==(Object other) =>
      other is _BrandColorMapper && other.mark == mark;

  @override
  int get hashCode => mark.hashCode;
}

/// O desenho do fundo ([BannerPattern]), na cor de destaque por cima da cor
/// do fundo.
class BannerPatternPainter extends CustomPainter {
  BannerPatternPainter(this.style);

  final BannerStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // Listras, raios e colmeia passam da borda: nada sai do banner.
    canvas.clipRect(rect);
    final background = style.background;
    final accent = style.accent;
    final paint = Paint()..color = background;
    canvas.drawRect(rect, paint);

    switch (style.pattern) {
      case BannerPattern.solid:
        break;
      case BannerPattern.gradient:
        canvas.drawRect(
          rect,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [background, Color.lerp(background, accent, 0.55)!],
            ).createShader(rect),
        );
      case BannerPattern.stripes:
        final stripe = Paint()
          ..color = accent.withValues(alpha: 0.12)
          ..strokeWidth = 18;
        for (var x = -size.height; x < size.width; x += 46) {
          canvas.drawLine(
            Offset(x, size.height),
            Offset(x + size.height, 0),
            stripe,
          );
        }
      case BannerPattern.dots:
        final dot = Paint()..color = accent.withValues(alpha: 0.2);
        for (var y = 8.0; y < size.height; y += 16) {
          for (var x = 8.0; x < size.width; x += 16) {
            // Os pontos crescem para baixo.
            canvas.drawCircle(Offset(x, y), 0.6 + 2.2 * y / size.height, dot);
          }
        }
      case BannerPattern.rays:
        final center = Offset(size.width / 2, size.height * 0.42);
        final reach = size.longestSide * 1.2;
        final ray = Paint()..color = accent.withValues(alpha: 0.12);
        const count = 18;
        for (var i = 0; i < count; i++) {
          final start = i * 2 * pi / count;
          const sweep = pi / count;
          canvas.drawPath(
            Path()
              ..moveTo(center.dx, center.dy)
              ..lineTo(
                center.dx + reach * cos(start),
                center.dy + reach * sin(start),
              )
              ..lineTo(
                center.dx + reach * cos(start + sweep),
                center.dy + reach * sin(start + sweep),
              )
              ..close(),
            ray,
          );
        }
      case BannerPattern.pitch:
        _paintPitch(canvas, size);
      case BannerPattern.diagonal:
        // Metade de baixo em diagonal, com um filete na borda.
        final top = Offset(size.width, size.height * 0.36);
        final bottom = Offset(0, size.height * 0.64);
        canvas.drawPath(
          Path()
            ..moveTo(bottom.dx, bottom.dy)
            ..lineTo(top.dx, top.dy)
            ..lineTo(size.width, size.height)
            ..lineTo(0, size.height)
            ..close(),
          Paint()..color = accent.withValues(alpha: 0.22),
        );
        canvas.drawLine(
          bottom,
          top,
          Paint()
            ..color = accent.withValues(alpha: 0.7)
            ..strokeWidth = 3,
        );
      case BannerPattern.sash:
        // Faixa transversal, como a de uma camisa, com dois filetes.
        final band = Paint()
          ..color = accent.withValues(alpha: 0.24)
          ..strokeWidth = 74;
        final line = Paint()
          ..color = accent.withValues(alpha: 0.5)
          ..strokeWidth = 3;
        final from = Offset(-20, size.height * 0.05);
        final to = Offset(size.width + 20, size.height * 0.95);
        canvas.drawLine(from, to, band);
        for (final shift in const [-48.0, 48.0]) {
          canvas.drawLine(
            from.translate(shift, -shift * 0.4),
            to.translate(shift, -shift * 0.4),
            line,
          );
        }
      case BannerPattern.waves:
        // Ondas sobrepostas, mais fortes embaixo.
        for (var i = 0; i < 4; i++) {
          final base = size.height * (0.55 + i * 0.12);
          final amplitude = 14.0 + i * 4;
          final path = Path()..moveTo(0, base);
          for (var x = 0.0; x <= size.width; x += 6) {
            path.lineTo(
              x,
              base + amplitude * sin(x / size.width * 2 * pi + i * 1.3),
            );
          }
          path
            ..lineTo(size.width, size.height)
            ..lineTo(0, size.height)
            ..close();
          canvas.drawPath(path, Paint()..color = accent.withValues(alpha: 0.1));
        }
      case BannerPattern.checkers:
        const side = 30.0;
        final square = Paint()..color = accent.withValues(alpha: 0.07);
        for (var row = 0; row * side < size.height; row++) {
          for (
            var col = row.isEven ? 0 : 1;
            col * side < size.width;
            col += 2
          ) {
            canvas.drawRect(
              Rect.fromLTWH(col * side, row * side, side, side),
              square,
            );
          }
        }
      case BannerPattern.glow:
        canvas.drawRect(
          rect,
          Paint()
            ..shader = RadialGradient(
              center: const Alignment(0, -0.2),
              radius: 0.85,
              colors: [
                accent.withValues(alpha: 0.5),
                accent.withValues(alpha: 0),
              ],
            ).createShader(rect),
        );
      case BannerPattern.ball:
        paintBall(canvas, size, accent);
      case BannerPattern.net:
        paintNet(canvas, size, accent);
      case BannerPattern.goal:
        paintGoal(canvas, size, accent);
      case BannerPattern.stadium:
        paintStadium(canvas, size, accent);
      case BannerPattern.grass:
        paintGrass(canvas, size, accent);
      case BannerPattern.tactics:
        paintTactics(canvas, size, accent);
      case BannerPattern.corner:
        paintCorner(canvas, size, accent);
      case BannerPattern.centerCircle:
        paintCenterCircle(canvas, size, accent);
      case BannerPattern.honeycomb:
        const radius = 18.0;
        final width = sqrt(3) * radius;
        final cell = Paint()
          ..color = accent.withValues(alpha: 0.14)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
        for (var row = 0; row * radius * 1.5 < size.height + radius; row++) {
          final y = row * radius * 1.5;
          final offset = row.isOdd ? width / 2 : 0;
          for (var x = offset - width; x < size.width + width; x += width) {
            final hexagon = Path();
            for (var corner = 0; corner < 6; corner++) {
              final angle = pi / 6 + corner * pi / 3;
              final point = Offset(
                x + radius * cos(angle),
                y + radius * sin(angle),
              );
              corner == 0
                  ? hexagon.moveTo(point.dx, point.dy)
                  : hexagon.lineTo(point.dx, point.dy);
            }
            canvas.drawPath(hexagon..close(), cell);
          }
        }
    }
  }

  /// Gramado com faixas de corte e as linhas do campo (visto de cima).
  void _paintPitch(Canvas canvas, Size size) {
    final accent = style.accent;
    const bands = 8;
    final bandHeight = size.height / bands;
    final mow = Paint()..color = accent.withValues(alpha: 0.06);
    for (var i = 0; i < bands; i += 2) {
      canvas.drawRect(
        Rect.fromLTWH(0, i * bandHeight, size.width, bandHeight),
        mow,
      );
    }
    final line = Paint()
      ..color = accent.withValues(alpha: 0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final field = Rect.fromLTRB(14, 14, size.width - 14, size.height - 14);
    final center = field.center;
    canvas
      ..drawRect(field, line)
      ..drawLine(
        Offset(field.left, center.dy),
        Offset(field.right, center.dy),
        line,
      )
      ..drawCircle(center, size.width * 0.17, line)
      ..drawCircle(center, 3, line..style = PaintingStyle.fill);
    line.style = PaintingStyle.stroke;
    for (final top in [true, false]) {
      final penalty = Rect.fromCenter(
        center: Offset(
          center.dx,
          top
              ? field.top + size.height * 0.08
              : field.bottom - size.height * 0.08,
        ),
        width: field.width * 0.6,
        height: size.height * 0.16,
      );
      final goal = Rect.fromCenter(
        center: Offset(
          center.dx,
          top
              ? field.top + size.height * 0.03
              : field.bottom - size.height * 0.03,
        ),
        width: field.width * 0.28,
        height: size.height * 0.06,
      );
      canvas
        ..drawRect(penalty, line)
        ..drawRect(goal, line);
    }
  }

  @override
  bool shouldRepaint(BannerPatternPainter oldDelegate) =>
      oldDelegate.style != style;
}
