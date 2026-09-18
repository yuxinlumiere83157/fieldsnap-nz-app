import 'dart:async';
import 'dart:isolate';

/// Runs a piece of work off the Flutter UI isolate.
///
/// The whole point of this boundary is that inference must not run on the main isolate
/// (Milestone 1's NFR3). It is an interface, not a bare `compute()` call, so widget tests can
/// inject a fake and assert the UI never blocks, and so the real implementation is the only
/// place that knows about `Isolate`.
abstract class BackgroundRunner {
  /// Runs [work] on a background isolate and returns its result.
  ///
  /// [work] must be a top-level or static function (isolates cannot capture closures), and its
  /// argument and return value must be transferable.
  Future<R> run<A, R>(FutureOr<R> Function(A) work, A argument);

  /// Whether this runner actually executes elsewhere. A fake returns false, which lets a test
  /// assert "this path does not block the UI" without pretending it is a real isolate.
  bool get isIsolate;
}

/// Production implementation: a real `Isolate.run`.
class IsolateBackgroundRunner implements BackgroundRunner {
  const IsolateBackgroundRunner();

  @override
  bool get isIsolate => true;

  @override
  Future<R> run<A, R>(FutureOr<R> Function(A) work, A argument) {
    return Isolate.run<R>(() async => await work(argument));
  }
}

/// In-process runner used by tests and by platforms where spawning is undesirable.
///
/// It deliberately reports [isIsolate] = false so no test can accidentally claim that this path
/// proves off-main-isolate execution.
class InlineBackgroundRunner implements BackgroundRunner {
  const InlineBackgroundRunner();

  @override
  bool get isIsolate => false;

  @override
  Future<R> run<A, R>(FutureOr<R> Function(A) work, A argument) async {
    return await work(argument);
  }
}

/// Reasons this layer can report without importing the inference implementation.
class BackgroundFailure {
  static const String invalidInput = 'invalidInput';
  static const String inferenceFailed = 'inferenceFailed';
}
