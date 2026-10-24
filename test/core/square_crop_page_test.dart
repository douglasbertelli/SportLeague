import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sport_league/core/media/picked_image.dart';
import 'package:sport_league/core/media/square_crop_page.dart';
import 'package:sport_league/core/theme/app_theme.dart';

Future<Uint8List> _png(int width, int height) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFF2E7D32),
  );
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

void main() {
  testWidgets('recorta em quadrado e devolve PNG', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    PickedImage? result;
    await tester.runAsync(() async {
      final bytes = await _png(60, 30);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await Navigator.of(context)
                  .push<PickedImage>(
                    MaterialPageRoute(
                      builder: (_) => SquareCropPage(
                        image: PickedImage(
                          bytes: bytes,
                          contentType: 'image/png',
                        ),
                      ),
                    ),
                  ),
              child: const Text('abrir'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      await tester.tap(find.text('Usar'));
      for (var i = 0; i < 20 && result == null; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    expect(result?.contentType, 'image/png');
    final decoded = await tester.runAsync(
      () async => (await (await ui.instantiateImageCodec(
        result!.bytes,
      )).getNextFrame()).image,
    );
    expect(decoded!.width, decoded.height);
  });
}
