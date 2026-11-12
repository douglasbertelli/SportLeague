import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../games/domain/game.dart';

/// Modelos de banner que o administrador escolhe.
enum BannerTemplate {
  gameDay(
    'Dia de jogo',
    'Anúncio do próximo jogo',
    Icons.campaign_outlined,
    fields: [
      BannerField.title,
      BannerField.subtitle,
      BannerField.team,
      BannerField.opponent,
      BannerField.date,
      BannerField.time,
      BannerField.place,
      BannerField.message,
      BannerField.footer,
    ],
  ),
  result(
    'Resultado',
    'Placar do jogo',
    Icons.scoreboard_outlined,
    fields: [
      BannerField.title,
      BannerField.subtitle,
      BannerField.team,
      BannerField.teamScore,
      BannerField.opponent,
      BannerField.opponentScore,
      BannerField.highlight,
      BannerField.footer,
    ],
  ),
  callUp(
    'Convocação',
    'Lista de convocados',
    Icons.groups_outlined,
    fields: [
      BannerField.title,
      BannerField.subtitle,
      BannerField.names,
      BannerField.date,
      BannerField.time,
      BannerField.place,
      BannerField.footer,
    ],
  ),
  birthday(
    'Aniversariante',
    'Parabéns para o atleta',
    Icons.cake_outlined,
    featuredPhoto: true,
    fields: [
      BannerField.title,
      BannerField.person,
      BannerField.message,
      BannerField.footer,
    ],
  ),
  champion(
    'Campeão',
    'Título conquistado',
    Icons.emoji_events_outlined,
    featuredPhoto: true,
    fields: [
      BannerField.title,
      BannerField.subtitle,
      BannerField.team,
      BannerField.message,
      BannerField.footer,
    ],
  ),
  notice(
    'Aviso',
    'Recado livre para o time',
    Icons.notes_outlined,
    fields: [
      BannerField.title,
      BannerField.subtitle,
      BannerField.message,
      BannerField.footer,
    ],
  );

  const BannerTemplate(
    this.label,
    this.description,
    this.icon, {
    required this.fields,
    this.featuredPhoto = false,
  });

  final String label;
  final String description;
  final IconData icon;

  /// Os textos editáveis, na ordem do formulário.
  final List<BannerField> fields;

  /// Tem uma foto em destaque (a do aniversariante, a do time campeão).
  final bool featuredPhoto;

  static BannerTemplate fromName(String? name) =>
      values.where((template) => template.name == name).firstOrNull ?? gameDay;
}

/// Um texto editável do banner.
enum BannerField {
  title('Título'),
  subtitle('Linha de apoio'),
  team('Seu time'),
  opponent('Adversário'),
  date('Data'),
  time('Horário'),
  place('Local'),
  teamScore('Gols do seu time', number: true),
  opponentScore('Gols do adversário', number: true),
  highlight('Destaque (gols, craque)', lines: 3),
  names('Convocados (um por linha)', lines: 8),
  person('Nome do aniversariante'),
  message('Mensagem', lines: 4),
  footer('Rodapé (Instagram, site)');

  const BannerField(this.label, {this.lines = 1, this.number = false});

  final String label;

  /// Linhas do campo no formulário (1 = uma linha só).
  final int lines;
  final bool number;
}

/// Os textos de cada campo.
typedef BannerTexts = Map<BannerField, String>;

/// Textos iniciais do [template]: o time e, com o [game], o adversário, a
/// data, o local e o placar do ponto de vista de [teamId].
BannerTexts defaultTexts(
  BannerTemplate template, {
  required String teamName,
  String? teamId,
  String? instagram,
  Game? game,
  DateTime? now,
}) {
  final today = now ?? DateTime.now();
  final viewer = teamId ?? game?.teamId;
  final opponent = game == null || viewer == null
      ? ''
      : game.opponentNameFor(viewer);
  final score = game == null || viewer == null ? null : game.scoreFor(viewer);
  final kind = switch (game) {
    final game? when game.championship != null =>
      '${game.championship!.name} · ${game.championship!.stageLabel}',
    final game? when game.modality != null =>
      'Amistoso · ${game.modality!.label}',
    _ => 'Amistoso',
  };
  final date = game == null ? '' : bannerDate(game.scheduledAt);
  final time = game == null ? '' : bannerTime(game.scheduledAt);
  final place = game?.venue?.name ?? game?.location ?? '';
  final footer = instagram == null || instagram.isEmpty ? '' : '@$instagram';

  return switch (template) {
    BannerTemplate.gameDay => {
      BannerField.title: 'DIA DE JOGO',
      BannerField.subtitle: kind,
      BannerField.team: teamName,
      BannerField.opponent: opponent.isEmpty ? 'Adversário' : opponent,
      BannerField.date: date.isEmpty ? bannerDate(today) : date,
      BannerField.time: time.isEmpty ? '20:00' : time,
      BannerField.place: place,
      BannerField.message: 'Vem com a gente!',
      BannerField.footer: footer,
    },
    BannerTemplate.result => {
      BannerField.title: 'FIM DE JOGO',
      BannerField.subtitle: game == null ? kind : '$kind · $date',
      BannerField.team: teamName,
      BannerField.teamScore: '${score?.$1 ?? 0}',
      BannerField.opponent: opponent.isEmpty ? 'Adversário' : opponent,
      BannerField.opponentScore: '${score?.$2 ?? 0}',
      BannerField.highlight: '',
      BannerField.footer: footer,
    },
    BannerTemplate.callUp => {
      BannerField.title: 'CONVOCADOS',
      BannerField.subtitle: opponent.isEmpty
          ? teamName
          : '$teamName × $opponent',
      BannerField.names: '',
      BannerField.date: date,
      BannerField.time: time,
      BannerField.place: place,
      BannerField.footer: footer,
    },
    BannerTemplate.birthday => {
      BannerField.title: 'PARABÉNS!',
      BannerField.person: '',
      BannerField.message:
          'Feliz aniversário! Muita saúde, alegria e gols. '
          'Conte sempre com o $teamName.',
      BannerField.footer: footer,
    },
    BannerTemplate.champion => {
      BannerField.title: 'CAMPEÃO!',
      BannerField.subtitle: game?.championship?.name ?? 'Campeonato',
      BannerField.team: teamName,
      BannerField.message: 'Obrigado a todos que fizeram parte! ${today.year}',
      BannerField.footer: footer,
    },
    BannerTemplate.notice => {
      BannerField.title: 'AVISO',
      BannerField.subtitle: teamName,
      BannerField.message: '',
      BannerField.footer: footer,
    },
  };
}

const _weekdays = ['SEG', 'TER', 'QUA', 'QUI', 'SEX', 'SÁB', 'DOM'];

/// "SÁB · 20/11".
String bannerDate(DateTime at) =>
    '${_weekdays[at.weekday - 1]} · ${_two(at.day)}/${_two(at.month)}';

/// "20h" ou "20h30".
String bannerTime(DateTime at) =>
    at.minute == 0 ? '${at.hour}h' : '${at.hour}h${_two(at.minute)}';

String _two(int value) => value.toString().padLeft(2, '0');

/// Tamanho da imagem. O banner é desenhado com 360 de largura e sai 3×
/// maior (1080 px).
enum BannerFormat {
  square('Quadrado', '1:1', Size(360, 360)),
  feed('Feed', '4:5', Size(360, 450)),
  story('Story', '9:16', Size(360, 640));

  const BannerFormat(this.label, this.ratio, this.size);

  final String label;
  final String ratio;
  final Size size;

  static BannerFormat fromName(String? name) =>
      values.where((format) => format.name == name).firstOrNull ?? feed;
}

/// Desenho do fundo.
enum BannerPattern {
  solid('Liso'),
  gradient('Degradê'),
  stripes('Listras'),
  dots('Pontos'),
  rays('Raios'),
  pitch('Campo'),
  diagonal('Diagonal'),
  sash('Faixa'),
  waves('Ondas'),
  checkers('Xadrez'),
  glow('Brilho'),
  honeycomb('Colmeia'),
  // Tema de futebol.
  ball('Bola'),
  net('Rede'),
  goal('Gol'),
  stadium('Estádio'),
  grass('Gramado'),
  tactics('Prancheta'),
  corner('Escanteio'),
  centerCircle('Meio-campo');

  const BannerPattern(this.label);

  final String label;

  static BannerPattern fromName(String? name) =>
      values.where((pattern) => pattern.name == name).firstOrNull ?? gradient;
}

/// Famílias de fonte. A DM Sans vem com o app; as outras são do Google
/// Fonts, baixadas na primeira vez e guardadas no aparelho.
enum BannerFont {
  dmSans('DM Sans', bundled: true),
  bebasNeue('Bebas Neue'),
  anton('Anton'),
  oswald('Oswald'),
  montserrat('Montserrat'),
  russoOne('Russo One'),
  teko('Teko'),
  permanentMarker('Permanent Marker');

  const BannerFont(this.family, {this.bundled = false});

  final String family;
  final bool bundled;

  /// [base] nesta família.
  TextStyle apply(TextStyle base) => bundled
      ? base.copyWith(fontFamily: family)
      : GoogleFonts.getFont(family, textStyle: base);

  static BannerFont fromName(String? name, BannerFont fallback) =>
      values.where((font) => font.name == name).firstOrNull ?? fallback;
}

/// A marca SportLeague no rodapé do banner.
enum BannerBrand {
  none('Sem marca'),
  logo('Logo'),
  symbol('Símbolo');

  const BannerBrand(this.label);

  final String label;

  static BannerBrand fromName(String? name) =>
      values.where((brand) => brand.name == name).firstOrNull ?? logo;
}

/// De onde vêm as cores da marca: o desenho (o "S", verde no original) e as
/// letras do logo.
enum BannerBrandColor {
  /// O desenho na cor de destaque e as letras na cor do texto: combina com
  /// a arte.
  art('Da arte'),

  /// Tudo na cor do texto, discreto.
  text('Uma cor'),

  /// O verde da marca e as letras na cor do texto.
  original('Original');

  const BannerBrandColor(this.label);

  final String label;

  /// O verde do símbolo nos arquivos do logo.
  static const brandGreen = Color(0xFF07F469);

  /// As cores do desenho e das letras com o [style].
  ({Color mark, Color word}) resolve(BannerStyle style) {
    final word = style.text.withValues(alpha: 0.85);
    return switch (this) {
      art => (mark: style.accent, word: word),
      text => (mark: word, word: word),
      original => (mark: brandGreen, word: word),
    };
  }

  static BannerBrandColor fromName(String? name) =>
      values.where((color) => color.name == name).firstOrNull ?? art;
}

/// Cores, fontes e o resto do visual. Fica salvo no aparelho por time.
@immutable
class BannerStyle {
  const BannerStyle({
    required this.background,
    required this.accent,
    required this.text,
    this.pattern = BannerPattern.gradient,
    this.format = BannerFormat.feed,
    this.titleFont = BannerFont.bebasNeue,
    this.bodyFont = BannerFont.dmSans,
    this.titleScale = 1,
    this.bodyScale = 1,
    this.showLogo = true,
    this.brand = BannerBrand.logo,
    this.brandColor = BannerBrandColor.art,
    this.backgroundDim = 0.55,
  });

  /// O padrão a partir da cor do time ([teamColor], o destaque).
  factory BannerStyle.forTeam(Color teamColor) {
    final hsl = HSLColor.fromColor(teamColor);
    // Fundo: a cor do time bem escura (cores neutras viram quase preto).
    final background = hsl.saturation < 0.1
        ? const Color(0xFF111111)
        : hsl
              .withLightness(0.14)
              .withSaturation(hsl.saturation * 0.7)
              .toColor();
    // Destaque visível sobre o fundo escuro (o preto vira branco).
    final accent = hsl.lightness < 0.3 && hsl.saturation < 0.1
        ? Colors.white
        : hsl.lightness < 0.35
        ? hsl.withLightness(0.55).toColor()
        : teamColor;
    return BannerStyle(
      background: background,
      accent: accent,
      text: Colors.white,
    );
  }

  final Color background;
  final Color accent;
  final Color text;
  final BannerPattern pattern;
  final BannerFormat format;
  final BannerFont titleFont;
  final BannerFont bodyFont;

  /// Multiplicadores do tamanho do título e dos textos (0,7 a 1,4).
  final double titleScale;
  final double bodyScale;

  /// Mostra o escudo do time (e o do adversário, quando houver).
  final bool showLogo;

  /// Qual marca SportLeague vai no rodapé (o logo, só o símbolo ou nada).
  final BannerBrand brand;

  /// De onde vêm as cores da marca.
  final BannerBrandColor brandColor;

  /// Mostra alguma marca no rodapé.
  bool get showBrand => brand != BannerBrand.none;

  /// Quanto a imagem de fundo escurece com a cor do fundo (0 a 0,9).
  final double backgroundDim;

  static const minScale = 0.7;
  static const maxScale = 1.4;

  /// Cor legível sobre o [accent] (o placar, as etiquetas).
  Color get onAccent =>
      ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
      ? Colors.white
      : Colors.black;

  BannerStyle copyWith({
    Color? background,
    Color? accent,
    Color? text,
    BannerPattern? pattern,
    BannerFormat? format,
    BannerFont? titleFont,
    BannerFont? bodyFont,
    double? titleScale,
    double? bodyScale,
    bool? showLogo,
    BannerBrand? brand,
    BannerBrandColor? brandColor,
    double? backgroundDim,
  }) => BannerStyle(
    background: background ?? this.background,
    accent: accent ?? this.accent,
    text: text ?? this.text,
    pattern: pattern ?? this.pattern,
    format: format ?? this.format,
    titleFont: titleFont ?? this.titleFont,
    bodyFont: bodyFont ?? this.bodyFont,
    titleScale: titleScale ?? this.titleScale,
    bodyScale: bodyScale ?? this.bodyScale,
    showLogo: showLogo ?? this.showLogo,
    brand: brand ?? this.brand,
    brandColor: brandColor ?? this.brandColor,
    backgroundDim: backgroundDim ?? this.backgroundDim,
  );

  String toJson() => jsonEncode({
    'background': background.toARGB32(),
    'accent': accent.toARGB32(),
    'text': text.toARGB32(),
    'pattern': pattern.name,
    'format': format.name,
    'title_font': titleFont.name,
    'body_font': bodyFont.name,
    'title_scale': titleScale,
    'body_scale': bodyScale,
    'show_logo': showLogo,
    'brand': brand.name,
    'brand_color': brandColor.name,
    'background_dim': backgroundDim,
  });

  /// O estilo salvo; o que faltar (ou um texto inválido) vem do [fallback].
  static BannerStyle fromJson(String? json, BannerStyle fallback) {
    if (json == null) return fallback;
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      Color color(String key, Color orElse) => switch (map[key]) {
        final int value => Color(value),
        _ => orElse,
      };
      double scale(String key) => switch (map[key]) {
        final num value => value.toDouble().clamp(minScale, maxScale),
        _ => 1,
      };
      return BannerStyle(
        background: color('background', fallback.background),
        accent: color('accent', fallback.accent),
        text: color('text', fallback.text),
        pattern: BannerPattern.fromName(map['pattern'] as String?),
        format: BannerFormat.fromName(map['format'] as String?),
        titleFont: BannerFont.fromName(
          map['title_font'] as String?,
          fallback.titleFont,
        ),
        bodyFont: BannerFont.fromName(
          map['body_font'] as String?,
          fallback.bodyFont,
        ),
        titleScale: scale('title_scale'),
        bodyScale: scale('body_scale'),
        showLogo: map['show_logo'] as bool? ?? true,
        // Antes era só ligar e desligar (o logo).
        brand: switch (map['brand']) {
          final String name => BannerBrand.fromName(name),
          _ when map['show_brand'] == false => BannerBrand.none,
          _ => BannerBrand.logo,
        },
        brandColor: BannerBrandColor.fromName(map['brand_color'] as String?),
        backgroundDim: switch (map['background_dim']) {
          final num value => value.toDouble().clamp(0, 0.9),
          _ => fallback.backgroundDim,
        },
      );
    } catch (_) {
      return fallback;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is BannerStyle && other.toJson() == toJson();

  @override
  int get hashCode => toJson().hashCode;
}

/// O que abrir no editor: o modelo e o jogo para preencher os textos.
class BannerArgs {
  const BannerArgs({this.template, this.game});

  final BannerTemplate? template;
  final Game? game;
}
