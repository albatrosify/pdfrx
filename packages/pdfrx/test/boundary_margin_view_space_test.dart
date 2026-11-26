import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';

/// hello.pdf is 3 uniform A4 pages.
final testPdfFile = File('example/viewer/assets/hello.pdf');

/// CREWLINE PATCH: PdfViewerParams.boundaryMarginInViewSpace.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => pdfrxInitialize());

  Future<void> settle(WidgetTester tester, {int frames = 20}) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<PdfViewerController> mount(WidgetTester tester, {required bool inViewSpace}) async {
    tester.view.physicalSize = const Size(1600, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final doc = (await tester.runAsync(
      () => PdfDocument.openData(testPdfFile.readAsBytesSync(), sourceName: 'boundary-margin-view-space.pdf'),
    ))!;
    addTearDown(doc.dispose);
    final controller = PdfViewerController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 400,
              height: 800,
              child: PdfViewer(
                PdfDocumentRefDirect(doc, autoDispose: false),
                controller: controller,
                params: PdfViewerParams(
                  boundaryMargin: const EdgeInsets.only(top: 120, bottom: 90),
                  boundaryMarginInViewSpace: inViewSpace,
                  behaviorControlParams: const PdfViewerBehaviorControlParams(trailingPageLoadingDelay: Duration.zero),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 100 && !controller.isReady; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await settle(tester);
    return controller;
  }

  /// Zooms to [zoom] while asking for a position far above the document, so the result is clamped
  /// to the top boundary. Returns the on-screen distance (view pixels) from the view's top edge to
  /// the document's top edge.
  Future<double> topGapAt(WidgetTester tester, PdfViewerController c, double zoom) async {
    await c.setZoom(Offset(c.documentSize.width / 2, -100000), zoom, duration: Duration.zero);
    await settle(tester);
    expect(c.currentZoom, moreOrLessEquals(zoom, epsilon: 0.001));
    return -c.visibleRect.top * c.currentZoom;
  }

  Future<double> bottomGapAt(WidgetTester tester, PdfViewerController c, double zoom) async {
    await c.setZoom(Offset(c.documentSize.width / 2, 100000), zoom, duration: Duration.zero);
    await settle(tester);
    return (c.visibleRect.bottom - c.documentSize.height) * c.currentZoom;
  }

  testWidgets('view-space margin keeps the same on-screen gap at every zoom', (tester) async {
    final c = await mount(tester, inViewSpace: true);
    for (final zoom in [0.5, 0.8, 1.0, 2.0]) {
      expect(await topGapAt(tester, c, zoom), moreOrLessEquals(120, epsilon: 0.5), reason: 'top at zoom $zoom');
      expect(await bottomGapAt(tester, c, zoom), moreOrLessEquals(90, epsilon: 0.5), reason: 'bottom at zoom $zoom');
    }
  });

  testWidgets('default (document-space) margin scales with zoom, as upstream', (tester) async {
    final c = await mount(tester, inViewSpace: false);
    for (final zoom in [0.5, 2.0]) {
      expect(await topGapAt(tester, c, zoom), moreOrLessEquals(120 * zoom, epsilon: 0.5), reason: 'zoom $zoom');
    }
  });
}
