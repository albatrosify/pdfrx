import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

/// Engine stand-in whose [init] can be held open to reproduce the window where
/// pdfrxFlutterInitialize() is still pending. [openFile] records the call and
/// never completes, so "was the document load started?" is directly observable
/// without rendering pdfrx's error UI.
class _GatedEntryFunctions implements PdfrxEntryFunctions {
  _GatedEntryFunctions(this.initGate);

  final Future<void> Function() initGate;
  final openedFiles = <String>[];

  @override
  Future<void> init() => initGate();

  @override
  Future<PdfDocument> openFile(
    String filePath, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool useProgressiveLoading = false,
  }) {
    openedFiles.add(filePath);
    return Completer<PdfDocument>().future; // stays pending forever
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Own file on purpose: pdfrx caches `_isInitialized` statically, so an earlier
// test that completed init would short-circuit pdfrxFlutterInitialize() and
// hide the race.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('document load survives a rebuild during pdfrxFlutterInitialize', (tester) async {
    final fakeCache = Directory.systemTemp.createTempSync('pdfrx_ref_race');
    addTearDown(() => fakeCache.deleteSync(recursive: true));
    Pdfrx.cacheDirectoryPath = fakeCache.path;

    final initGate = Completer<void>();
    final engine = _GatedEntryFunctions(() => initGate.future);
    PdfrxEntryFunctions.instance = engine;

    Widget viewer() => MaterialApp(home: PdfViewer.file('/tmp/roster.pdf'));

    // Frame 1: viewer created, pdfrxFlutterInitialize() now pending on the gate.
    await tester.pumpWidget(viewer());
    // Frame 2: rebuild with a fresh-but-equal PdfDocumentRefFile lands inside
    // the pending-init window (startup MediaQuery/provider churn does this).
    await tester.pumpWidget(viewer());

    initGate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      engine.openedFiles,
      ['/tmp/roster.pdf'],
      reason: 'The document load must still start after a rebuild during '
          'pdfrxFlutterInitialize(). An empty list means _widgetUpdated silently '
          'dropped the load because the rebuilt PdfDocumentRef was not '
          'instance-identical -- the cold-launch blank-viewer bug.',
    );
  });
}
