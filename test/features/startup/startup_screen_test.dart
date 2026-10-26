import 'dart:async';

import 'package:flashquest_drill/app.dart';
import 'package:flashquest_drill/features/decks/deck_list_screen.dart';
import 'package:flashquest_drill/features/startup/startup_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/controlled_repositories.dart';
import '../../support/memory_repositories.dart';
import '../../support/visual_capture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);
  late ControlledDeckRepository decks;
  late ControlledFlashcardRepository cards;
  late GlobalKey preview;

  setUp(() {
    final store = MemoryStore();
    decks = ControlledDeckRepository(MemoryDeckRepository(store));
    cards = ControlledFlashcardRepository(MemoryFlashcardRepository(store));
    preview = GlobalKey();
  });

  Future<void> start(
    WidgetTester tester,
    AppInitializer initialize, {
    Size size = const Size(412, 892),
    double scale = 1,
    bool animate = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      RepaintBoundary(
        key: preview,
        child: FlashQuestApp(
          deckRepository: decks,
          flashcardRepository: cards,
          initialize: initialize,
        ),
      ),
    );
    await tester.pump();
    if (animate) await tester.pump(const Duration(milliseconds: 450));
  }

  Future<void> capture(WidgetTester tester, String name) => capturePreview(
    tester,
    preview,
    name,
    outputDirectory: 'build/startup-preview',
    settle: false,
  );

  testWidgets(
    'centered purple wordmark replaces the logo while initialization is pending',
    (tester) async {
      final gate = Completer<void>();
      var attempts = 0;
      await start(tester, () {
        attempts++;
        return gate.future;
      });
      expect(attempts, 1);
      expect(decks.loadCalls, 0);
      expect(find.byType(DeckListScreen), findsNothing);
      expect(find.text('FlashQuest'), findsOneWidget);
      expect(find.text('Study smarter, one card at a time.'), findsNothing);
      expect(find.text('Getting your flashcards ready...'), findsOneWidget);
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        const Color(0xFFF4EFFF),
      );
      expect(find.byType(Image), findsNothing);
      final title = tester.widget<Text>(find.text('FlashQuest'));
      expect(title.style!.color, const Color(0xFF6F4BB8));
      expect(title.style!.fontWeight, FontWeight.bold);
      final center = tester.getCenter(find.text('FlashQuest'));
      expect(center.dx, closeTo(206, .1));
      expect(center.dy, closeTo(446, .1));
      await capture(tester, '01-initializing');
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Your decks'), findsOneWidget);
      expect(find.byKey(const ValueKey('startup-logo')), findsNothing);
      expect(decks.loadCalls, 1);
    },
  );

  testWidgets(
    'early readiness fades in, holds, then crossfades once at the 1900ms minimum',
    (tester) async {
      final before = tester.binding.clock.now();
      var attempts = 0;
      await start(tester, () async {
        attempts++;
      }, animate: false);
      await tester.pump();
      expect(find.byType(DeckListScreen), findsNothing);
      expect(tester.binding.clock.now(), before);
      expect(attempts, 1);
      double opacity(String key) => tester
          .widget<FadeTransition>(find.byKey(ValueKey(key)))
          .opacity
          .value;
      expect(opacity('startup-fade'), 0);
      await tester.pump(const Duration(milliseconds: 200));
      expect(opacity('startup-fade'), inExclusiveRange(0, 1));
      await tester.pump(const Duration(milliseconds: 200));
      expect(opacity('startup-fade'), 1);
      await tester.pump(const Duration(milliseconds: 1199));
      expect(find.byType(DeckListScreen), findsNothing);
      expect(opacity('startup-fade'), 1);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(find.byType(DeckListScreen), findsOneWidget);
      expect(opacity('startup-exit'), 1);
      expect(
        find.byKey(const ValueKey('create-deck')).hitTestable(),
        findsNothing,
      );
      await tester.pump(const Duration(milliseconds: 150));
      expect(opacity('startup-exit'), closeTo(.5, .01));
      await tester.pump(const Duration(milliseconds: 149));
      expect(find.byKey(const ValueKey('startup-exit')), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.byKey(const ValueKey('startup-exit')), findsNothing);
      expect(
        tester.binding.clock.now().difference(before),
        const Duration(milliseconds: 1900),
      );
      expect(find.text('Your decks'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('create-deck')).hitTestable(),
        findsOneWidget,
      );
      expect(
        Navigator.of(tester.element(find.text('Your decks'))).canPop(),
        isFalse,
      );
      await tester.pumpAndSettle();
      expect(decks.loadCalls, 1);
    },
  );

  testWidgets(
    'initialization error stays on splash and repeated Retry taps make one attempt',
    (tester) async {
      var attempts = 0;
      final retryGate = Completer<void>();
      await start(tester, () {
        if (++attempts == 1) throw StateError('Private SQL and database path');
        return retryGate.future;
      });
      await tester.pumpAndSettle();
      expect(
        find.textContaining('couldn’t open your saved flashcards'),
        findsOneWidget,
      );
      expect(find.textContaining('Private SQL'), findsNothing);
      expect(find.byType(DeckListScreen), findsNothing);
      expect(decks.loadCalls, 0);
      await capture(tester, '02-initialization-error');
      final retry = tester
          .widget<FilledButton>(find.byKey(const ValueKey('retry-startup')))
          .onPressed!;
      retry();
      retry();
      await tester.pump();
      await tester.pump();
      expect(attempts, 2);
      expect(find.byKey(const ValueKey('retry-startup')), findsNothing);
      expect(find.text('Getting your flashcards ready...'), findsOneWidget);
      expect(find.byType(DeckListScreen), findsNothing);
      retryGate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Your decks'), findsOneWidget);
      expect(decks.loadCalls, 1);
      expect(
        Navigator.of(tester.element(find.text('Your decks'))).canPop(),
        isFalse,
      );
    },
  );

  testWidgets(
    'backgrounding, resuming and rebuilding never repeat startup or navigation',
    (tester) async {
      final gate = Completer<void>();
      var attempts = 0;
      await start(tester, () {
        attempts++;
        return gate.future;
      });
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      gate.complete();
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(640, 360);
      await tester.pumpAndSettle();
      expect(attempts, 1);
      expect(decks.loadCalls, 1);
      expect(find.byType(DeckListScreen), findsOneWidget);
      expect(
        Navigator.of(tester.element(find.text('Your decks'))).canPop(),
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final fail in [false, true]) {
    testWidgets(
      'disposal before ${fail ? 'failure' : 'success'} never opens a dashboard',
      (tester) async {
        final gate = Completer<void>();
        await start(tester, () => gate.future);
        await tester.pumpWidget(const SizedBox());
        if (fail) {
          gate.completeError(Exception('Initialization failed'));
        } else {
          gate.complete();
        }
        await tester.pumpAndSettle();
        expect(decks.loadCalls, 0);
        expect(find.byType(DeckListScreen), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final setting in {
    'disabled animations': const FakeAccessibilityFeatures(
      disableAnimations: true,
    ),
    'accessible navigation': const FakeAccessibilityFeatures(
      accessibleNavigation: true,
    ),
  }.entries) {
    testWidgets('startup respects ${setting.key}', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue = setting.value;
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final gate = Completer<void>();
      await start(tester, () => gate.future, animate: false);
      final startedAt = tester.binding.clock.now();
      expect(
        tester
            .widget<FadeTransition>(find.byKey(const ValueKey('startup-fade')))
            .opacity
            .value,
        1,
      );
      expect(find.byKey(const ValueKey('startup-scale')), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byIcon(Icons.hourglass_empty_rounded), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1600));
      gate.complete();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(
        tester
            .widget<FadeTransition>(find.byKey(const ValueKey('startup-exit')))
            .opacity
            .value,
        1,
      );
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.text('Your decks'), findsOneWidget);
      expect(
        tester.binding.clock.now().difference(startedAt),
        const Duration(milliseconds: 1900),
      );
    });
  }

  testWidgets(
    'slow initialization holds the wordmark and only adds its exit fade',
    (tester) async {
      final gate = Completer<void>();
      await start(tester, () => gate.future);
      await tester.pump(const Duration(seconds: 4));
      expect(find.byType(DeckListScreen), findsNothing);
      expect(
        tester
            .widget<FadeTransition>(find.byKey(const ValueKey('startup-fade')))
            .opacity
            .value,
        1,
      );
      final readyAt = tester.binding.clock.now();
      gate.complete();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 299));
      expect(find.byKey(const ValueKey('startup-exit')), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.byKey(const ValueKey('startup-exit')), findsNothing);
      expect(
        tester.binding.clock.now().difference(readyAt),
        const Duration(milliseconds: 300),
      );
      expect(decks.loadCalls, 1);
    },
  );

  testWidgets(
    'errors are shown immediately and Retry does not restart the minimum',
    (tester) async {
      var attempts = 0;
      await start(tester, () async {
        if (++attempts == 1) throw Exception('Storage failed');
      }, animate: false);
      await tester.pump();
      expect(find.byKey(const ValueKey('retry-startup')), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      final retriedAt = tester.binding.clock.now();
      await tester.tap(find.byKey(const ValueKey('retry-startup')));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('startup-exit')), findsNothing);
      expect(
        tester.binding.clock.now().difference(retriedAt),
        const Duration(milliseconds: 300),
      );
      expect(attempts, 2);
      expect(decks.loadCalls, 1);
    },
  );

  for (final exit in [false, true]) {
    testWidgets(
      'disposal during ${exit ? 'exit' : 'minimum hold'} cancels presentation safely',
      (tester) async {
        await start(tester, () async {}, animate: false);
        if (exit) {
          await tester.pump(const Duration(milliseconds: 1600));
          await tester.pump();
        }
        final reads = decks.loadCalls;
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 3));
        expect(tester.takeException(), isNull);
        expect(decks.loadCalls, reads);
      },
    );
  }

  for (final layout in [
    (name: 'small', size: const Size(320, 640), scale: 1.0),
    (name: 'large-text', size: const Size(320, 640), scale: 1.8),
    (name: 'landscape', size: const Size(640, 360), scale: 1.8),
  ]) {
    testWidgets('loading and error are readable with ${layout.name} layout', (
      tester,
    ) async {
      final gate = Completer<void>();
      await start(
        tester,
        () => gate.future,
        size: layout.size,
        scale: layout.scale,
      );
      await capture(tester, '03-loading-${layout.name}');
      final titleBounds = tester.getRect(find.text('FlashQuest'));
      expect(titleBounds.left, greaterThanOrEqualTo(23));
      expect(titleBounds.right, lessThanOrEqualTo(layout.size.width - 23));
      expect(
        tester.getBottomRight(find.text('Getting your flashcards ready...')).dy,
        lessThanOrEqualTo(layout.size.height),
      );
      expect(tester.takeException(), isNull);
      tester.view.physicalSize = Size(layout.size.height, layout.size.width);
      await tester.pump();
      gate.completeError(Exception('Storage error'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('retry-startup')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('retry-startup')).hitTestable(),
        findsOneWidget,
      );
      await capture(tester, '04-error-rotated-${layout.name}');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('startup loading and Retry meet Android accessibility checks', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      final gate = Completer<void>();
      await start(tester, () => gate.future);
      expect(
        find.bySemanticsLabel('Getting your flashcards ready...'),
        findsOneWidget,
      );
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      gate.completeError(Exception('Storage error'));
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
    } finally {
      semantics.dispose();
    }
  });
}
