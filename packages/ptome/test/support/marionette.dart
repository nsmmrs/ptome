/// Firefox driven through Marionette, its remote protocol (length-prefixed
/// JSON over TCP): a page loaded, then screenshot once its fonts are ready.
/// (`firefox --screenshot` takes the page as soon as it has loaded, which
/// can be before its @font-face fonts have: under load, a shot in the
/// fallback fonts.)
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// A headless Firefox under Marionette.
final class Marionette {
  new _(this._process, this._socket) {
    _socket.listen(_receive, onDone: () => _closed = true);
  }

  final Process _process;
  final Socket _socket;
  final List<int> _buffer = [];
  final Map<int, Completer<Map<String, Object?>>> _pending = {};
  Completer<void>? _hello = Completer<void>();
  var _next = 1;
  var _closed = false;

  /// Starts [firefox] headless with a fresh profile in [profile], its
  /// window [width] CSS pixels wide.
  static Future<Marionette> start(
    String firefox,
    Directory profile, {
    required int width,
  }) async {
    profile.createSync(recursive: true);
    // (Port 0: Firefox picks one and writes it into the profile.)
    File('${profile.path}/user.js').writeAsStringSync(
      'user_pref("marionette.port", 0);\n'
      'user_pref("browser.shell.checkDefaultBrowser", false);\n'
      'user_pref("datareporting.policy.dataSubmissionEnabled", false);\n'
      // (Scrollbars that take no room: the page as wide as the window.)
      'user_pref("ui.useOverlayScrollbars", 1);\n'
      'user_pref("layout.testing.overlay-scrollbars.always-visible", false);\n',
    );
    final portFile = File('${profile.path}/MarionetteActivePort');
    if (portFile.existsSync()) portFile.deleteSync();
    final process = await Process.start(firefox, [
      '--headless',
      '--marionette',
      '--no-remote',
      '--profile',
      profile.path,
      '--width',
      '$width',
      '--height',
      '1000',
    ]);
    unawaited(process.stdout.drain<void>());
    unawaited(process.stderr.drain<void>());
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    while (!portFile.existsSync() ||
        int.tryParse(portFile.readAsStringSync().trim()) == null) {
      if (DateTime.now().isAfter(deadline)) {
        process.kill();
        throw StateError('Firefox started no Marionette server');
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    final port = int.parse(portFile.readAsStringSync().trim());
    final socket = await Socket.connect(InternetAddress.loopbackIPv4, port);
    final marionette = Marionette._(process, socket);
    await marionette._hello!.future;
    await marionette._command('WebDriver:NewSession', {
      'capabilities': <String, Object>{},
    });
    return marionette;
  }

  void _receive(List<int> data) {
    _buffer.addAll(data);
    while (true) {
      final colon = _buffer.indexOf(0x3a);
      if (colon < 0) return;
      final length = int.parse(ascii.decode(_buffer.sublist(0, colon)));
      if (_buffer.length < colon + 1 + length) return;
      final message = jsonDecode(
        utf8.decode(_buffer.sublist(colon + 1, colon + 1 + length)),
      );
      _buffer.removeRange(0, colon + 1 + length);
      if (_hello case final hello?) {
        // The server's greeting.
        _hello = null;
        hello.complete();
        continue;
      }
      // [1, id, error, result]
      if (message case [1, final int id, final error, final result]) {
        final completer = _pending.remove(id);
        if (completer == null) continue;
        if (error != null) {
          completer.completeError(StateError('Marionette: $error'));
        } else {
          completer.complete(switch (result) {
            final Map<String, Object?> map => map,
            _ => <String, Object?>{},
          });
        }
      }
    }
  }

  Future<Map<String, Object?>> _command(
    String name,
    Map<String, Object> parameters,
  ) {
    if (_closed) throw StateError('Marionette: connection closed');
    final id = _next++;
    final completer = Completer<Map<String, Object?>>();
    _pending[id] = completer;
    final body = utf8.encode(jsonEncode([0, id, name, parameters]));
    _socket
      ..add(ascii.encode('${body.length}:'))
      ..add(body);
    return completer.future.timeout(const Duration(seconds: 120));
  }

  /// The whole page at [url] as a PNG, once it has loaded, its fonts and
  /// images are ready, and two frames have been painted after.
  Future<Uint8List> screenshot(String url) async {
    await _command('WebDriver:Navigate', {'url': url});
    await _command('WebDriver:ExecuteAsyncScript', {
      'script':
          'const done = arguments[arguments.length - 1];'
          // Every face the page declares loaded (fonts.ready alone
          // resolves before layout has asked for any), every image
          // decoded, then two frames painted.
          'Promise.all([...document.fonts].map((f) => f.load()'
          '.catch(() => null)))'
          '.then(() => Promise.all([...document.images].map((i) => '
          'i.decode().catch(() => null))))'
          '.then(() => document.fonts.ready)'
          '.then(() => requestAnimationFrame(() => '
          'requestAnimationFrame(() => done(true))));',
      'args': <Object>[],
    });
    final result = await _command('WebDriver:TakeScreenshot', {
      'full': true,
      'hash': false,
    });
    return switch (result['value']) {
      final String png => base64.decode(png),
      _ => throw StateError('Marionette: no screenshot'),
    };
  }

  /// Ends the session and Firefox.
  Future<void> close() async {
    try {
      await _command(
        'Marionette:Quit',
        <String, Object>{},
      ).timeout(const Duration(seconds: 10));
    } on Object {
      // (Firefox may close the connection as it quits.)
    }
    await _socket.close();
    _process.kill();
    await _process.exitCode.timeout(
      const Duration(seconds: 20),
      onTimeout: () => 0,
    );
  }
}
