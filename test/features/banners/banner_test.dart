import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sport_league/core/storage/preferences_provider.dart';
import 'package:sport_league/features/banners/domain/banner_design.dart';
import 'package:sport_league/features/banners/presentation/banner_canvas.dart';
import 'package:sport_league/features/banners/presentation/banner_editor_page.dart';
import 'package:sport_league/features/banners/presentation/banner_style_tab.dart';
import 'package:sport_league/features/banners/presentation/banner_template_tab.dart';
import 'package:sport_league/features/banners/presentation/banner_texts_tab.dart';
import 'package:sport_league/features/games/domain/game.dart';
import 'package:sport_league/features/plans/domain/plan_status.dart';
import 'package:sport_league/features/teams/data/team_repository.dart';
import 'package:sport_league/features/teams/domain/team.dart';

const _team = Team(
  id: 'team-1',
  ownerId: 'user-1',
  name: 'Unidos da Vila',
  instagram: 'unidosdavila',
);

final _game = Game(
  id: 'game-1',
  teamId: 'team-1',
  opponent: 'Real Bairro',
  scheduledAt: DateTime(2026, 11, 21, 20),
  location: 'Arena Central',
  teamScore: 3,
  opponentScore: 1,
);

/// Estilo só com a DM Sans (vem com o app): os testes não baixam fontes.
const _offlineStyle = BannerStyle(
  background: Color(0xFF111111),
  accent: Color(0xFF07F469),
  text: Colors.white,
  titleFont: BannerFont.dmSans,
  bodyFont: BannerFont.dmSans,
);

void main() {
  group('textos iniciais', () {
    test('o anúncio do jogo vem com o adversário, a data e o local', () {
      final texts = defaultTexts(
        BannerTemplate.gameDay,
        teamName: _team.name,
        teamId: _team.id,
        instagram: _team.instagram,
        game: _game,
      );
      expect(texts[BannerField.team], 'Unidos da Vila');
      expect(texts[BannerField.opponent], 'Real Bairro');
      expect(texts[BannerField.date], 'SÁB · 21/11');
      expect(texts[BannerField.time], '20h');
      expect(texts[BannerField.place], 'Arena Central');
      expect(texts[BannerField.footer], '@unidosdavila');
    });

    test('o resultado vem com o placar do time', () {
      final texts = defaultTexts(
        BannerTemplate.result,
        teamName: _team.name,
        teamId: _team.id,
        game: _game,
      );
      expect(texts[BannerField.teamScore], '3');
      expect(texts[BannerField.opponentScore], '1');
    });

    test('todo modelo preenche os campos que mostra', () {
      for (final template in BannerTemplate.values) {
        final texts = defaultTexts(template, teamName: 'Time');
        expect(
          texts.keys.toSet(),
          template.fields.toSet(),
          reason: '$template',
        );
      }
    });

    test('horário com minutos', () {
      expect(bannerTime(DateTime(2026, 1, 1, 19, 30)), '19h30');
    });
  });

  group('estilo', () {
    test('salvo e lido de volta', () {
      final style = _offlineStyle.copyWith(
        pattern: BannerPattern.rays,
        format: BannerFormat.story,
        titleScale: 1.2,
        brand: BannerBrand.symbol,
        brandColor: BannerBrandColor.original,
      );
      final read = BannerStyle.fromJson(style.toJson(), _offlineStyle);
      expect(read, style);
    });

    test('a marca salva antes (liga e desliga) vira logo ou nada', () {
      final old = _offlineStyle.toJson().replaceFirst(
        RegExp(r'"brand":"\w+","brand_color":"\w+"'),
        '"show_brand":false',
      );
      expect(old, contains('show_brand'));
      expect(BannerStyle.fromJson(old, _offlineStyle).brand, BannerBrand.none);
      expect(
        BannerStyle.fromJson(
          old.replaceFirst('false', 'true'),
          _offlineStyle,
        ).brand,
        BannerBrand.logo,
      );
    });

    test('as cores da marca seguem a arte', () {
      final art = BannerBrandColor.art.resolve(_offlineStyle);
      expect(art.mark, _offlineStyle.accent);
      expect(
        art.word.toARGB32() & 0xFFFFFF,
        Colors.white.toARGB32() & 0xFFFFFF,
      );
      final mono = BannerBrandColor.text.resolve(_offlineStyle);
      expect(mono.mark, mono.word);
      expect(
        BannerBrandColor.original.resolve(_offlineStyle).mark,
        BannerBrandColor.brandGreen,
      );
    });

    test('texto inválido cai no padrão', () {
      expect(BannerStyle.fromJson('{nada', _offlineStyle), _offlineStyle);
      expect(BannerStyle.fromJson(null, _offlineStyle), _offlineStyle);
    });

    test('o padrão do time escurece o fundo e mantém o destaque visível', () {
      final green = BannerStyle.forTeam(const Color(0xFF07F469));
      expect(green.accent, const Color(0xFF07F469));
      expect(
        ThemeData.estimateBrightnessForColor(green.background),
        Brightness.dark,
      );
      // Time preto: o destaque vira branco para aparecer no fundo escuro.
      expect(BannerStyle.forTeam(Colors.black).accent, Colors.white);
    });
  });

  testWidgets('todos os modelos cabem em todos os formatos', (tester) async {
    tester.view
      ..physicalSize = const Size(1080, 2340)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    for (final format in BannerFormat.values) {
      for (final template in BannerTemplate.values) {
        final texts = defaultTexts(
          template,
          teamName: _team.name,
          teamId: _team.id,
          instagram: _team.instagram,
          game: _game,
        );
        if (template == BannerTemplate.callUp) {
          texts[BannerField.names] = List.generate(
            18,
            (i) => '${i + 1} · Atleta com nome comprido $i',
          ).join('\n');
        }
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: BannerCanvas(
                template: template,
                style: _offlineStyle.copyWith(
                  format: format,
                  titleScale: BannerStyle.maxScale,
                  bodyScale: BannerStyle.maxScale,
                ),
                texts: texts,
                teamName: _team.name,
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull, reason: '$template $format');
        expect(
          tester.getSize(find.byType(BannerCanvas)),
          format.size,
          reason: '$template $format',
        );
      }
    }
  });

  testWidgets('o editor mostra a prévia ao vivo e compartilha', (tester) async {
    SharedPreferences.setMockInitialValues({
      bannerStyleKey('team-1'): _offlineStyle.toJson(),
    });
    final preferences = await SharedPreferences.getInstance();
    // Tela de celular.
    tester.view
      ..physicalSize = const Size(1080, 2340)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    Uint8List? shared;
    String? sharedText;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          selectedTeamProvider.overrideWith((ref) async => _team),
          shareBannerProvider.overrideWithValue((png, text) async {
            shared = png;
            sharedText = text;
          }),
        ],
        child: MaterialApp(
          home: BannerEditorPage(
            args: BannerArgs(template: BannerTemplate.result, game: _game),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // A prévia grande é a primeira; as miniaturas da aba Modelo vêm depois.
    final canvas = find.byType(BannerCanvas).first;
    Finder inPreview(String text) =>
        find.descendant(of: canvas, matching: find.text(text));
    expect(inPreview('FIM DE JOGO'), findsOneWidget);
    expect(inPreview('VITÓRIA'), findsOneWidget);
    // Uma miniatura de cada modelo, além da prévia.
    expect(
      find.byType(BannerCanvas),
      findsNWidgets(BannerTemplate.values.length + 1),
    );

    // Editar o título muda a prévia na hora.
    await tester.tap(find.text('Textos'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Título'), 'GOLEADA');
    await tester.pump();
    expect(inPreview('GOLEADA'), findsOneWidget);

    // Título pronto e placar com o +.
    await tester.tap(find.text('VITÓRIA!'));
    await tester.pump();
    expect(inPreview('VITÓRIA!'), findsOneWidget);
    final textsList = find
        .descendant(
          of: find.byType(BannerTextsTab),
          matching: find.byType(Scrollable),
        )
        .first;
    final plusOne = find.byTooltip('Mais um gol de Unidos da Vila');
    await tester.scrollUntilVisible(plusOne, 80, scrollable: textsList);
    await tester.tap(plusOne);
    await tester.pump();
    expect(inPreview('4 × 1'), findsOneWidget);

    // Restaurar volta os textos iniciais do modelo.
    final reset = find.text('Restaurar');
    await tester.scrollUntilVisible(reset, -80, scrollable: textsList);
    await tester.tap(reset);
    await tester.pump();
    expect(inPreview('FIM DE JOGO'), findsOneWidget);
    expect(inPreview('3 × 1'), findsOneWidget);

    // Trocar de modelo pela miniatura.
    await tester.tap(find.widgetWithText(Tab, 'Modelo'));
    await tester.pumpAndSettle();
    expect(find.byType(BannerTemplateTab), findsOneWidget);
    final callUp = find.bySemanticsLabel('Modelo Convocação');
    await tester.ensureVisible(callUp);
    await tester.pump();
    await tester.tap(callUp);
    await tester.pump();
    expect(inPreview('CONVOCADOS'), findsOneWidget);

    // Na convocação, o contador dos nomes.
    await tester.tap(find.widgetWithText(Tab, 'Textos'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Nenhum convocado'),
      80,
      scrollable: textsList,
    );
    expect(find.text('Nenhum convocado'), findsOneWidget);
    await tester.tap(find.widgetWithText(Tab, 'Modelo'));
    await tester.pumpAndSettle();

    // O estilo escolhido fica salvo para o time.
    final story = find.bySemanticsLabel('Formato Story 9:16');
    await tester.ensureVisible(story);
    await tester.pump();
    await tester.tap(story);
    await tester.pump();
    expect(tester.getSize(canvas).height, greaterThan(0));
    expect(
      BannerStyle.fromJson(
        preferences.getString(bannerStyleKey('team-1')),
        _offlineStyle,
      ).format,
      BannerFormat.story,
    );

    await tester.runAsync(() async {
      await tester.tap(find.text('Compartilhar'));
      // A captura da imagem roda fora do relógio falso dos testes.
      for (var i = 0; i < 20 && shared == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }
    });
    expect(shared, isNotNull);
    expect(sharedText, 'Unidos da Vila · CONVOCADOS');
  });

  testWidgets('todos os fundos desenham em todos os formatos', (tester) async {
    tester.view
      ..physicalSize = const Size(1080, 2340)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    expect(BannerPattern.values, hasLength(20));
    for (final pattern in BannerPattern.values) {
      for (final format in BannerFormat.values) {
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: BannerCanvas(
                template: BannerTemplate.notice,
                style: _offlineStyle.copyWith(pattern: pattern, format: format),
                texts: defaultTexts(BannerTemplate.notice, teamName: 'Time'),
                teamName: 'Time',
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull, reason: '$pattern $format');
      }
      // O fundo escolhido volta igual do estilo salvo.
      final saved = _offlineStyle.copyWith(pattern: pattern);
      expect(BannerStyle.fromJson(saved.toJson(), _offlineStyle), saved);
    }
  });

  testWidgets('aba Estilo: combinações, cores, fontes e imagem de fundo', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1080, 2340)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final team = BannerStyle.forTeam(const Color(0xFF1E88E5));
    var style = team.copyWith(
      titleFont: BannerFont.dmSans,
      bodyFont: BannerFont.dmSans,
    );
    var picked = 0;

    Future<void> pump() => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => BannerStyleTab(
              style: style,
              teamStyle: team,
              backgroundPhoto: null,
              onPickBackground: () => picked++,
              onChanged: (value) => setState(() => style = value),
            ),
          ),
        ),
      ),
    );
    await pump();

    // Combinação "Invertido": o fundo vira a cor do time.
    await tester.tap(find.bySemanticsLabel('Combinação Invertido'));
    await tester.pump();
    expect(style.background, team.accent);
    expect(style.text, team.onAccent);

    // Uma paleta só: escolhe "Texto" e toca no branco (o 3º da paleta).
    await tester.tap(find.text('Texto'));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Cor texto 3'));
    await tester.pump();
    expect(style.text, Colors.white);
    expect(style.background, team.accent);

    // Fundo pela miniatura (rolando a fila de fundos).
    await tester.dragUntilVisible(
      find.bySemanticsLabel('Fundo Campo'),
      find.bySemanticsLabel('Fundo Liso'),
      const Offset(-120, 0),
    );
    await tester.tap(find.bySemanticsLabel('Fundo Campo'));
    await tester.pump();
    expect(style.pattern, BannerPattern.pitch);

    // A imagem de fundo agora fica nesta aba.
    await tester.ensureVisible(find.text('Imagem de fundo'));
    await tester.tap(find.text('Imagem de fundo'));
    expect(picked, 1);

    // Tamanho do texto, não do título, depois de trocar para "Textos".
    await tester.ensureVisible(find.text('Textos'));
    await tester.tap(find.text('Textos'));
    await tester.pump();
    await tester.ensureVisible(find.byType(Slider));
    await tester.drag(find.byType(Slider), const Offset(200, 0));
    await tester.pump();
    expect(style.bodyScale, greaterThan(1));
    expect(style.titleScale, 1);

    // Marca: só o símbolo, com o verde original; depois sem marca.
    final symbol = find.bySemanticsLabel('Marca Símbolo');
    await tester.ensureVisible(symbol);
    await tester.pump();
    await tester.tap(symbol);
    await tester.pump();
    expect(style.brand, BannerBrand.symbol);
    final original = find.bySemanticsLabel('Cores da marca Original');
    await tester.ensureVisible(original);
    await tester.pump();
    await tester.tap(original);
    await tester.pump();
    expect(style.brandColor, BannerBrandColor.original);
    final none = find.bySemanticsLabel('Marca Sem marca');
    await tester.ensureVisible(none);
    await tester.pump();
    await tester.tap(none);
    await tester.pump();
    expect(style.showBrand, isFalse);
    // Sem marca, as cores da marca somem.
    expect(original, findsNothing);
  });

  testWidgets('os cartões de formato têm a mesma altura e a proporção cabe', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1080, 2340)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BannerTemplateTab(
            template: BannerTemplate.gameDay,
            style: _offlineStyle,
            textsOf: (template) => defaultTexts(template, teamName: 'Time'),
            teamName: 'Time',
            onTemplate: (_) {},
            onFormat: (_) {},
          ),
        ),
      ),
    );
    final heights = {
      for (final format in BannerFormat.values)
        tester
            .getSize(
              find.bySemanticsLabel('Formato ${format.label} ${format.ratio}'),
            )
            .height,
    };
    expect(heights, hasLength(1));
    // "9:16" numa linha só, dentro do retângulo estreito do Story.
    final ratio = find.text('9:16');
    expect(tester.getSize(ratio).height, lessThan(20));
    expect(tester.takeException(), isNull);
  });

  test('o banner é recurso do plano', () {
    expect(PlanFeature.fromKey('banners'), PlanFeature.banners);
    final free = PlanStatus.fromMap({
      'plan': 'free',
      'quotas': {'banners': 0},
    });
    expect(free.has(PlanFeature.banners), isFalse);
    expect(planLimitMessage(PlanFeature.banners, 0), contains('Premium'));
  });
}
