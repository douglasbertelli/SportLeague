import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sport_league/core/widgets/circle_image.dart';

/// PNG 4x4 gerado na hora, para a imagem decodificar de verdade.
Future<Uint8List> _png() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    const Rect.fromLTWH(0, 0, 4, 4),
    Paint()..color = const Color(0xFF2E7D32),
  );
  final image = await recorder.endRecording().toImage(4, 4);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

Future<void> _pump(WidgetTester tester, ImageProvider? image) =>
    tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: CircleImage(
            image: image,
            radius: 20,
            placeholder: const Icon(Icons.shield_outlined),
          ),
        ),
      ),
    );

void main() {
  testWidgets('sem imagem: círculo colorido com o escudo', (tester) async {
    await _pump(tester, null);
    expect(find.byType(CircleAvatar), findsOneWidget);
    expect(find.byIcon(Icons.shield_outlined), findsOneWidget);
  });

  testWidgets('imagem carregada: só a imagem, sem o fundo', (tester) async {
    await tester.runAsync(() async {
      final image = MemoryImage(await _png());
      await _pump(tester, image);
      // Enquanto carrega, o escudo aparece.
      expect(find.byType(CircleAvatar), findsOneWidget);
      await precacheImage(image, tester.element(find.byType(CircleImage)));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    expect(find.byType(CircleAvatar), findsNothing);
    expect(find.byIcon(Icons.shield_outlined), findsNothing);
  });

  testWidgets('imagem que falha volta ao escudo', (tester) async {
    await tester.runAsync(() async {
      await _pump(tester, MemoryImage(Uint8List.fromList([1, 2, 3])));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    expect(find.byIcon(Icons.shield_outlined), findsOneWidget);
  });
}
