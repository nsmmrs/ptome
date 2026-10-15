@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:ptome/src/parallel.dart';
import 'package:test/test.dart';

/// The sum of the squares below [n].
final class _Squares extends Job<int> {
  const new(this.n);

  final int n;

  @override
  int run() {
    var sum = 0;
    for (var i = 0; i < n; i++) {
      sum += i * i;
    }
    return sum;
  }
}

/// Waits until the file [latch] exists (busy, or on a timer when
/// [async]), then gives its [name]: a job that ends when the test says so,
/// whatever the machine's speed. (It gives up after a minute, for the test
/// to fail rather than hang.)
final class _Waits extends Job<String> {
  const new(this.name, this.latch, {this.async = false});

  final String name;
  final String latch;
  final bool async;

  @override
  FutureOr<String> run() => async ? _later() : _busy();

  String _busy() {
    final watch = Stopwatch()..start();
    while (!File(latch).existsSync() && watch.elapsed < _patience) {
      sleep(const Duration(milliseconds: 1));
    }
    return name;
  }

  Future<String> _later() async {
    final watch = Stopwatch()..start();
    while (!File(latch).existsSync() && watch.elapsed < _patience) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    return name;
  }

  static const Duration _patience = Duration(minutes: 1);
}

/// A file for a [_Waits] job to wait on, in a folder of its own.
String _latch() {
  final dir = Directory.systemTemp.createTempSync('parallel_test.');
  addTearDown(() => dir.deleteSync(recursive: true));
  return '${dir.path}/go';
}

final class _Throws extends Job<int> {
  const new();

  @override
  int run() => throw StateError('no luck');
}

/// Waits [millis] (on a timer), then gives its [name], or fails when it
/// [fails].
final class _Later extends Job<String> {
  const new(this.name, this.millis, {this.fails = false});

  final String name;
  final int millis;
  final bool fails;

  @override
  Future<String> run() async {
    await Future<void>.delayed(Duration(milliseconds: millis));
    if (fails) throw StateError('too late');
    return name;
  }
}

/// Ends its worker.
final class _Dies extends Job<int> {
  const new();

  @override
  int run() {
    Isolate.current.kill(priority: Isolate.immediate);
    return 0;
  }
}

void main() {
  test('every pool gives the serial results', () async {
    final jobs = [for (var n = 0; n < 40; n++) _Squares(n * 1000)];
    final serial = await Future.wait(jobs.map(Parallel.serial.submit));
    final pool = Parallel.ofSize(3);
    expect(pool.workers, 3);
    expect(await Future.wait(jobs.map(pool.submit)), serial);
  });

  test('idle workers pull the next job', () async {
    final pool = Parallel.ofSize(2);
    final latch = _latch();
    final finished = <String>[];
    final long = pool.submit(_Waits('long', latch)).then(finished.add);
    // The short ones on the other worker, one after another, while the
    // long one holds the first (dealt in turn, the third would wait for
    // it, and the long one ends only once the short ones have).
    await Future.wait([
      for (final name in const ['a', 'b', 'c'])
        pool.submit(_Later(name, 0)).then(finished.add),
    ]);
    File(latch).createSync();
    await long;
    expect(finished, ['a', 'b', 'c', 'long']);
  });

  test('a job that fails fails its future', () async {
    await expectLater(
      Parallel.ofSize(2).submit(const _Throws()),
      throwsA(
        isA<JobFailure>().having(
          (failure) => failure.message,
          'message',
          contains('no luck'),
        ),
      ),
    );
    await expectLater(
      Parallel.serial.submit(const _Throws()),
      throwsA(isA<StateError>()),
    );
  });

  test('a job that waits holds its worker until it ends', () async {
    final pool = Parallel.ofSize(2);
    final latch = _latch();
    final finished = <String>[];
    final long = pool
        .submit(_Waits('long', latch, async: true))
        .then(finished.add);
    await Future.wait([
      for (final name in const ['a', 'b'])
        pool.submit(_Later(name, 0)).then(finished.add),
    ]);
    File(latch).createSync();
    await long;
    expect(finished, ['a', 'b', 'long']);
    await expectLater(
      pool.submit(const _Later('x', 1, fails: true)),
      throwsA(
        isA<JobFailure>().having(
          (f) => f.message,
          'message',
          'Bad state: too late',
        ),
      ),
    );
    expect(await Parallel.serial.submit(const _Later('s', 1)), 's');
    await expectLater(
      Parallel.serial.submit(const _Later('s', 1, fails: true)),
      throwsA(isA<StateError>()),
    );
  });

  test('a worker that ends fails its job and is replaced', () async {
    final pool = Parallel.ofSize(4);
    await expectLater(pool.submit(const _Dies()), throwsA(isA<JobFailure>()));
    expect(await pool.submit(const _Squares(4)), 14);
  });

  test('the jobs attribute sets the workers', () {
    expect(Parallel.forAttribute('1').workers, 0);
    expect(Parallel.forAttribute('5').workers, 5);
    expect(Parallel.forAttribute(null).workers, isNot(1));
    expect(Parallel.forAttribute('many').workers, greaterThanOrEqualTo(0));
    Parallel.nested = true;
    addTearDown(() => Parallel.nested = false);
    expect(Parallel.forAttribute('5').workers, 0);
  });
}
