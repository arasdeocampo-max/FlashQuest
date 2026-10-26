import 'dart:async';

import 'package:flashquest_drill/features/startup/startup_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'coalesces concurrent starts and never repeats successful initialization',
    () async {
      final gate = Completer<void>();
      var attempts = 0;
      final model = StartupViewModel(() {
        attempts++;
        return gate.future;
      });
      addTearDown(model.dispose);
      final first = model.initialize();
      expect(identical(first, model.initialize()), isTrue);
      await Future<void>.value();
      expect(attempts, 1);
      expect(model.state, StartupState.loading);
      gate.complete();
      await first;
      expect(model.state, StartupState.ready);
      await model.initialize();
      expect(attempts, 1);
    },
  );

  test(
    'a synchronous failure is sanitized and Retry makes one fresh attempt',
    () async {
      var attempts = 0;
      final retryGate = Completer<void>();
      final model = StartupViewModel(() {
        attempts++;
        if (attempts == 1) throw StateError('Private database path and SQL');
        return retryGate.future;
      });
      addTearDown(model.dispose);
      await model.initialize();
      expect(model.state, StartupState.error);
      expect(model.error, contains('couldn’t open your saved flashcards'));
      expect(model.error, isNot(contains('Private')));
      final retry = model.initialize();
      expect(identical(retry, model.initialize()), isTrue);
      await Future<void>.value();
      expect(model.state, StartupState.loading);
      expect(model.error, isNull);
      expect(attempts, 2);
      retryGate.complete();
      await retry;
      expect(model.state, StartupState.ready);
    },
  );

  test(
    'disposal before the queued attempt prevents initialization work',
    () async {
      var attempts = 0;
      final model = StartupViewModel(() async {
        attempts++;
      });
      final pending = model.initialize();
      model.dispose();
      await pending;
      expect(attempts, 0);
    },
  );

  test('an asynchronous failure remains retryable', () async {
    var attempts = 0;
    final model = StartupViewModel(() async {
      if (++attempts < 3) throw Exception('Private failure');
    });
    addTearDown(model.dispose);
    await model.initialize();
    await model.initialize();
    expect(model.state, StartupState.error);
    await model.initialize();
    expect(model.state, StartupState.ready);
    expect(attempts, 3);
  });

  test(
    'a reentrant loading listener cannot start another initializer',
    () async {
      var attempts = 0;
      final model = StartupViewModel(() async {
        attempts++;
      });
      addTearDown(model.dispose);
      model.addListener(() {
        unawaited(model.initialize());
      });
      await model.initialize();
      expect(attempts, 1);
      expect(model.state, StartupState.ready);
    },
  );

  for (final fail in [false, true]) {
    test(
      'disposing during ${fail ? 'failed' : 'successful'} initialization suppresses late notifications',
      () async {
        final gate = Completer<void>();
        var attempts = 0;
        var notifications = 0;
        final model = StartupViewModel(() {
          attempts++;
          return gate.future;
        });
        model.addListener(() => notifications++);
        final pending = model.initialize();
        await Future<void>.value();
        expect(notifications, 1);
        model.dispose();
        if (fail) {
          gate.completeError(Exception('Private failure'));
        } else {
          gate.complete();
        }
        await pending;
        expect(notifications, 1);
        expect(model.state, StartupState.loading);
        await model.initialize();
        expect(attempts, 1);
      },
    );
  }
}
